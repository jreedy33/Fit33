//
//  DashboardStravaWidget.swift
//  Fit33
//
//  Compact, runner-first dashboard widget for Strava — Nike Run Club style.
//  Distance is the hero, pace sits alongside, and a tight 4-icon strip
//  surfaces Time / HR / Effort / Cal underneath. The whole card wears a
//  Strava-orange gradient so it reads as a brand-tagged tile, not a clone
//  of the WHOOP recovery panel above it.
//
//  Tapping the widget pushes `StravaSettingsView` onto the dashboard's
//  NavigationStack so the user lands on the full Strava overview page —
//  totals, weekly mileage chart, pace trend, recent activities — instead of
//  jumping straight into a single activity recap. Both the active card and
//  the empty/no-recent-activity card route to the same destination so the
//  widget always behaves predictably regardless of state.
//

import SwiftUI

// MARK: - Wrapper (always visible when connected)

struct DashboardStravaWrapper: View {
    @Binding var navigationPath: NavigationPath

    @StateObject private var stravaService = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme

    // Mirror the same key used by `WidgetSettingsSheet` (`showStrava`
    // binding in DashboardView) so dismissing the unsynced Strava widget
    // here also unchecks it in the "Add Widgets" sheet — single source of
    // truth. Same pattern as the WHOOP wrapper.
    @AppStorage("showStravaWidget") private var showStravaWidget = true

    private var latestActivity: StravaActivity? {
        stravaService.mostRecentActivity
    }

    /// Soft disc + glow so the runner reads “floating” beside the wordmark,
    /// aligned with the Daily Steps header glyph treatment.
    private var stravaPoweredByHeaderRunner: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.stravaOrange.opacity(colorScheme == .dark ? 0.28 : 0.18),
                            Color.stravaOrange.opacity(colorScheme == .dark ? 0.12 : 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)

            Image(systemName: "figure.run")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.stravaOrange, Color.stravaOrange.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .shadow(color: Color.stravaOrange.opacity(colorScheme == .dark ? 0.45 : 0.35), radius: 10, x: 0, y: 5)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 5, x: 0, y: 3)
        .accessibilityHidden(true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // The dismiss "X" only appears while Strava is unconnected so
            // a not-yet-synced user can tear off the prompt without
            // digging into the Add Widgets sheet. Once the integration is
            // live we hide it to prevent accidental teardowns; settings
            // stays the canonical entry point for managing connected
            // widgets.
            HStack(spacing: 10) {
                // Same treatment as Daily Steps (`StepTrackerCard` header): title3 + diagonal gradient glyph
                Image(systemName: "figure.run")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.stravaOrange,
                                Color(red: 252 / 255, green: 100 / 255, blue: 30 / 255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)
                    .accessibilityHidden(true)
                Image("PoweredByStrava")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 17)
                    .accessibilityLabel("Powered by Strava")
                Spacer(minLength: 0)

                if !stravaService.isConnected {
                    Button {
                        HapticManager.tap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showStravaWidget = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove Strava widget")
                    .accessibilityHint("Hides the Strava widget from your dashboard. You can add it back from Add Widgets.")
                }
            }

            Button {
                HapticManager.tap()
                navigationPath.append(DashboardRoute.stravaSettings)
            } label: {
                if stravaService.isConnected {
                    if let activity = latestActivity {
                        DashboardStravaCard(activity: activity)
                    } else {
                        DashboardStravaEmptyCard(
                            weeklyMinutes: stravaService.weeklyCardioMinutes,
                            weeklyDistanceKm: stravaService.weeklyDistanceKm,
                            weeklyCalories: stravaService.weeklyCaloriesBurned,
                            lastSyncDate: stravaService.lastSyncDate
                        )
                    }
                } else {
                    DashboardStravaSyncNowCard()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityHint(
                stravaService.isConnected
                    ? "Tap to view your full Strava overview with weekly totals, mileage chart, and recent activities"
                    : "Tap to connect Strava and start syncing your runs, rides, and other activities"
            )
        }
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Sync Now Card (not yet connected)

/// Shown on the dashboard when the user has the Strava widget enabled
/// but hasn't connected their Strava account yet. Tapping routes to
/// `StravaSettingsView` where the orange "Connect with Strava" CTA
/// kicks off the OAuth flow.
struct DashboardStravaSyncNowCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color { Color.stravaOrange }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Strava")
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Connect to track runs, rides, splits, HR & pace.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs)

            HStack(spacing: 4) {
                Text("Sync now")
                    .font(.ds_labelSmall)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, Color(red: 252/255, green: 100/255, blue: 30/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(colorScheme == .dark ? 0.18 : 0.1),
                                accentColor.opacity(colorScheme == .dark ? 0.04 : 0.02),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.4 : 0.25), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync Strava. Connect to track runs, rides, splits, heart rate, and pace.")
    }
}

// MARK: - Active Card (runner-first hero layout)

/// Runner-first activity card. Distance is the hero numeral, pace renders
/// next to it as the second-most-important figure, and a single horizontal
/// strip of four icon-tagged metrics handles the rest. No 5-column grid —
/// the goal is "glance and know".
struct DashboardStravaCard: View {
    let activity: StravaActivity

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    private var accentColor: Color { Color.stravaOrange }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            brandHeader
            heroRow
            statStrip
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.45 : 0.3), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Brand header (icon + title + when)
    // The "Strava Insights" section header now lives OUTSIDE the card
    // (in `DashboardStravaWrapper`), so the in-card branding is just a
    // compact activity-icon badge plus the activity name and timestamp.

    private var brandHeader: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(activity.name)
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(relativeStartedAt)
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Hero row — big distance + secondary pace

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(distanceValue)
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.stravaOrange, Color.stravaOrange.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(distanceUnit)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Text("Distance")
                    .font(.ds_labelSmall)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text(activity.paceFormatted ?? "—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(paceLabel)
                    .font(.ds_labelSmall)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: 4-metric stat strip (Time / HR / Effort / Cal)

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(
                icon: "stopwatch",
                value: activity.durationFormatted,
                label: "Time"
            )
            statDivider
            statCell(
                icon: "heart.fill",
                value: activity.averageHeartrate.map { "\(Int($0))" } ?? "—",
                label: "Avg HR"
            )
            statDivider
            statCell(
                icon: "flame.fill",
                value: activity.sufferScore.map { "\($0)" } ?? "—",
                label: "Effort"
            )
            statDivider
            statCell(
                icon: "bolt.fill",
                value: activity.calories.map { "\($0)" } ?? "—",
                label: "Cal"
            )
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.stravaOrange.opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        let hasValue = value != "—"
        return VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(hasValue ? Color.stravaOrange : .secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(hasValue ? .primary : .primary.opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.stravaOrange.opacity(colorScheme == .dark ? 0.22 : 0.18))
            .frame(width: 1, height: 24)
    }

    // MARK: Card background — Strava-orange gradient

    /// Subtle orange-tinted background so the widget feels brand-tagged
    /// without losing legibility against the dashboard's dark/light surface.
    private var cardBackground: some View {
        ZStack {
            // Base card surface — adaptive (frosted ↔ solid via setting)
            AdaptiveCardSurface(cornerRadius: CornerRadius.xl)

            // Orange tint overlay — top-left more saturated, fades to clear
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.stravaOrange.opacity(colorScheme == .dark ? 0.22 : 0.12),
                            Color.stravaOrange.opacity(colorScheme == .dark ? 0.06 : 0.03),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Soft top highlight for depth
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.12), Color.clear]
                            : [Color.white.opacity(0.7), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: Helpers

    /// Splits the formatted distance string ("5.2 km") into a hero numeral
    /// and unit suffix so we can size each independently in the hero row.
    private var distanceValue: String {
        let formatted = activity.distanceFormatted
        if let space = formatted.firstIndex(of: " ") {
            return String(formatted[..<space])
        }
        return formatted
    }

    private var distanceUnit: String {
        let formatted = activity.distanceFormatted
        if let space = formatted.firstIndex(of: " ") {
            return String(formatted[formatted.index(after: space)...])
        }
        return ""
    }

    private var paceLabel: String {
        switch activity.type {
        case "Ride", "VirtualRide", "GravelRide", "MountainBikeRide": return "Avg Speed"
        case "Swim": return "Pace"
        default: return "Pace"
        }
    }

    private var relativeStartedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: activity.startDate, relativeTo: Date())
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["Strava \(activity.type)."]
        parts.append("\(activity.name).")
        parts.append("\(activity.distanceFormatted) in \(activity.durationFormatted).")
        if let pace = activity.paceFormatted { parts.append("Pace \(pace).") }
        if let hr = activity.averageHeartrate { parts.append("Average heart rate \(Int(hr)).") }
        if let cal = activity.calories { parts.append("\(cal) calories.") }
        if let suffer = activity.sufferScore { parts.append("Effort score \(suffer).") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Empty State

/// Slim brand chip + this-week totals when connected but no activity has
/// landed in the trailing 30 days. Same orange gradient language as the
/// active card so the widget reads consistently either way.
struct DashboardStravaEmptyCard: View {
    let weeklyMinutes: Int
    let weeklyDistanceKm: Double
    let weeklyCalories: Int
    let lastSyncDate: Date?

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    private var accentColor: Color { Color.stravaOrange }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(accentColor))

                VStack(alignment: .leading, spacing: 0) {
                    Text("This Week")
                        .font(.ds_bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if let lastSyncDate {
                        Text(relativeDateString(from: lastSyncDate))
                            .font(.ds_labelSmall)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                emptyMetricCell(
                    value: weeklyDistanceValue,
                    unit: weeklyDistanceUnit,
                    label: "Distance"
                )
                emptyDivider
                emptyMetricCell(
                    value: "\(weeklyMinutes)",
                    unit: "min",
                    label: "Time"
                )
                emptyDivider
                emptyMetricCell(
                    value: "\(weeklyCalories)",
                    unit: "cal",
                    label: "Burned"
                )
            }
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )

            laceUpPrompt
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.4 : 0.25), lineWidth: 1)
        )
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Strava connected, no recent activity. \(weeklyDistanceValue) \(weeklyDistanceUnit), \(weeklyMinutes) minutes, \(weeklyCalories) calories this week.")
    }

    /// Encouraging nudge shown when there's no recent Strava activity.
    /// Reads as a friendly "go run" prompt rather than a passive placeholder.
    private var laceUpPrompt: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lace up — your next run lands here")
                    .font(.ds_bodySmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Strava activities sync automatically once you finish.")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.07))
        )
    }

    private var weeklyDistanceValue: String {
        let meters = weeklyDistanceKm * 1_000
        let units = UnitSettingsManager.shared
        return String(format: "%.1f", units.stravaDistanceValue(meters: meters))
    }

    private var weeklyDistanceUnit: String {
        UnitSettingsManager.shared.stravaDistanceShortLabel
    }

    private func emptyMetricCell(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(value == "0" || value == "0.0" ? .primary.opacity(0.5) : accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDivider: some View {
        Rectangle()
            .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.18))
            .frame(width: 1, height: 24)
    }

    private var cardBackground: some View {
        ZStack {
            AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(colorScheme == .dark ? 0.18 : 0.1),
                            accentColor.opacity(colorScheme == .dark ? 0.04 : 0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Brand colors

extension Color {
    /// Strava's brand orange — used for the dashboard widget accent and any
    /// Strava-tagged surface so users instantly recognise the source.
    static let stravaOrange = Color(red: 0.988, green: 0.302, blue: 0)

    /// Fit33 brand blue — single-stop accent for surfaces that want a
    /// "Fit33-tagged" tint without a full gradient (sleek-card border
    /// on `RecentCardioWorkoutCard`, badge fills, etc). Sampled to
    /// match the midpoint of the cyan→blue gradient on the "33" in
    /// the `fit33-logo` wordmark.
    static let fit33Brand = Color(red: 0.10, green: 0.55, blue: 0.98)

    /// Cyan endpoint of the "33" wordmark gradient. Pairs with
    /// `fit33GradientEnd` to recreate the dashboard wordmark's cyan→
    /// blue ramp on Fit33-authored cardio rows so a Fit33 run reads as
    /// "ours" at a glance vs Strava's orange / WHOOP's red.
    static let fit33GradientStart = Color(red: 0.20, green: 0.85, blue: 1.00)

    /// Blue endpoint of the "33" wordmark gradient — see
    /// `fit33GradientStart`.
    static let fit33GradientEnd = Color(red: 0.05, green: 0.45, blue: 1.00)
}
