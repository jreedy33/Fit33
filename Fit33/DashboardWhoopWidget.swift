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
            if let perf = sleep?.sleepPerformancePercentage {
                metricCell(
                    value: "\(Int(perf))%",
                    label: "Sleep",
                    color: .indigo
                )
            }
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private func metricCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: Spacing.xxxs) {
            Text(value)
                .font(.ds_statSmall)
                .foregroundColor(.primary)
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
        return parts.joined(separator: " ")
    }
}
