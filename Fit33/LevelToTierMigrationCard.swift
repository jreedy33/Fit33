import SwiftUI

// 2026-04-29 — League Redesign Plan §B1 ship gate ("Your level is now your tier").
//
// One-time, full-screen card shown to users who had ANY XP before the
// tier-as-identity rollout. Pre-existing 50-level grinders need framing on
// what just happened: their level title is gone from the UI, but their
// lifetime XP is preserved as a private souvenir, and their tier is now the
// user-facing identity. No data is lost.
//
// Trigger lives in `LevelToTierMigrationGate` (below) — checks
// `UserDefaults.tier_migration_card_shown_v1` and the user's lifetime XP on
// app launch. Card appears as a `.sheet` from ContentView. Dismissal sets
// the flag so the card never reappears.

struct LevelToTierMigrationCard: View {
    let legacyLevel: Int
    let legacyTitle: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Spacer(minLength: Spacing.xl)

                // Hero — "L → T" handoff
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        legacyLevelChip
                        Image(systemName: "arrow.right")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        tierIdentityChip
                    }

                    Text("Your level is now your tier")
                        .font(.ds_displayMedium)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.lg)

                // Three explainer rows
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    migrationRow(
                        icon: "trophy.fill",
                        iconColor: .orange,
                        title: "Tiers are the new identity",
                        detail: "Bronze → Silver → Gold → Platinum → Diamond → Elite → Verified. Climb 7 tiers."
                    )

                    migrationRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "League Points decide your tier",
                        detail: "Resets every Monday. Workouts, quests, PRs, kudos — they all stack."
                    )

                    migrationRow(
                        icon: "star.fill",
                        iconColor: .purple,
                        title: "Your XP is safe",
                        detail: "We kept every point. Your \(legacyTitle.lowercased()) status lives on as a personal record."
                    )
                }
                .padding(Spacing.md)
                .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
                .padding(.horizontal, Spacing.md)

                Spacer()

                Button(action: onDismiss) {
                    Text("Got it — show me my tier")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            LinearGradient.ds_primaryAccent
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill))
                        )
                }
                .buttonStyle(UniversalScaleButtonStyle())
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
                .accessibilityHint("Closes the migration card.")
            }
        }
    }

    // MARK: - Hero chips

    private var legacyLevelChip: some View {
        VStack(spacing: 4) {
            Text("LV \(legacyLevel)")
                .font(.ds_labelSmall)
                .fontWeight(.bold)
                .foregroundColor(.purple)
            Text(legacyTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minWidth: 90)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.purple.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .opacity(0.7) // Visually demoted — it's the legacy side
    }

    private var tierIdentityChip: some View {
        // Source-of-truth for the user's CURRENT tier. Same fallback chain
        // as the dashboard tier tile (League Redesign Plan §B1).
        let tierName = WeeklyLeagueService.shared.standing?.tierName
            ?? WeeklyLeagueService.shared.notPlacedTierName
            ?? "Bronze"
        let gradient = WeeklyLeagueService.shared.standing?.tierGradient
            ?? [Color.orange, Color(red: 0.8, green: 0.5, blue: 0.2)]

        return VStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.title3)
                .foregroundColor(.white)
            Text(tierName)
                .font(.ds_labelMedium)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(minWidth: 90)
        .background(
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        )
        .shadow(color: (gradient.first ?? .blue).opacity(0.4), radius: 10, x: 0, y: 4)
    }

    // MARK: - Explainer row

    private func migrationRow(
        icon: String,
        iconColor: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ds_labelMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Trigger

/// Small co-located helper that decides whether the migration card should
/// appear on this app launch and persists the dismissal flag once it has.
/// Lives next to the card so the `_v1` UserDefaults key, the trigger
/// threshold (any prior XP), and the dismissal write stay in one file.
enum LevelToTierMigrationGate {
    static let shownKey = "tier_migration_card_shown_v1"

    /// True if the user had non-zero XP before the rollout AND the card
    /// hasn't been shown yet. Brand-new users (no XP) skip it — they have
    /// no legacy mental model to reframe.
    static func shouldShow() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: shownKey) { return false }
        let xp = UserManager.shared.currentUser?.xp ?? 0
        return xp > 0
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}
