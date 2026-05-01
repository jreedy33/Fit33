import SwiftUI

// =============================================================================
// NotificationPrimerSheet — soft-prompt before iOS notification dialog
// (Smart Notification Engine — Phase 1, refined in Phase 4).
// =============================================================================
//
// Why: Apple shows the system permission dialog ONCE per install. If the user
// taps "Don't Allow" the only way back is through Settings. The cold dialog
// has zero context — users hit it with no idea WHY the app wants pushes.
//
// What this sheet does:
//   - Renders 3 default-on category preview rows so the user sees concrete
//     examples ("Manuel pulled ahead 2K — talk smack", "Recovery red — keep
//     RPE under 7", "🔥 25-day streak at risk").
//   - "Sounds good — turn on" → triggers the system dialog via the
//     PushPermissionCoordinator.
//   - "Not now" → defers without consuming Apple's one-shot dialog budget;
//     the user can still trigger the ask later from Settings.
//
// Mounted by:
//   - `MainTabView` (post-onboarding, post-auth)
//   - `NewOnboardingView+Completion` (last step of onboarding, BEFORE the
//     final "complete onboarding" tap so the user sees value first)
//
// Keep visual style consistent with the existing onboarding sheets — same
// `.ds_*` design tokens, same corner-radius / shadow rhythm.
// =============================================================================

struct NotificationPrimerSheet: View {
    @ObservedObject var coordinator = PushPermissionCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.orange.opacity(0.85), .pink.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 76, height: 76)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 28)

                Text("Stay in the game")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)

                Text("Get smart, personal nudges that actually move the needle. No spam — promise.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Examples
            VStack(spacing: 14) {
                primerRow(
                    icon: "shield.lefthalf.filled",
                    color: .orange,
                    title: "Rivalries & Leagues",
                    example: "“Kc is beating you 1v1 mid day — talk smack.”"
                )
                primerRow(
                    icon: "heart.text.square.fill",
                    color: .pink,
                    title: "Recovery & Sleep",
                    example: "“WHOOP recovery red — keep RPE under 7 today.”"
                )
                primerRow(
                    icon: "flame.fill",
                    color: .red,
                    title: "Streak protection",
                    example: "“🔥 25-day streak at risk — log anything to save it.”"
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    Task {
                        // Enable the default-on category set BEFORE asking for
                        // system permission. The orchestrator + send fn both
                        // gate on these per-type opt-ins, so a user who grants
                        // system permission with everything off would receive
                        // nothing — the worst possible "I said yes and got
                        // ghosted" outcome. Enabling defaults here keeps the
                        // permission contract honest.
                        await MainActor.run {
                            NotificationManager.shared.enableAllDefaultNotifications()
                        }
                        _ = await coordinator.requestSystemPermission()
                        dismiss()
                    }
                } label: {
                    Text("Sounds good — turn on")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.declinePrimer()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Text("You can fine-tune categories any time in Settings → Notifications.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled(false)
    }

    private func primerRow(icon: String, color: Color, title: String, example: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(example)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer()
        }
    }
}

#Preview {
    NotificationPrimerSheet()
}
