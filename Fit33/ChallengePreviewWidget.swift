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
    
    // Theme colors based on challenge type
    private var themeColor: Color {
        challengeType.color
    }
    
    private var gradientColors: [Color] {
        challengeType.gradientColors
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            VStack(spacing: 0) {
                // Header - Challenge info
                headerSection
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Challenge details
                challengeDetailsSection
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Action buttons
                actionButtonsSection
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(cardBackground)
                    
                    // Subtle gradient glow overlay
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [themeColor.opacity(0.06), .clear, themeColor.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(0.6), gradientColors[1].opacity(0.2), gradientColors[0].opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 20, x: 0, y: 8)
            .shadow(color: themeColor.opacity(0.08), radius: 40, x: 0, y: 16)
        }
        .confirmationDialog(
            "Decline this challenge?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                declineChallenge()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll miss out on competing with \(invite.creatorName ?? "your friend")!")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            // Challenger avatar with gradient ring
            challengerAvatarView
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Challenge")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeColor)
                    
                    // NEW badge
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(themeColor))
                }
                
                Text("\(invite.creatorName ?? "Someone") wants to challenge...")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Username if available
                if let username = invite.creatorUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Time ago
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatSmartDate(invite.invitedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
    
    // MARK: - Challenger Avatar View
    
    private var challengerAvatarView: some View {
        ZStack(alignment: .topTrailing) {
            CachedFriendPhoto(
                friendId: invite.creatorId.uuidString,
                photoUrl: invite.creatorPhotoUrl,
                name: invite.creatorName ?? "Challenger",
                size: 52,
                showGradientRing: true,
                gradientColors: gradientColors
            )
            
            // Pulsing dot for new challenge
            PulsingRedDot()
                .offset(x: 2, y: -2)
        }
    }
    
    // MARK: - Challenge Details Section
    
    private var challengeDetailsSection: some View {
        HStack(spacing: 16) {
            // Trophy icon
            Image(systemName: "trophy.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Challenge title — just the mode emoji + clean title
                Text(invite.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Challenge details
                HStack(spacing: 12) {
                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text("\(invite.durationDays) days")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    // Target
                    if let target = invite.dailyTarget {
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.caption2)
                            Text("\(target.formatted()) \(invite.targetUnit)/day")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                // Start date
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Starts \(invite.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Decline button
            Button(action: {
                print("❌ [CHALLENGE ACCEPT] Decline button tapped")
                HapticManager.impact(.light)
                showingDeclineConfirmation = true
            }) {
                HStack(spacing: 6) {
                    if isDeclining {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.primary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.15))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)
            
            // Accept button
            Button(action: acceptChallenge) {
                HStack(spacing: 6) {
                    if isAccepting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isDeclining)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Actions
    
    private func acceptChallenge() {
        print("✅ [CHALLENGE ACCEPT] Accept button tapped for challenge: \(invite.title)")
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            print("📤 [CHALLENGE ACCEPT] Calling respondToChallenge...")
            let success = await challengeService.respondToChallenge(challengeId: invite.challengeId, accept: true)
            if success {
                print("✅ [CHALLENGE ACCEPT] Challenge accepted successfully!")
                print("🔄 [CHALLENGE ACCEPT] Refreshing challenges...")
                // Immediately refresh to show active challenge
                await challengeService.fetchActiveChallenges()
                await challengeService.fetchPendingInvites()
                HapticManager.notification(.success)
                onAccept()
            } else {
                print("❌ [CHALLENGE ACCEPT] Failed to accept challenge")
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
                            .font(.system(size: 12))
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
    
    private var resolvedType: ChallengeType {
        challenge.resolvedType
    }
    
    private var resolver: ChallengeProgressResolver {
        ChallengeProgressResolver.shared
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Header — type-aware
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Text(resolvedType.emoji)
                            .font(.system(size: 14))
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
                                .font(.system(size: 10))
                            Text("Leading")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.yellow.opacity(0.2))
                        )
                    } else {
                        Text("Behind")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
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
                    
                    // Opponent progress (from server)
                    VStack(spacing: 4) {
                        Text(resolver.formatValue(challenge.opponentTotalProgress, unit: challenge.targetUnit, type: resolvedType))
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
                
                // Live progress bar + days remaining
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
                        Text("\(Int(resolver.progressPercentage(for: challenge) * 100))% of daily goal")
                            .font(.caption2)
                            .foregroundColor(resolvedType.color)
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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: resolvedType.color.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [resolvedType.gradientColors[0].opacity(0.3), resolvedType.gradientColors[1].opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark 
            ? [Color(white: 0.18), Color(white: 0.12)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Type emoji - floating
                Text(challengeType.emoji)
                    .font(.system(size: 32))
                
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
                        .font(.system(size: 18))
                        .foregroundColor(challenge.amWinning ? .yellow : .secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: challengeType.gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
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
    @State private var glowRotation: Double = 0
    @State private var nudgedUserIds: Set<UUID> = []
    @State private var isNudging: UUID? = nil
    
    private let challengeColor = Color(red: 0.0, green: 0.9, blue: 0.7) // Green teal
    
    private var challengeType: ChallengeType {
        challenge.resolvedType
    }
    
    private var themeColor: Color { challengeColor }
    private var gradientColors: [Color] { [Color(red: 0.0, green: 0.9, blue: 0.7), .teal] }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
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
                    .font(.system(size: 28))
            }
            .padding(16)
            
            Divider().padding(.horizontal, 16)
            
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
                            .overlay(Circle().stroke(cardBackground, lineWidth: 1.5))
                        }
                    }
                    
                    Text("with \(otherMemberNames.joined(separator: " & "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider().padding(.horizontal, 16)
            
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
                                .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 12, weight: .semibold))
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
            .padding(16)
        }
        .background(
            ZStack {
                // Animated glowing border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                challengeColor.opacity(0.7),
                                Color.teal.opacity(0.5),
                                challengeColor.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                challengeColor.opacity(0.2),
                                Color.mint.opacity(0.4),
                                challengeColor.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(glowRotation)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackground)
                
                // Inner border for definition
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [challengeColor.opacity(0.5), Color.teal.opacity(0.3), challengeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: challengeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: challengeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                glowRotation = 360
            }
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
