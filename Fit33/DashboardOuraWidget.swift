//
//  DashboardOuraWidget.swift
//  Fit33
//
//  Isolated Oura Ring Readiness widget for the Dashboard.
//  Matches the DashboardWhoopWidget layout (horizontal, 80pt height, same card bg).
//

import SwiftUI

struct DashboardOuraWrapper: View {
    @StateObject private var ouraService = OuraService.shared

    var body: some View {
        if ouraService.isConnected {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                SectionHeader(title: "Oura Readiness", icon: "circle.circle", iconColor: ouraService.currentReadinessLevel.color)

                DashboardOuraCard(
                    readiness: ouraService.todayReadiness,
                    activity: ouraService.todayActivity,
                    sleep: ouraService.lastSleep,
                    level: ouraService.currentReadinessLevel
                )
            }
        }
    }
}

struct DashboardOuraCard: View {
    let readiness: OuraReadinessRecord?
    let activity: OuraActivityRecord?
    let sleep: OuraSleepRecord?
    let level: OuraService.ReadinessLevel

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color { level.color }

    var body: some View {
        HStack(spacing: 0) {
            metricCell(
                value: readiness?.score.map { "\($0)" } ?? "--",
                label: "Readiness",
                color: level.color
            )
            metricCell(
                value: sleep?.averageHrv.map { String(format: "%.0f", $0) } ?? "--",
                label: "HRV",
                color: .cyan
            )
            metricCell(
                value: activity?.score.map { "\($0)" } ?? "--",
                label: "Activity",
                color: .blue
            )
            metricCell(
                value: sleep?.lowestHeartRate.map { "\($0)" } ?? "--",
                label: "RHR",
                color: .red
            )
            if let efficiency = sleep?.efficiency {
                metricCell(
                    value: "\(efficiency)%",
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

            AdaptiveCardSurface(cornerRadius: 24)

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
        var parts: [String] = ["Oura Readiness widget."]
        if let score = readiness?.score {
            parts.append("Readiness \(score), \(level.label) zone.")
        }
        if let hrv = sleep?.averageHrv {
            parts.append("HRV \(Int(hrv)) milliseconds.")
        }
        if let actScore = activity?.score {
            parts.append("Activity score \(actScore).")
        }
        return parts.joined(separator: " ")
    }
}
