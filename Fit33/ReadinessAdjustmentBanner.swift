//
//  ReadinessAdjustmentBanner.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 1 (Recovery-aware auto-gen)
//
//  Small reusable SwiftUI banner that surfaces the current
//  `ReadinessBand` + coaching copy above an active or about-to-start
//  workout. Deliberately does NOT own any service subscriptions — the
//  caller passes a snapshot so the banner can be rendered inline
//  wherever readiness is relevant (ActiveWorkoutView, Dashboard
//  Smart Welcome, AutoWorkoutPreview).
//
//  Accessibility + design-token invariants (swiftui-rules.mdc):
//    - All spacing via `Spacing.*`, corners via `CornerRadius.*`.
//    - Fonts via `.ds_*` tokens.
//    - Icon + text are a combined accessibility element so VoiceOver
//      reads "Recovery Day. Mobility, walk, or yoga today." as one.
//

import SwiftUI

/// Renders a single-line banner describing how today's workout was
/// adjusted for the user's readiness. No-op (renders nothing) when:
///   - the snapshot has no wearable signal, OR
///   - the band is `.yellow` AND the feature flag is off
///     (yellow is the sentinel for "no wearable" too; we don't want
///     a banner showing for every unconnected user).
struct ReadinessAdjustmentBanner: View {
    let snapshot: DailyReadinessSnapshot

    /// Optional override — if the caller pre-computed an adjustment
    /// (e.g. after generating a workout) they can pass it so the
    /// banner shows the real `bannerHeadline` rather than a generic
    /// band headline. Safe to pass `nil` and let the banner derive
    /// from `snapshot.band.coachingCopy`.
    var adjustment: ReadinessAdjustment?

    /// Tap handler — opens the readiness drill-down sheet when set.
    var onTap: (() -> Void)?

    var body: some View {
        if shouldRender {
            bannerContent
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Derived state

    private var shouldRender: Bool {
        // No wearable = never show (prevents false "red" banners on
        // placeholder snapshots).
        guard snapshot.hasWearableSignal else { return false }
        // Respect the feature flag — Phase 1 ships dark-first.
        return AppConfig.FeatureFlags.readinessAdaptiveAutoGen
    }

    private var headline: String {
        if let adj = adjustment, !adj.bannerHeadline.isEmpty {
            return adj.bannerHeadline
        }
        return snapshot.band.coachingCopy
    }

    private var iconName: String {
        snapshot.band.sfSymbol
    }

    private var accent: Color {
        snapshot.band.accentColor
    }

    private var sourceCaption: String {
        "from \(snapshot.primarySource.displayName)"
    }

    // MARK: - View

    private var bannerContent: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: iconName)
                .font(.ds_heading3)
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.band.title)
                    .font(.ds_heading3)
                    .foregroundStyle(Color.adaptiveText)
                Text(headline)
                    .font(.ds_caption)
                    .foregroundStyle(Color.adaptiveText.opacity(0.75))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(snapshot.score)")
                    .font(.ds_heading2)
                    .foregroundStyle(accent)
                Text(sourceCaption)
                    .font(.ds_caption)
                    .foregroundStyle(Color.adaptiveText.opacity(0.55))
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(snapshot.band.title). \(headline). Score \(snapshot.score) \(sourceCaption)."
        ))
        .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Green — Primed") {
    ReadinessAdjustmentBanner(
        snapshot: DailyReadinessSnapshot(
            date: Date(),
            score: 82,
            band: .green,
            primarySource: .whoop,
            hrvDeltaPct: 14,
            sleepHours: 8.1,
            sleepDebtMin: 0,
            rhrTrendBpm: -3,
            strainPrev: 9,
            signals: []
        ),
        adjustment: nil
    )
    .padding()
}

#Preview("Red — Recovery day") {
    ReadinessAdjustmentBanner(
        snapshot: DailyReadinessSnapshot(
            date: Date(),
            score: 24,
            band: .red,
            primarySource: .oura,
            hrvDeltaPct: -22,
            sleepHours: 5.2,
            sleepDebtMin: 108,
            rhrTrendBpm: 8,
            strainPrev: 18,
            signals: []
        ),
        adjustment: ReadinessAdjustment(
            replaceWithRecoveryDay: true,
            adjustedCount: 4,
            allowsPrAttempt: false,
            bannerHeadline: "Recovery day — mobility + walk today",
            band: .red,
            source: .oura
        )
    )
    .padding()
}
#endif
