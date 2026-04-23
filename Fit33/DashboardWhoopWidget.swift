//
//  DashboardWhoopWidget.swift
//  Fit33
//
//  Isolated WHOOP Recovery widget for the Dashboard.
//  Matches the DashboardWeightWidget expanded style (horizontal, 80pt height, same card bg).
//

import SwiftUI

struct DashboardWhoopWrapper: View {
    @StateObject private var whoopService = WhoopService.shared

    var body: some View {
        if whoopService.isConnected {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "WHOOP Recovery", icon: "waveform.path.ecg", iconColor: whoopService.currentRecoveryLevel.color)

                DashboardWhoopCard(
                    recovery: whoopService.todayRecovery,
                    strain: whoopService.todayStrain,
                    sleep: whoopService.lastSleep,
                    level: whoopService.currentRecoveryLevel
                )
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
                    value: formattedSleepDuration,
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
                    value: formattedCalories,
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
        VStack(spacing: Spacing.xxxs) {
            Text(value)
                .font(isSecondary ? .ds_labelMedium : .ds_statSmall)
                .fontWeight(isSecondary ? .semibold : .regular)
                .foregroundColor(.primary)
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Formats total asleep time (light + deep + REM) as "7h 23m".
    private var formattedSleepDuration: String {
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
    private var formattedCalories: String {
        guard let kj = strain?.kilojoule, kj > 0 else { return "--" }
        let kcal = kj / 4.184
        return "\(Int(kcal.rounded()))"
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
        if formattedSleepDuration != "--" {
            parts.append("Slept \(formattedSleepDuration).")
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
        if formattedCalories != "--" {
            parts.append("\(formattedCalories) calories burned.")
        }
        return parts.joined(separator: " ")
    }
}
