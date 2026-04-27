//
//  DashboardWhoopWidget.swift
//  Fit33
//
//  Isolated WHOOP Recovery widget for the Dashboard.
//  Matches the DashboardWeightWidget expanded style (horizontal, 80pt height, same card bg).
//
//  Tapping the widget opens `WhoopMetricsInfoSheet` which shows what each metric
//  means. Definitions are sourced directly from WHOOP's official articles
//  (thelocker on whoop.com) so members get the same guidance inside Fit33 that
//  they would find in the WHOOP app.
//

import SwiftUI

struct DashboardWhoopWrapper: View {
    @Binding var navigationPath: NavigationPath

    @StateObject private var whoopService = WhoopService.shared
    @State private var showingInfoSheet = false

    // Mirror the same key used by `WidgetSettingsSheet` (`showWhoop` binding
    // in DashboardView) so dismissing the unsynced WHOOP widget here also
    // unchecks it in the "Add Widgets" sheet — single source of truth.
    @AppStorage("showWhoopWidget") private var showWhoopWidget = true

    init(navigationPath: Binding<NavigationPath>) {
        self._navigationPath = navigationPath
    }

    /// WHOOP-branded section header — official puck mark + wordmark + "Recovery"
    /// label. The puck inherits the recovery-level color so the badge still
    /// carries the at-a-glance recovery signal; the wordmark stays neutral
    /// (`Color.primary`) per WHOOP brand guidelines (white on dark, black on
    /// light, never recolored).
    ///
    /// When the user hasn't connected WHOOP yet (i.e. the dashboard is
    /// nudging them with the "Sync now" card) we surface a small dismiss
    /// "X" opposite the title. Tapping it toggles `showWhoopWidget` off,
    /// which both removes the widget from the dashboard immediately AND
    /// unchecks it in the "Add Widgets" settings sheet (same AppStorage
    /// key). We deliberately hide the X once the service is connected so
    /// users can't accidentally tear off a working integration — the
    /// settings sheet remains the canonical entry point for that.
    private var whoopBrandedHeader: some View {
        HStack(spacing: 10) {
            Image("WhoopPuck")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundColor(.primary)
            Image("WhoopWordmark")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 16)
                .foregroundColor(.primary)
                .accessibilityHidden(true)
            Text("Recovery")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer(minLength: 0)

            if !whoopService.isConnected {
                Button {
                    HapticManager.tap()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWhoopWidget = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove WHOOP widget")
                .accessibilityHint("Hides the WHOOP widget from your dashboard. You can add it back from Add Widgets.")
            }
        }
        .accessibilityElement(children: .contain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            whoopBrandedHeader

            if whoopService.isConnected {
                if whoopService.todayRecovery == nil {
                    Button {
                        HapticManager.tap()
                        navigationPath.append(DashboardRoute.whoopSettings)
                    } label: {
                        DashboardWhoopWaitingCard()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityHint("Tap to open WHOOP settings while today's data syncs")
                } else {
                    Button {
                        HapticManager.tap()
                        showingInfoSheet = true
                    } label: {
                        DashboardWhoopCard(
                            recovery: whoopService.todayRecovery,
                            strain: whoopService.todayStrain,
                            sleep: whoopService.lastSleep,
                            level: whoopService.currentRecoveryLevel
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityHint("Tap to learn what each WHOOP metric means")
                }
            } else {
                Button {
                    HapticManager.tap()
                    navigationPath.append(DashboardRoute.whoopSettings)
                } label: {
                    DashboardWhoopSyncNowCard()
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityHint("Tap to connect WHOOP and start syncing recovery, strain, and sleep")
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            WhoopMetricsInfoSheet(
                recovery: whoopService.todayRecovery,
                strain: whoopService.todayStrain,
                sleep: whoopService.lastSleep,
                level: whoopService.currentRecoveryLevel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Sync Now Card (not yet connected)

/// Shown on the dashboard when the user has the WHOOP widget enabled
/// but hasn't paired their WHOOP account yet. Tapping routes to
/// `WhoopSettingsView` where the "Connect WHOOP" CTA starts the OAuth.
struct DashboardWhoopSyncNowCard: View {
    @Environment(\.colorScheme) private var colorScheme

    // WHOOP's brand is monochrome black/white — use a neutral grey accent
    // for the card chrome (icon halo, border, shadow) and pair the "Sync
    // now" pill with an explicit black→grey gradient so the prompt reads
    // as on-brand instead of an alert/error red.
    private var accentColor: Color { Color(white: 0.35) }

    private var pillGradientColors: [Color] {
        // Dark mode: black → mid-grey for clean contrast on the dark card.
        // Light mode: very-dark-grey → mid-grey so the pill stays readable
        // without going pitch-black against a white card.
        colorScheme == .dark
            ? [Color.black, Color(white: 0.35)]
            : [Color(white: 0.15), Color(white: 0.4)]
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image("WhoopPuck")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(.primary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sync WHOOP")
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Connect to track recovery, strain, HRV & sleep.")
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
                            colors: pillGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Match the rest of the dashboard cards (Oura readiness, workout
        // stats, etc.) by using the shared `sleekCard` treatment instead
        // of a one-off background/overlay/shadow stack. The accent color
        // is the same neutral grey that drives the icon halo + "Sync now"
        // pill so the whole card reads as a single cohesive monochrome
        // surface.
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync WHOOP. Connect to track recovery, strain, HRV, and sleep.")
    }
}

// MARK: - Active Card (recovery-ring hero, monochrome chrome)

/// Recovery-ring hero card. The ring IS WHOOP's brand mark — a percentage
/// trim around the level color (red/yellow/green) so the at-a-glance
/// recovery signal is the primary visual instead of a 10-cell rainbow grid.
///
/// Card chrome is intentionally neutral (white-ish in light mode, dark
/// gray in dark mode) — the recovery color is confined to the ring +
/// percent digit so the at-a-glance signal pops without flooding the
/// whole tile in red on a low-recovery day. Mirrors the neutral chrome
/// already used by `DashboardWhoopSyncNowCard` / `DashboardWhoopWaitingCard`.
///
/// The 10-metric breakdown still lives in `WhoopMetricsInfoSheet` (this
/// card opens it on tap) — the widget surfaces only the 6 most actionable
/// today-stats: Recovery score, Strain (mini-bar), Sleep performance,
/// HRV, RHR, and total Asleep time.
struct DashboardWhoopCard: View {
    let recovery: WhoopRecoveryScore?
    let strain: WhoopCycleScore?
    let sleep: WhoopSleepScore?
    let level: WhoopService.RecoveryLevel

    @Environment(\.colorScheme) private var colorScheme

    /// Recovery color (red/yellow/green) — used ONLY inside the recovery
    /// ring (stroke + center percent digit). Do not apply to card chrome,
    /// stat-strip backgrounds, or dividers; those must stay neutral so a
    /// low-recovery day doesn't paint the entire dashboard tile red.
    private var ringColor: Color { level.color }

    /// Neutral chrome accent for the `.sleekCard()` outer glow + shadow.
    /// Matches the `Color(white: 0.4)` used by the connected-but-pending
    /// `DashboardWhoopWaitingCard` so all three WHOOP card states share the
    /// same monochrome chrome and only the inner content differs.
    private var chromeAccent: Color { Color(white: 0.4) }

    /// WHOOP-blue — used only for the strain mini-bar so Strain has its
    /// own brand cue without polluting the rest of the card with extra hues.
    private var strainColor: Color {
        Color(red: 0.0, green: 0.62, blue: 0.96)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            heroRow
            strainSection
            statStrip
            secondaryStatStrip
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: chromeAccent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Hero — ring + headline copy

    private var heroRow: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            recoveryRing

            VStack(alignment: .leading, spacing: 2) {
                Text(recoveryHeadline)
                    .font(.ds_heading3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(recoverySubhead)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var recoveryRing: some View {
        let progress: CGFloat = {
            guard let score = recovery?.recoveryScore else { return 0 }
            return CGFloat(min(max(score, 0), 100)) / 100
        }()

        return ZStack {
            Circle()
                .stroke(ringColor.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [ringColor, ringColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(recovery?.recoveryScore.map { "\($0)" } ?? "—")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(ringColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .offset(y: -2)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }

    // MARK: Strain mini-bar (WHOOP's second brand signal)

    private var strainSection: some View {
        let value = strain?.strain ?? 0
        let progress: CGFloat = CGFloat(min(max(value, 0), 21)) / 21
        let hasValue = strain?.strain != nil

        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day Strain")
                    .font(.ds_labelSmall)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hasValue ? String(format: "%.1f", value) : "—")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(hasValue ? .primary : .primary.opacity(0.45))
                    Text("/ 21")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [strainColor.opacity(0.85), strainColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: 4-metric stat strip

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(
                value: sleep?.sleepPerformancePercentage.map { "\(Int($0))%" } ?? "—",
                label: "Sleep"
            )
            statDivider
            statCell(
                value: WhoopWidgetFormat.sleepDuration(from: sleep),
                label: "Asleep"
            )
            statDivider
            statCell(
                value: recovery?.hrvRmssdMilli.map { "\(Int($0))" } ?? "—",
                label: "HRV",
                unit: "ms"
            )
            statDivider
            statCell(
                value: recovery?.restingHeartRate.map { "\($0)" } ?? "—",
                label: "RHR",
                unit: "bpm"
            )
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            // Neutral monochrome backdrop — never recovery-color-tinted.
            // A low-recovery day would otherwise paint a red wash across
            // the primary stat strip, which is what the user explicitly
            // asked to remove (only the ring stays colored).
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
    }

    private func statCell(value: String, label: String, unit: String? = nil) -> some View {
        let hasValue = value != "—"
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(hasValue ? .primary : .primary.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit, hasValue {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
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
            // Neutral monochrome divider — never recovery-color-tinted.
            // Matches the `secondaryDivider` below for consistency, and
            // keeps the only red/yellow/green surface the recovery ring.
            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.18))
            .frame(width: 1, height: 24)
    }

    // MARK: Secondary stat strip — physiological detail

    /// Less-prominent second row for the deeper physiological signals
    /// (sleep efficiency, blood oxygen, respiratory rate, calories burned).
    /// Intentionally rendered without the level-color background tint and
    /// at a smaller scale so the recovery ring + primary strip stay the
    /// hero of the card. The detail-level info sheet still hosts the full
    /// definitions when the user taps the widget.
    private var secondaryStatStrip: some View {
        HStack(spacing: 0) {
            secondaryStatCell(
                value: sleep?.sleepEfficiencyPercentage.map { "\(Int($0))%" } ?? "—",
                label: "Efficiency"
            )
            secondaryDivider
            secondaryStatCell(
                value: recovery?.spo2Percentage.map { String(format: "%.0f%%", $0) } ?? "—",
                label: "SpO₂"
            )
            secondaryDivider
            secondaryStatCell(
                value: sleep?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—",
                label: "Resp",
                unit: "/min"
            )
            secondaryDivider
            secondaryStatCell(
                value: WhoopWidgetFormat.calories(from: strain),
                label: "Cal"
            )
        }
        .padding(.top, Spacing.xxs)
    }

    private func secondaryStatCell(value: String, label: String, unit: String? = nil) -> some View {
        let hasValue = value != "—" && value != "--"
        return VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(hasValue ? value : "—")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(hasValue ? .primary.opacity(0.85) : .primary.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, hasValue {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var secondaryDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 18)
    }

    // MARK: Recovery copy (WHOOP's voice)

    private var recoveryHeadline: String {
        switch level {
        case .green: return "Primed to perform"
        case .yellow: return "Maintain today"
        case .red: return "Take it easy"
        case .unknown: return "Recovery pending"
        }
    }

    private var recoverySubhead: String {
        switch level {
        case .green: return "Your body is ready for high strain."
        case .yellow: return "Match your effort to today's recovery."
        case .red: return "Your body needs rest — go light today."
        case .unknown: return "Today's recovery will land here once your strap syncs."
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["WHOOP Recovery widget."]
        if let score = recovery?.recoveryScore {
            parts.append("Recovery \(score) percent, \(level.label) zone. \(recoveryHeadline).")
        }
        if let s = strain?.strain {
            parts.append("Day strain \(String(format: "%.1f", s)) out of 21.")
        }
        if let perf = sleep?.sleepPerformancePercentage {
            parts.append("Sleep performance \(Int(perf)) percent.")
        }
        let asleep = WhoopWidgetFormat.sleepDuration(from: sleep)
        if asleep != "--" {
            parts.append("Slept \(asleep).")
        }
        if let hrv = recovery?.hrvRmssdMilli {
            parts.append("HRV \(Int(hrv)) milliseconds.")
        }
        if let rhr = recovery?.restingHeartRate {
            parts.append("Resting heart rate \(rhr).")
        }
        if let eff = sleep?.sleepEfficiencyPercentage {
            parts.append("Sleep efficiency \(Int(eff)) percent.")
        }
        if let spo2 = recovery?.spo2Percentage {
            parts.append("SpO2 \(Int(spo2)) percent.")
        }
        if let resp = sleep?.respiratoryRate {
            parts.append("Respiratory rate \(String(format: "%.1f", resp)) breaths per minute.")
        }
        let cal = WhoopWidgetFormat.calories(from: strain)
        if cal != "--" {
            parts.append("\(cal) calories burned.")
        }
        parts.append("Tap for definitions of every metric.")
        return parts.joined(separator: " ")
    }
}

// MARK: - Waiting Card (connected, but today's recovery not yet synced)

/// Shown when the user has paired their WHOOP but today's recovery score
/// hasn't landed yet (early morning before the strap uploads, or a brief
/// sync gap). Mirrors the Strava "Lace up — your next run lands here"
/// empty state so connected widgets always feel intentional, never broken.
struct DashboardWhoopWaitingCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color { Color(white: 0.4) }

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(colorScheme == .dark ? 0.25 : 0.18), lineWidth: 5)
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery pending")
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text("Today's score lands here once your strap syncs.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("WHOOP recovery pending. Today's score will land here once your strap syncs.")
    }
}

// MARK: - Shared formatting helpers

/// File-private formatters shared between the card and the info sheet so both
/// screens display identical values for "Asleep" and "Cal".
enum WhoopWidgetFormat {
    /// Formats total asleep time (light + deep + REM) as "7h 23m".
    static func sleepDuration(from sleep: WhoopSleepScore?) -> String {
        guard let stages = sleep?.stageSummary else { return "--" }
        let asleepMs = (stages.totalLightSleepTimeMilli ?? 0)
            + (stages.totalSlowWaveSleepTimeMilli ?? 0)
            + (stages.totalRemSleepTimeMilli ?? 0)
        guard asleepMs > 0 else { return "--" }
        let totalMinutes = asleepMs / 60_000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    /// Converts WHOOP kilojoules to kilocalories for the day's strain cycle.
    static func calories(from strain: WhoopCycleScore?) -> String {
        guard let kj = strain?.kilojoule, kj > 0 else { return "--" }
        let kcal = kj / 4.184
        return "\(Int(kcal.rounded()))"
    }
}

// MARK: - WHOOP Metrics Info Sheet

/// Definition-card metadata for a single metric inside the info sheet.
/// Definitions are paraphrased from WHOOP's official `thelocker` articles.
private struct WhoopMetricInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let value: String
    let unit: String?
    let headline: String
    let definition: String
    let extra: String?

    init(
        id: String,
        title: String,
        icon: String,
        color: Color,
        value: String,
        unit: String? = nil,
        headline: String,
        definition: String,
        extra: String? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.color = color
        self.value = value
        self.unit = unit
        self.headline = headline
        self.definition = definition
        self.extra = extra
    }
}

struct WhoopMetricsInfoSheet: View {
    let recovery: WhoopRecoveryScore?
    let strain: WhoopCycleScore?
    let sleep: WhoopSleepScore?
    let level: WhoopService.RecoveryLevel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header

                        ForEach(metrics) { metric in
                            WhoopMetricInfoCard(info: metric)
                        }

                        sourceFooter
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("WHOOP Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("What each metric means")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text("Definitions come directly from WHOOP. Tap any metric on the dashboard to revisit this guide.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Source")
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text("Definitions adapted from WHOOP's official articles on thelocker (whoop.com) and WHOOP's developer documentation.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.xs)
    }

    // MARK: - Metric content (WHOOP-sourced definitions)

    private var metrics: [WhoopMetricInfo] {
        [
            recoveryInfo,
            hrvInfo,
            strainInfo,
            rhrInfo,
            sleepPerformanceInfo,
            asleepInfo,
            efficiencyInfo,
            spo2Info,
            respInfo,
            caloriesInfo
        ]
    }

    private var recoveryInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "recovery",
            title: "Recovery",
            icon: "heart.circle.fill",
            color: level.color,
            value: recovery?.recoveryScore.map { "\($0)" } ?? "--",
            unit: "%",
            headline: "How prepared your body is to perform",
            definition: "WHOOP Recovery is a daily score from 0–100% that tells you how ready your body is to take on Strain. The higher the score, the more your body is primed to perform. It's calculated each morning from HRV, resting heart rate, sleep performance, respiratory rate, and other signals.",
            extra: "Green (67–99%): primed to perform. Yellow (34–66%): maintaining. Red (1–33%): your body needs rest."
        )
    }

    private var hrvInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "hrv",
            title: "HRV",
            icon: "waveform.path.ecg",
            color: .cyan,
            value: recovery?.hrvRmssdMilli.map { String(format: "%.0f", $0) } ?? "--",
            unit: "ms",
            headline: "Heart Rate Variability (RMSSD)",
            definition: "HRV is the variance in time between your heartbeats. WHOOP calculates it using RMSSD (Root Mean Square of Successive Differences) during your deepest sleep each night for the most consistent reading.",
            extra: "Higher HRV suggests your autonomic nervous system is balanced and you're well-recovered. Lower HRV can signal stress, fatigue, dehydration, illness, or under-recovery."
        )
    }

    private var strainInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "strain",
            title: "Day Strain",
            icon: "bolt.heart.fill",
            color: .blue,
            value: strain?.strain.map { String(format: "%.1f", $0) } ?? "--",
            unit: nil,
            headline: "Total cardiovascular load today",
            definition: "Day Strain measures the total stress your body takes on across the entire day — workouts, daily activity, and life stress combined. It's scored on a non-linear 0–21 scale, so moving from 16 to 17 takes much more effort than moving from 4 to 5.",
            extra: "Light (0–9): active recovery. Moderate (10–13): maintains fitness. High (14–17): stimulates fitness gains. All Out (18–21): significant overreach."
        )
    }

    private var rhrInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "rhr",
            title: "Resting Heart Rate",
            icon: "heart.fill",
            color: .red,
            value: recovery?.restingHeartRate.map { "\($0)" } ?? "--",
            unit: "bpm",
            headline: "Beats per minute at full rest",
            definition: "Resting Heart Rate is the number of times your heart beats per minute when you're completely at rest. A lower RHR generally signals a stronger, more efficient heart and better cardiovascular fitness. WHOOP measures it during sleep for the most consistent reading.",
            extra: "Most adults fall between 60–100 bpm. Endurance-trained athletes often land in the 40–60 bpm range."
        )
    }

    private var sleepPerformanceInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "sleep_performance",
            title: "Sleep Performance",
            icon: "moon.stars.fill",
            color: .indigo,
            value: sleep?.sleepPerformancePercentage.map { "\(Int($0))" } ?? "--",
            unit: "%",
            headline: "Sleep you got vs. sleep you needed",
            definition: "Sleep Performance is the percentage of the sleep you actually got compared to the amount WHOOP calculates that you needed. 100% means you fully met your need; values above 100% mean you paid down sleep debt.",
            extra: "Built from four factors: Sleep Sufficiency (hours vs. needed), Sleep Consistency, Sleep Efficiency, and Sleep Stress."
        )
    }

    private var asleepInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "asleep",
            title: "Asleep",
            icon: "bed.double.fill",
            color: .indigo,
            value: WhoopWidgetFormat.sleepDuration(from: sleep),
            unit: nil,
            headline: "Total time asleep last night",
            definition: "The total time you actually spent asleep — light sleep, slow-wave (deep) sleep, and REM sleep combined. Time you were in bed but awake is not counted.",
            extra: nil
        )
    }

    private var efficiencyInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "efficiency",
            title: "Sleep Efficiency",
            icon: "chart.bar.fill",
            color: .purple,
            value: sleep?.sleepEfficiencyPercentage.map { "\(Int($0))" } ?? "--",
            unit: "%",
            headline: "Share of time in bed you were asleep",
            definition: "Sleep Efficiency is the percentage of your time in bed that you actually spent asleep. It's a core measure of sleep quality — trouble falling asleep, frequent wakings, or restless sleep all lower this number.",
            extra: "WHOOP members average about 7.5 hours of sleep for every 8 hours in bed, so efficiency is commonly below 100%."
        )
    }

    private var spo2Info: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "spo2",
            title: "SpO₂",
            icon: "lungs.fill",
            color: .teal,
            value: recovery?.spo2Percentage.map { String(format: "%.0f", $0) } ?? "--",
            unit: "%",
            headline: "Blood oxygen saturation",
            definition: "SpO₂ (peripheral oxygen saturation) is the percentage of oxygen circulating through your bloodstream. WHOOP measures it nightly during sleep using pulse oximetry — LEDs shine light through your skin and sensors measure how the blood absorbs it.",
            extra: "For healthy adults, SpO₂ typically sits between 95% and 100%."
        )
    }

    private var respInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "resp",
            title: "Respiratory Rate",
            icon: "wind",
            color: .mint,
            value: sleep?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "--",
            unit: "breaths/min",
            headline: "Breaths per minute during sleep",
            definition: "Respiratory Rate is how many breaths you take per minute. WHOOP measures it during sleep using Respiratory Sinus Arrhythmia — the natural rhythm where heart rate slightly rises on inhalation and falls on exhalation.",
            extra: "A typical adult resting respiratory rate is between 12 and 20 breaths per minute. Sustained changes from your personal baseline can be an early signal of illness."
        )
    }

    private var caloriesInfo: WhoopMetricInfo {
        WhoopMetricInfo(
            id: "calories",
            title: "Calories",
            icon: "flame.fill",
            color: .orange,
            value: WhoopWidgetFormat.calories(from: strain),
            unit: "kcal",
            headline: "Total energy burned today",
            definition: "An estimate of the total calories your body has burned today. WHOOP combines your Basal Metabolic Rate (the calories you'd burn just staying alive, based on age, height, weight, and gender) with Active Burn measured continuously from your heart rate.",
            extra: nil
        )
    }
}

private struct WhoopMetricInfoCard: View {
    let info: WhoopMetricInfo

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(info.color.opacity(colorScheme == .dark ? 0.2 : 0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: info.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(info.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.ds_bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(info.headline)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.xs)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(info.value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(info.color)
                    if let unit = info.unit, info.value != "--" {
                        Text(unit)
                            .font(.ds_labelSmall)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(info.definition)
                .font(.ds_bodySmall)
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if let extra = info.extra {
                Text(extra)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(info.color.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.title). \(info.value)\(info.unit.map { " \($0)" } ?? ""). \(info.headline). \(info.definition)")
    }
}
