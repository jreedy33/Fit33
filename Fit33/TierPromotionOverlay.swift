import SwiftUI

// 2026-04-29 — League Redesign Plan §B2.
//
// Replaces `LevelUpCelebrationOverlay` (which fired on every 100-XP boundary).
// This overlay is the single celebration surface for tier promotions and only
// fires at most once per Monday rollup. Driven by
// `WeeklyLeagueService.shared.pendingTierPromotion`. ContentView watches and
// shows the overlay; the close button calls
// `WeeklyLeagueService.shared.clearPendingTierPromotion()`.
//
// Sprint 1 ships the `.standard` variant. Sprint 2 layers in `.standOut`,
// `.crown`, `.bounceback`, and the (informational, not celebratory)
// `.shieldBurned` variants — all routed through the same `event.variant`
// switch below so the celebration surface stays singular.
//
// Layout intentionally mirrors the previous level-up overlay (sparkle ring +
// icon + headline + tier name + Continue CTA) so the muscle memory survives —
// what changes is the SOURCE of celebration (server-side rollup, not local XP
// boundary) and the FREQUENCY (≤ 1×/week, not 1× per 3-4 workouts).

struct TierPromotionOverlay: View {
    let event: TierPromotionEvent
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var iconScale: CGFloat = 0.3
    @State private var textOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var sparkleRotation: Double = 0

    // MARK: - Variant Copy

    private var headline: String {
        switch event.variant {
        case .standard:     return "TIER UP!"
        case .standOut:     return "STAND-OUT"
        case .crown:        return "CROWN OF THE WEEK"
        case .bounceback:   return "BOUNCEBACK"
        case .shieldBurned: return "SHIELD BURNED"
        }
    }

    private var subheadline: String {
        switch event.variant {
        case .standard:
            return "Welcome to \(event.newTierName)"
        case .standOut:
            if let skipped = event.skippedTierName {
                return "You skipped \(skipped) — Welcome to \(event.newTierName)"
            }
            return "Welcome to \(event.newTierName)"
        case .crown:
            return "You held the top spot in \(event.newTierName)"
        case .bounceback:
            return "Right back into \(event.newTierName)"
        case .shieldBurned:
            return "Shield burned — next time the drop is real"
        }
    }

    /// Whether this variant is a celebration (full-screen overlay) or a
    /// quiet informational surface. `.shieldBurned` is informational per the
    /// plan — same plumbing, smaller treatment in Sprint 2.
    private var isCelebratory: Bool {
        event.variant != .shieldBurned
    }

    /// Variant-specific accent color. Crown is gold regardless of tier;
    /// Stand-Out keeps a high-energy yellow; Bounceback nods to "back in
    /// the game" with green; ShieldBurned warns with orange-red. Otherwise
    /// the destination tier color drives the celebration palette.
    /// Sprint 3 polish (League Redesign Plan §B2 follow-up).
    private var tierColor: Color {
        switch event.variant {
        case .crown:
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case .standOut:
            return Color(red: 1.0, green: 0.85, blue: 0.2) // Bright yellow
        case .bounceback:
            return Color(red: 0.2, green: 0.78, blue: 0.55) // Mint green
        case .shieldBurned:
            return Color(red: 1.0, green: 0.45, blue: 0.25) // Burned-orange
        case .standard:
            switch event.newTierRank {
            case 1: return .orange
            case 2: return .gray
            case 3: return .yellow
            case 4: return Color(red: 0.66, green: 0.66, blue: 0.78)
            case 5: return .cyan
            case 6: return Color(red: 1.0, green: 0.42, blue: 0.21)
            case 7: return Color(red: 0.11, green: 0.63, blue: 0.95)
            default: return .blue
            }
        }
    }

    private var iconName: String {
        switch event.variant {
        case .standard:
            return event.newTierRank == 7 ? "checkmark.seal.fill" : "trophy.fill"
        case .standOut:
            return "sparkles"
        case .bounceback:
            return "arrow.uturn.up.circle.fill"
        case .crown:
            return "crown.fill"
        case .shieldBurned:
            return "shield.lefthalf.filled.slash"
        }
    }

    /// Variant-specific haptic pattern. `.shieldBurned` is informational
    /// (warning haptic, no celebration ring); the celebratory variants get
    /// progressively stronger feedback up to `.crown`.
    private func playVariantHaptic() {
        switch event.variant {
        case .standard:
            HapticManager.notification(.success)
        case .standOut:
            HapticManager.impact(.heavy)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                HapticManager.notification(.success)
            }
        case .bounceback:
            HapticManager.impact(.medium)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                HapticManager.notification(.success)
            }
        case .crown:
            HapticManager.impact(.heavy)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                HapticManager.impact(.heavy)
                try? await Task.sleep(for: .milliseconds(120))
                HapticManager.notification(.success)
            }
        case .shieldBurned:
            HapticManager.notification(.warning)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: Spacing.lg) {
                // Animated tier icon with rings
                ZStack {
                    Circle()
                        .stroke(tierColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale)
                        .blur(radius: 4)

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [tierColor, .white.opacity(0.6), tierColor],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(sparkleRotation))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [tierColor.opacity(0.4), tierColor.opacity(0.1)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: iconName)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tierColor, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: tierColor.opacity(0.6), radius: 12, x: 0, y: 0)
                }
                .scaleEffect(iconScale)

                VStack(spacing: Spacing.sm) {
                    Text(headline)
                        .font(.ds_displayMedium)
                        .fontWeight(.black)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tierColor, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(event.newTierName)
                        .font(.ds_stat)
                        .foregroundColor(.white)

                    Text(subheadline)
                        .font(.ds_heading3)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
                .opacity(textOpacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(headline). \(event.newTierName). \(subheadline)")

                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [tierColor, tierColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill))
                        )
                }
                .opacity(textOpacity)
                .padding(.top, Spacing.sm)
                .accessibilityHint("Dismisses the tier promotion celebration.")
            }
        }
        .onAppear {
            // 2026-04-29 — Sprint 3 polish (League Redesign Plan §B2 follow-up).
            // Variant-specific entry animations. Crown gets a slight extra
            // bounce (over-shoot on icon scale); Bounceback springs harder
            // to convey "rebound"; Stand-Out has a faster entrance (the
            // user IS standing out); ShieldBurned slides in flatter as it's
            // informational, not celebratory.
            let iconAnim: Animation
            switch event.variant {
            case .crown:
                iconAnim = .spring(response: 0.55, dampingFraction: 0.45).delay(0.1)
            case .bounceback:
                iconAnim = .spring(response: 0.45, dampingFraction: 0.5).delay(0.05)
            case .standOut:
                iconAnim = .spring(response: 0.5, dampingFraction: 0.55).delay(0.05)
            case .shieldBurned:
                iconAnim = .easeOut(duration: 0.45).delay(0.1)
            case .standard:
                iconAnim = .spring(response: 0.6, dampingFraction: 0.6).delay(0.1)
            }
            withAnimation(iconAnim) {
                iconScale = 1.0
                ringScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                textOpacity = 1.0
            }
            // Continuous sparkle ring rotation. Disabled on the informational
            // ShieldBurned variant — it's a quieter, non-celebratory surface.
            if isCelebratory {
                let ringDuration: Double = (event.variant == .crown) ? 5 : 8
                withAnimation(.linear(duration: ringDuration).repeatForever(autoreverses: false)) {
                    sparkleRotation = 360
                }
            }

            // Variant-specific haptic pattern. ShieldBurned plays warning
            // haptic only; celebrations stack medium → heavy + success.
            playVariantHaptic()

            // Auto-dismiss after 5s (4s for the informational ShieldBurned
            // variant) so a backgrounded user comes back to a clean
            // dashboard. Structured-concurrency version — never
            // DispatchQueue.main.asyncAfter (codingrules).
            let dismissDelay: TimeInterval = isCelebratory ? 5.0 : 4.0
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(dismissDelay))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
    }
}
