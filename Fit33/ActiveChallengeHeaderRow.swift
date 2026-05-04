//
//  ActiveChallengeHeaderRow.swift
//  Fit33
//
//  Header row for the dashboard's active 1v1 / accountability challenge
//  card. Owns the local `@State` for the battle-cry sheet so the row
//  can be embedded anywhere in the dashboard (single carousel, stacked
//  carousel, etc.) without each call site duplicating that state.
//
//  Tap behavior:
//    • Row body (icon + title + subtitle area)  → push ChallengeDetailView
//    • Smiley button (competition mode only)    → present BattleCryPickerSheet
//    • Mode badge 🤝 (accountability mode only) → passive (no tap)
//    • Chevron                                  → push ChallengeDetailView
//
//  Visual notes:
//    • The smiley mirrors the friend-tab `emojiButton` exactly
//      (`face.smiling` SF Symbol, orange→red gradient, `.ds_heading3`)
//      to keep the "tap me to send a reaction" affordance consistent
//      across the app.
//    • For accountability mode we leave the existing 🤝 badge in place
//      because it's a passive mode indicator, not an action affordance.
//      Swap it for the smiley too if we ever want power-ups to be a
//      one-tap shortcut from the dashboard.
//

import SwiftUI

struct ActiveChallengeHeaderRow: View {
    let challenge: ActiveChallenge
    
    @State private var showingReactionPicker = false
    
    private var resolvedType: ChallengeType { challenge.resolvedType }
    private var typeColor: Color { resolvedType.color }
    private var typeGradient: [Color] { resolvedType.gradientColors }
    private var isAccountability: Bool { challenge.mode == .accountability }
    private var opponentFirst: String {
        challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NavigationLink(value: challenge) {
                navigationContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            modeAffordance

            NavigationLink(value: challenge) {
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.sm)
        // Battle-cry shout bubble (2026-05-02). Floats above the row
        // when there's an active battle cry on this challenge.
        // Self-aligns horizontally:
        //   • Incoming (they sent it) → hugs the RIGHT edge, tail points
        //     down-right at the opponent's photo.
        //   • Outgoing (I sent it)    → hugs the LEFT edge, tail points
        //     down-left at the type icon.
        // Vertical offset keeps both at the same height regardless of
        // direction.
        .overlay(alignment: .top) {
            BattleCryShoutBubble(challengeId: challenge.challengeId)
                .padding(.horizontal, Spacing.md)
                .offset(y: Spacing.sm + 35)
                .allowsHitTesting(true)
                .zIndex(20)
        }
        .sheet(isPresented: $showingReactionPicker) {
            BattleCryPickerSheet(
                mode: isAccountability ? .accountability : .competition,
                typeColor: typeColor,
                gradient: typeGradient,
                recipientLabel: opponentFirst,
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
    
    private var navigationContent: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2.5
                    )
                    .frame(width: 36, height: 36)
                Text(resolvedType.emoji)
                    .font(.ds_heading3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(isAccountability ? "with \(opponentFirst)" : "vs \(opponentFirst)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(challenge.daysRemaining)d left")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(typeColor)
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    @ViewBuilder
    private var modeAffordance: some View {
        if isAccountability {
            Text("🤝")
                .font(.ds_bodyRegular)
        } else {
            Button {
                HapticManager.impact(.light)
                showingReactionPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.ds_heading3)
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .buttonStyle(.plain)
            // Extra trailing padding so the smiley reads as its own
            // affordance instead of bleeding into the chevron's tap
            // target. The HStack's 10pt spacing alone left them too
            // visually flush.
            .padding(.trailing, 8)
            .accessibilityLabel("Send a battle cry")
            .accessibilityHint("Opens the reaction picker without leaving the dashboard")
        }
    }
}
