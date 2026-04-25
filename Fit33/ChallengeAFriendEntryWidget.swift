import SwiftUI

/// Reusable "Challenge a Friend!" entry widget — the orange trophy card shown on the
/// home dashboard and on the Friends tab when the user has no active challenges.
///
/// This is the canonical, shared rendering. Existing duplicates in
/// `DashboardView+Challenges.swift` (`getStartedChallengeWidget`) and
/// `FriendsTabView.swift` (`noChallengesCard`) remain untouched per the
/// "don't refactor large files unless explicitly requested" rule, but new
/// surfaces (e.g. the onboarding tutorial) should use this widget so the look
/// stays in sync with what users actually see in the app.
struct ChallengeAFriendEntryWidget: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Tap handler. Pass `nil` for purely decorative use (e.g. tutorial).
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .frame(height: 156)
        .background(cardBackground)
        .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .allowsHitTesting(onTap != nil)
    }

    // MARK: - Content

    private var cardContent: some View {
        let challengeColor = Color.orange

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(challengeColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 48, height: 48)

                    Text("🏆")
                        .font(.ds_heading2)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Challenge a Friend!")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Compete head-to-head on fitness goals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(challengeColor)
                    .frame(width: 4, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Steps, Workouts & More")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text("7-30 days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Daily goals")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(challengeColor)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.ds_caption)
                    Text("Challenge")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, Color(red: 1.0, green: 0.6, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xl + 4)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .offset(y: 6)
                .blur(radius: 3)

            RoundedRectangle(cornerRadius: CornerRadius.xl + 2)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)

            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.16), Color(white: 0.10)]
                            : [Color.white, Color(white: 0.98)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )

            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange.opacity(colorScheme == .dark ? 0.35 : 0.25), Color.yellow.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

#Preview {
    ChallengeAFriendEntryWidget()
        .padding()
}
