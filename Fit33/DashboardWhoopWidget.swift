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
    @StateObject private var whoopService = WhoopService.shared
    @State private var showingInfoSheet = false

    var body: some View {
        if whoopService.isConnected {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "WHOOP Recovery", icon: "waveform.path.ecg", iconColor: whoopService.currentRecoveryLevel.color)

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
}

struct DashboardWhoopCard: View {
    let recovery: WhoopRecoveryScore?
    let strain: WhoopCycleScore?
    let sleep: WhoopSleepScore?
    let level: WhoopService.RecoveryLevel

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color { level.color }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Primary row — recovery / strain signals
            HStack(spacing: 0) {
                metricCell(
                    value: recovery?.recoveryScore.map { "\($0)%" } ?? "--",
                    label: "Recovery",
                    color: level.color
                )
                metricCell(
                    value: recovery?.hrvRmssdMilli.map { String(format: "%.0f", $0) } ?? "--",
                    label: "HRV",
                    color: .cyan
                )
                metricCell(
                    value: strain?.strain.map { String(format: "%.1f", $0) } ?? "--",
                    label: "Strain",
                    color: .blue
                )
                metricCell(
                    value: recovery?.restingHeartRate.map { "\($0)" } ?? "--",
                    label: "RHR",
                    color: .red
                )
                metricCell(
                    value: sleep?.sleepPerformancePercentage.map { "\(Int($0))%" } ?? "--",
                    label: "Sleep",
                    color: .indigo
                )
            }

            Divider()
                .opacity(0.35)
                .padding(.horizontal, Spacing.md)

            // Secondary row — sleep + physiological detail
            HStack(spacing: 0) {
                metricCell(
                    value: WhoopWidgetFormat.sleepDuration(from: sleep),
                    label: "Asleep",
                    color: .indigo,
                    isSecondary: true
                )
                metricCell(
                    value: sleep?.sleepEfficiencyPercentage.map { "\(Int($0))%" } ?? "--",
                    label: "Efficiency",
                    color: .purple,
                    isSecondary: true
                )
                metricCell(
                    value: recovery?.spo2Percentage.map { String(format: "%.0f%%", $0) } ?? "--",
                    label: "SpO₂",
                    color: .teal,
                    isSecondary: true
                )
                metricCell(
                    value: sleep?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "--",
                    label: "Resp",
                    color: .mint,
                    isSecondary: true
                )
                metricCell(
                    value: WhoopWidgetFormat.calories(from: strain),
                    label: "Cal",
                    color: .orange,
                    isSecondary: true
                )
            }
        }
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private func metricCell(value: String, label: String, color: Color, isSecondary: Bool = false) -> some View {
        // Value is tinted to match the expanded info sheet cards so the widget
        // speaks WHOOP's visual language (Recovery red/yellow/green, Strain
        // blue, etc.). Fallback to `.primary` when there is no reading so the
        // greyed-out "--" state reads cleanly.
        let hasValue = value != "--"
        return VStack(spacing: Spacing.xxxs) {
            Text(value)
                .font(isSecondary ? .ds_labelMedium : .ds_statSmall)
                .fontWeight(isSecondary ? .semibold : .regular)
                .foregroundColor(hasValue ? color : .primary.opacity(0.5))
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.08 : 0.04))
                .offset(y: 6)
                .blur(radius: 3)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBackground)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
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

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(colorScheme == .dark ? 0.25 : 0.18), accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = ["WHOOP Recovery widget."]
        if let score = recovery?.recoveryScore {
            parts.append("Recovery \(score) percent, \(level.label) zone.")
        }
        if let hrv = recovery?.hrvRmssdMilli {
            parts.append("HRV \(Int(hrv)) milliseconds.")
        }
        if let s = strain?.strain {
            parts.append("Strain \(String(format: "%.1f", s)).")
        }
        if let rhr = recovery?.restingHeartRate {
            parts.append("Resting heart rate \(rhr).")
        }
        if let perf = sleep?.sleepPerformancePercentage {
            parts.append("Sleep performance \(Int(perf)) percent.")
        }
        let asleep = WhoopWidgetFormat.sleepDuration(from: sleep)
        if asleep != "--" {
            parts.append("Slept \(asleep).")
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
        return parts.joined(separator: " ")
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
