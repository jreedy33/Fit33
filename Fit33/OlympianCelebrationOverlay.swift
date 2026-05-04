//
//  OlympianCelebrationOverlay.swift
//  Fit33
//
//  Full-screen celebration when a user completes all 33 goals of the season
//  and earns the stackable "Olympian YYYY" badge.
//
//  Modeled on `TierPromotionOverlay` so the celebration vocabulary stays
//  consistent (sparkle ring + icon + headline + dismiss). Triggered by
//  `OlympianPathService.shared.pendingSeasonCompletion` (set when the
//  server-side `complete_olympian_season_if_done` mints the badge); hosted
//  in `ContentView` so it presents above any tab.
//
//  The "Share" button bridges into `BattleCryComposer` infrastructure —
//  reusing the existing share-card composer so we don't reinvent
//  sharing for one moment a year.
//

import SwiftUI

// `OlympianShareItem` (the bridge type used by the Share button) lives in
// `OlympianPathService.swift` next to `OlympianSeasonBadge` so the year-end
// recap card in `OlympianPathView` can reach it without a cross-file build
// dependency on this overlay file.

struct OlympianCelebrationOverlay: View {
    let badge: OlympianSeasonBadge
    let onDismiss: () -> Void
    let onShare: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var iconScale: CGFloat = 0.3
    @State private var textOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var sparkleRotation: Double = 0
    @State private var confettiAnimating = false

    private var goldAccent: Color { Color(red: 1.00, green: 0.84, blue: 0.00) }

    private var archetype: OlympianArchetype { badge.resolvedArchetype }

    var body: some View {
        ZStack {
            // Dimming + tap-to-dismiss
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Confetti pin layer (cheap — handful of emoji-style sparkles)
            ForEach(0..<14, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.title)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [goldAccent, archetype.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(confettiAnimating ? 0.0 : 0.85)
                    .offset(
                        x: confettiAnimating ? CGFloat([-180, -120, -60, 0, 60, 120, 180].randomElement() ?? 0) : 0,
                        y: confettiAnimating ? CGFloat.random(in: -240 ... -40) : -10
                    )
                    .rotationEffect(.degrees(confettiAnimating ? Double.random(in: -180...180) : 0))
                    .animation(
                        .easeOut(duration: 1.6)
                        .delay(Double(i) * 0.08),
                        value: confettiAnimating
                    )
                    .accessibilityHidden(true)
            }

            VStack(spacing: Spacing.lg) {
                // Animated crown with rings
                ZStack {
                    Circle()
                        .stroke(goldAccent.opacity(0.3), lineWidth: 4)
                        .frame(width: 180, height: 180)
                        .scaleEffect(ringScale)
                        .blur(radius: 6)

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [goldAccent, .white.opacity(0.6), archetype.accent, goldAccent],
                                center: .center
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 150, height: 150)
                        .rotationEffect(.degrees(sparkleRotation))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [goldAccent.opacity(0.4), goldAccent.opacity(0.1)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 70
                            )
                        )
                        .frame(width: 130, height: 130)

                    Image(systemName: "crown.fill")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [goldAccent, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: goldAccent.opacity(0.6), radius: 14, x: 0, y: 0)
                }
                .scaleEffect(iconScale)

                VStack(spacing: Spacing.sm) {
                    Text("OLYMPIAN \(badge.seasonYear)")
                        .font(.ds_displayLarge)
                        .fontWeight(.black)
                        .tracking(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [goldAccent, .white, archetype.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text("All 33 goals — done.")
                        .font(.ds_heading2)
                        .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Image(systemName: archetype.icon)
                        Text("\(archetype.displayName) complete")
                    }
                    .font(.ds_labelLarge)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))

                    Text("Your Olympian \(badge.seasonYear) badge is on your profile forever.")
                        .font(.ds_bodyMedium)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, 4)
                }
                .opacity(textOpacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Olympian \(badge.seasonYear). All 33 goals complete on the \(archetype.displayName).")

                HStack(spacing: Spacing.md) {
                    Button(action: {
                        HapticManager.tap()
                        onShare()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                                .fontWeight(.bold)
                        }
                        .font(.ds_labelLarge)
                        .foregroundColor(.black)
                        .frame(maxWidth: 140)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [goldAccent, Color(red: 0.95, green: 0.75, blue: 0.30)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill))
                        )
                    }
                    .accessibilityHint("Shares your Olympian badge to friends.")

                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.ds_labelLarge)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: 140)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                            )
                    }
                    .accessibilityHint("Dismisses the celebration.")
                }
                .opacity(textOpacity)
                .padding(.top, Spacing.sm)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.55).delay(0.1)) {
                iconScale = 1.0
                ringScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
                textOpacity = 1.0
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                sparkleRotation = 360
            }

            confettiAnimating = true

            // Heavy → heavy → success haptic stack — the most celebratory pattern
            // available, reserved for once-a-year tier-5 completion.
            HapticManager.impact(.heavy)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                HapticManager.impact(.heavy)
                try? await Task.sleep(for: .milliseconds(220))
                HapticManager.notification(.success)
            }

            // Auto-dismiss after 8s — long enough for the user to read +
            // tap Share, short enough to bounce back to dashboard if they
            // backgrounded.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
    }
}
