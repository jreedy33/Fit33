import SwiftUI
import Charts

// MARK: - Phase 3 Strava Stats Charts
//
// Two widgets for `WorkoutStatsSection`:
//   • StravaMileageChartWidget   — weekly mileage stacked by Strava activity type.
//   • StravaPaceTrendChartWidget — 4-week rolling avg pace per Strava run.
//
// Both read directly from `StravaService.shared.recentActivities` (already
// hydrated by sync) — no new RPC, no Core Data round-trip. They render only
// when Strava is connected and at least one activity exists in the window.

// MARK: - Data Points

private struct StravaWeeklyMileagePoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let activityType: String
    /// Distance bucketed into the user's preferred unit (km or miles).
    /// Field stays generic so the same shape works for both unit systems.
    let distance: Double
}

private struct StravaPacePoint: Identifiable {
    let id = UUID()
    let date: Date
    let paceSecondsPerKm: Double
}

// MARK: - Helpers

private func mileageColor(for activityType: String) -> Color {
    switch activityType {
    case "Run", "TrailRun", "VirtualRun": return .orange
    case "Ride", "VirtualRide", "GravelRide", "MountainBikeRide": return .blue
    case "Walk", "Hike": return .green
    case "Swim": return .cyan
    default: return .purple
    }
}

private func formatPace(_ secondsPerKm: Double) -> String {
    guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "—" }
    return UnitSettingsManager.shared.formatStravaPace(secondsPerKm: secondsPerKm)
}

// Local copies of WorkoutStatsView's `private` chart helpers — kept
// in-file so the two Strava widgets stay self-contained per
// codingrules.mdc (no refactor of WorkoutStatsView).
private func stravaChartPlaceholder(height: CGFloat = 180) -> some View {
    RoundedRectangle(cornerRadius: CornerRadius.sm)
        .fill(Color.cardBackground.opacity(0.5))
        .frame(height: height)
}

private func stravaEmptyChartState(message: String, height: CGFloat = 180) -> some View {
    VStack(spacing: Spacing.sm) {
        Image(systemName: "chart.bar.xaxis")
            .font(.system(size: 28))
            .foregroundColor(.adaptiveSecondaryText.opacity(0.6))
        Text(message)
            .font(.ds_caption)
            .foregroundColor(.adaptiveSecondaryText)
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
}

// MARK: - Mileage Chart

struct StravaMileageChartWidget: View {
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [StravaWeeklyMileagePoint] = []
    @State private var isLoading = true

    var body: some View {
        if !stravaService.isConnected {
            EmptyView()
        } else {
            content
                .task(id: timeframe) { recompute() }
                .onChange(of: stravaService.recentActivities.count) { _, _ in
                    recompute()
                }
                .onChange(of: unitSettings.distanceUnit) { _, _ in
                    recompute()
                }
        }
    }

    private var distanceUnitLabel: String {
        unitSettings.stravaDistanceShortLabel
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Strava Mileage (\(distanceUnitLabel))",
                icon: "figure.run.circle.fill",
                iconColor: .orange
            )

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading {
                    stravaChartPlaceholder(height: 200)
                } else if dataPoints.isEmpty {
                    stravaEmptyChartState(message: "Sync Strava activities to see mileage", height: 200)
                } else {
                    Chart(dataPoints) { point in
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value(distanceUnitLabel, point.distance)
                        )
                        .foregroundStyle(by: .value("Type", point.activityType))
                        .cornerRadius(CornerRadius.sm / 2)
                    }
                    .chartForegroundStyleScale(stravaTypeScale)
                    .frame(height: 200)
                    .chartLegend(position: .bottom, spacing: Spacing.xs)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisValueLabel().font(.ds_caption)
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: .orange)
        }
    }

    private var stravaTypeScale: KeyValuePairs<String, Color> {
        [
            "Run": .orange,
            "Ride": .blue,
            "Walk": .green,
            "Swim": .cyan,
            "Other": .purple,
        ]
    }

    private func recompute() {
        isLoading = true
        let cal = Calendar(identifier: .iso8601)
        let cutoff = timeframe.startDate

        let activities = stravaService.recentActivities
            .filter { $0.startDate >= cutoff && $0.distance > 0 }

        var bucket: [Date: [String: Double]] = [:]
        for a in activities {
            let weekStart = cal.dateInterval(of: .weekOfYear, for: a.startDate)?.start ?? a.startDate
            let bucketKey = bucketedType(a.type)
            bucket[weekStart, default: [:]][bucketKey, default: 0] += unitSettings.stravaDistanceValue(meters: a.distance)
        }

        let points: [StravaWeeklyMileagePoint] = bucket.flatMap { weekStart, byType in
            byType.map { type, distance in
                StravaWeeklyMileagePoint(weekStart: weekStart, activityType: type, distance: distance)
            }
        }
        .sorted { $0.weekStart < $1.weekStart }

        dataPoints = points
        isLoading = false
    }

    private func bucketedType(_ raw: String) -> String {
        switch raw {
        case "Run", "TrailRun", "VirtualRun": return "Run"
        case "Ride", "VirtualRide", "GravelRide", "MountainBikeRide": return "Ride"
        case "Walk", "Hike": return "Walk"
        case "Swim": return "Swim"
        default: return "Other"
        }
    }
}

// MARK: - Pace Trend Chart

struct StravaPaceTrendChartWidget: View {
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared
    @State private var timeframe: StatsTimeframe = .threeMonths
    @State private var rawPoints: [StravaPacePoint] = []
    @State private var rollingPoints: [StravaPacePoint] = []
    @State private var isLoading = true

    var body: some View {
        if !stravaService.isConnected {
            EmptyView()
        } else {
            content
                .task(id: timeframe) { recompute() }
                .onChange(of: stravaService.recentActivities.count) { _, _ in
                    recompute()
                }
                .onChange(of: unitSettings.distanceUnit) { _, _ in
                    recompute()
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Run Pace Trend", icon: "speedometer", iconColor: .pink)

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading {
                    stravaChartPlaceholder(height: 200)
                } else if rawPoints.isEmpty {
                    stravaEmptyChartState(message: "Log Strava runs to see pace trends", height: 200)
                } else {
                    Chart {
                        ForEach(rawPoints) { p in
                            PointMark(
                                x: .value("Date", p.date),
                                y: .value("Pace", p.paceSecondsPerKm)
                            )
                            .foregroundStyle(.pink.opacity(0.4))
                            .symbolSize(35)
                        }
                        ForEach(rollingPoints) { p in
                            LineMark(
                                x: .value("Date", p.date),
                                y: .value("Avg Pace", p.paceSecondsPerKm)
                            )
                            .foregroundStyle(.pink)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                    .frame(height: 200)
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(formatPace(v)).font(.ds_caption)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: .pink)
        }
    }

    private func recompute() {
        isLoading = true
        let cutoff = timeframe.startDate
        let runs = stravaService.recentActivities
            .filter { $0.type == "Run" || $0.type == "TrailRun" || $0.type == "VirtualRun" }
            .filter { $0.startDate >= cutoff && $0.distance > 100 && $0.movingTime > 0 }
            .sorted { $0.startDate < $1.startDate }

        let raw: [StravaPacePoint] = runs.map { a in
            // pace s/km = movingTime / (distance_m / 1000)
            let pace = Double(a.movingTime) / max(a.distance / 1_000.0, 0.001)
            return StravaPacePoint(date: a.startDate, paceSecondsPerKm: pace)
        }

        // 4-run rolling average smoothing.
        let window = 4
        var rolling: [StravaPacePoint] = []
        for i in 0..<raw.count {
            let lo = max(0, i - window + 1)
            let slice = raw[lo...i]
            let avg = slice.map(\.paceSecondsPerKm).reduce(0, +) / Double(slice.count)
            rolling.append(StravaPacePoint(date: raw[i].date, paceSecondsPerKm: avg))
        }

        rawPoints = raw
        rollingPoints = rolling
        isLoading = false
    }
}
