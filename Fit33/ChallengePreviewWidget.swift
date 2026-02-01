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
        invite.type ?? .steps
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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: themeColor.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(0.5), gradientColors[1].opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
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
                
                Text("\(invite.creatorName ?? "Someone") wants to challenge you!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
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
            // Challenge type icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.15) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: challengeType.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Challenge title
                HStack(spacing: 6) {
                    Text(invite.displayEmoji)
                        .font(.title3)
                    
                    Text(invite.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.15))
                )
            }
            .disabled(isAccepting || isDeclining)
            
            // Accept button
            Button(action: acceptChallenge) {
                HStack(spacing: 6) {
                    if isAccepting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Accept Challenge")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(isAccepting || isDeclining)
        }
        .padding(16)
    }
    
    // MARK: - Actions
    
    private func acceptChallenge() {
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            let success = await challengeService.respondToChallenge(challengeId: invite.challengeId, accept: true)
            if success {
                HapticManager.notification(.success)
                onAccept()
            } else {
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
    
    private var challengeType: ChallengeType {
        challenge.type ?? .steps
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: challengeType.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: challengeType.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text(challenge.title)
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
                
                // Progress comparison
                HStack(spacing: 0) {
                    // My progress
                    VStack(spacing: 4) {
                        Text(formatProgress(challenge.myTotalProgress))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
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
                    
                    // Opponent progress
                    VStack(spacing: 4) {
                        Text(formatProgress(challenge.opponentTotalProgress))
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
                
                // Days remaining
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(challenge.daysRemaining) days left")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [challengeType.gradientColors[0].opacity(0.3), challengeType.gradientColors[1].opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatProgress(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
}

// MARK: - Friend Challenge Row (for Friend Profile challenges list)

struct FriendChallengeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: FriendChallenge
    let onTap: () -> Void
    
    private var challengeType: ChallengeType {
        challenge.type ?? .steps
    }
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark 
            ? [Color(white: 0.18), Color(white: 0.12)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Type icon with gradient circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: challengeType.gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: challengeType.color.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: challengeType.icon)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                
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
