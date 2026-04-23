//
//  HealthInsightsView+Readiness.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 2b
//
//  New sections for the HealthInsightsView: unified 30-day readiness
//  history chart (wearable-agnostic — reads
//  `daily_readiness_history`) plus Oura and Fitbit summary cards that
//  previously didn't exist in the parent view (WHOOP had its own
//  section already).
//

import SwiftUI
import Charts

extension HealthInsightsView {

    // MARK: - Unified Readiness History

    /// 30-day line + band chart of the user's unified readiness score.
    /// Works for WHOOP / Oura / Fitbit / Apple Health users — the band
    /// thresholds are the same (33 / 67).
    var readinessHistorySection: some View {
        let readiness = ReadinessService.shared
        let points = readiness.readinessHistory.prefix(30)
        let today = readiness.todayReadiness

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Readiness")
                        .font(.ds_heading3)
                        .foregroundStyle(Color.adaptiveText)
                    Text("Unified across your wearable")
                        .font(.ds_caption)
                        .foregroundStyle(Color.adaptiveText.opacity(0.6))
                }
                Spacer()
                readinessPill(snapshot: today)
            }

            if points.isEmpty {
                emptyReadinessPlaceholder
            } else {
                readinessChart(points: Array(points))
                readinessLegend
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .fill(Color.cardBackground)
        )
    }

    @ViewBuilder
    private var emptyReadinessPlaceholder: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: "moon.stars")
                .font(.title2)
                .foregroundStyle(Color.adaptiveText.opacity(0.5))
            Text("Readiness will fill in here after your wearable syncs a few days of data.")
                .font(.ds_caption)
                .foregroundStyle(Color.adaptiveText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
    }

    private func readinessPill(snapshot: DailyReadinessSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.band.sfSymbol)
                .font(.ds_labelLarge)
            Text("\(snapshot.score)")
                .font(.ds_heading3)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule().fill(snapshot.band.accentColor.opacity(0.18))
        )
        .overlay(
            Capsule().stroke(snapshot.band.accentColor.opacity(0.6), lineWidth: 1)
        )
        .foregroundStyle(snapshot.band.accentColor)
        .accessibilityLabel(Text("Readiness \(snapshot.score). \(snapshot.band.title)."))
    }

    private func readinessChart(points: [DailyReadinessSnapshot]) -> some View {
        // Sort ascending for the chart. readinessHistory is newest-first.
        let sorted = points.sorted { $0.date < $1.date }
        return Chart {
            // Band reference rectangles (red 0-33, yellow 34-66, green 67-100).
            RectangleMark(
                xStart: .value("start", sorted.first?.date ?? Date()),
                xEnd: .value("end", sorted.last?.date ?? Date()),
                yStart: .value("y0", 0),
                yEnd: .value("y1", 33)
            )
            .foregroundStyle(Color.red.opacity(0.12))
            RectangleMark(
                xStart: .value("start", sorted.first?.date ?? Date()),
                xEnd: .value("end", sorted.last?.date ?? Date()),
                yStart: .value("y0", 34),
                yEnd: .value("y1", 66)
            )
            .foregroundStyle(Color.yellow.opacity(0.12))
            RectangleMark(
                xStart: .value("start", sorted.first?.date ?? Date()),
                xEnd: .value("end", sorted.last?.date ?? Date()),
                yStart: .value("y0", 67),
                yEnd: .value("y1", 100)
            )
            .foregroundStyle(Color.green.opacity(0.12))

            ForEach(sorted) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(Color.adaptiveText.opacity(0.85))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(point.band.accentColor)
                .symbolSize(32)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 33, 67, 100])
        }
        .chartXAxis {
            AxisMarks(
                format: .dateTime.month(.abbreviated).day(),
                values: .automatic(desiredCount: 4)
            )
        }
        .frame(height: 160)
    }

    private var readinessLegend: some View {
        HStack(spacing: Spacing.md) {
            legendSwatch(color: .red, label: "Recovery")
            legendSwatch(color: .yellow, label: "Moderate")
            legendSwatch(color: .green, label: "Primed")
            Spacer()
        }
        .font(.ds_caption)
        .foregroundStyle(Color.adaptiveText.opacity(0.7))
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: - Oura Section

    @ViewBuilder
    var ouraInsightsSection: some View {
        let oura = OuraService.shared
        if oura.isConnected {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Oura Ring")
                    .font(.ds_heading3)
                    .foregroundStyle(Color.adaptiveText)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 2), spacing: Spacing.md) {
                    if let readiness = oura.todayReadiness?.score {
                        miniStatCard(
                            icon: "heart.text.square.fill",
                            tint: .purple,
                            title: "Readiness",
                            value: "\(readiness)",
                            suffix: "/ 100"
                        )
                    }
                    if let activity = oura.todayActivity?.score {
                        miniStatCard(
                            icon: "figure.walk",
                            tint: .orange,
                            title: "Activity",
                            value: "\(activity)",
                            suffix: "/ 100"
                        )
                    }
                    if let sleepMin = oura.lastSleep?.totalSleepDuration, sleepMin > 0 {
                        let hours = Double(sleepMin) / 3600.0
                        miniStatCard(
                            icon: "bed.double.fill",
                            tint: .indigo,
                            title: "Last Sleep",
                            value: String(format: "%.1f", hours),
                            suffix: "h"
                        )
                    }
                    if let rhr = oura.lastSleep?.lowestHeartRate {
                        miniStatCard(
                            icon: "heart.fill",
                            tint: .red,
                            title: "Resting HR",
                            value: "\(rhr)",
                            suffix: "bpm"
                        )
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.cardBackground)
            )
        }
    }

    // MARK: - Fitbit Section

    @ViewBuilder
    var fitbitInsightsSection: some View {
        let fitbit = FitbitService.shared
        if fitbit.isConnected {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Fitbit")
                    .font(.ds_heading3)
                    .foregroundStyle(Color.adaptiveText)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 2), spacing: Spacing.md) {
                    if let summary = fitbit.todaySummary {
                        miniStatCard(
                            icon: "figure.walk",
                            tint: .teal,
                            title: "Steps",
                            value: formatStep(summary.steps),
                            suffix: ""
                        )
                        miniStatCard(
                            icon: "flame.fill",
                            tint: .orange,
                            title: "Calories",
                            value: "\(summary.caloriesOut)",
                            suffix: "cal"
                        )
                        if let rhr = summary.restingHeartRate {
                            miniStatCard(
                                icon: "heart.fill",
                                tint: .red,
                                title: "Resting HR",
                                value: "\(rhr)",
                                suffix: "bpm"
                            )
                        }
                        let active = (summary.fairlyActiveMinutes ?? 0) + (summary.veryActiveMinutes ?? 0)
                        if active > 0 {
                            miniStatCard(
                                icon: "bolt.heart.fill",
                                tint: .pink,
                                title: "Active",
                                value: "\(active)",
                                suffix: "min"
                            )
                        }
                    }
                    if let sleep = fitbit.sleepData.first, let asleep = sleep.minutesAsleep, asleep > 0 {
                        miniStatCard(
                            icon: "bed.double.fill",
                            tint: .indigo,
                            title: "Last Sleep",
                            value: String(format: "%.1f", Double(asleep) / 60.0),
                            suffix: "h"
                        )
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.cardBackground)
            )
        }
    }

    // MARK: - Mini stat card

    private func miniStatCard(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: icon)
                    .font(.ds_labelLarge)
                    .foregroundStyle(tint)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.ds_heading2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.adaptiveText)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.ds_caption)
                        .foregroundStyle(Color.adaptiveText.opacity(0.6))
                }
            }
            Text(title)
                .font(.ds_caption)
                .foregroundStyle(Color.adaptiveText.opacity(0.7))
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title) \(value) \(suffix)"))
    }

    private func formatStep(_ n: Int) -> String {
        if n >= 10_000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
}
