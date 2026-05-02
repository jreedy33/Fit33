import SwiftUI

// MARK: - Phase 4 Cardio Section Strava Surface
//
// Two pieces that the Cardio landing view drops in above the existing
// `quickStartSection`:
//
//   • CardioStravaWeeklyDeltaChip  — single-line "This week vs last week"
//                                     summary (distance + time deltas).
//   • CardioStravaRecentRow        — horizontal scroll of the last 8
//                                     Strava activities; tap → recap sheet.
//
// Both gate on `StravaService.shared.isConnected` and quietly
// short-circuit to `EmptyView()` when no activities exist yet.

// MARK: - Container

struct CardioStravaSection: View {
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    var body: some View {
        if stravaService.isConnected {
            VStack(alignment: .leading, spacing: 12) {
                CardioStravaWeeklyDeltaChip()
                CardioStravaRecentRow()
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Weekly Delta Chip

struct CardioStravaWeeklyDeltaChip: View {
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    private struct WeekTotals {
        var distanceKm: Double = 0
        var timeMinutes: Double = 0
    }

    private var totals: (this: WeekTotals, last: WeekTotals) {
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart

        var thisW = WeekTotals()
        var lastW = WeekTotals()
        for a in stravaService.recentActivities {
            let km = a.distance / 1_000.0
            let mins = Double(a.movingTime) / 60.0
            if a.startDate >= thisWeekStart {
                thisW.distanceKm += km
                thisW.timeMinutes += mins
            } else if a.startDate >= lastWeekStart && a.startDate < thisWeekStart {
                lastW.distanceKm += km
                lastW.timeMinutes += mins
            }
        }
        return (thisW, lastW)
    }

    var body: some View {
        let (this, last) = totals
        // Only render once we have at least *some* signal in either week —
        // an empty card on first connect feels broken.
        if this.distanceKm < 0.1 && last.distanceKm < 0.1 {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("This week vs last")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(headlineCopy(this: this, last: last))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                deltaPill(value: this.distanceKm, prev: last.distanceKm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func headlineCopy(this: WeekTotals, last: WeekTotals) -> String {
        let distanceStr = unitSettings.formatStravaDistance(meters: this.distanceKm * 1_000)
        let minStr = "\(Int(this.timeMinutes)) min"
        return "\(distanceStr) · \(minStr)"
    }

    @ViewBuilder
    private func deltaPill(value: Double, prev: Double) -> some View {
        let delta = value - prev
        let pct: Double = prev > 0.001 ? (delta / prev) * 100 : 0
        let positive = delta >= 0
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let color: Color = positive ? .green : .orange

        HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.caption2.weight(.bold))
            if prev > 0.001 {
                Text(String(format: "%@%.0f%%", positive ? "+" : "", pct))
                    .font(.caption.weight(.semibold))
            } else {
                Text("New")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Recent Row
//
// 2026-05-02 (per-user request): renamed "Recent Strava" → "Recent" and
// dropped the per-row "Synced X min ago" timestamp. The connection
// status + last-sync are owned by the dashboard Strava widget — no need
// to duplicate that signal under the cardio page header.

struct CardioStravaRecentRow: View {
    @ObservedObject private var stravaService = StravaService.shared
    @State private var selectedActivity: StravaActivity?

    private var activities: [StravaActivity] {
        Array(
            stravaService.recentActivities
                .sorted { $0.startDate > $1.startDate }
                .prefix(8)
        )
    }

    var body: some View {
        if activities.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(activities) { activity in
                            Button {
                                selectedActivity = activity
                            } label: {
                                CardioStravaMiniCard(activity: activity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .sheet(item: $selectedActivity) { act in
                StravaActivityRecapSheet(activity: act)
            }
        }
    }
}

// MARK: - Mini Card

private struct CardioStravaMiniCard: View {
    let activity: StravaActivity

    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: activity.activityIcon)
                    .font(.system(size: 12, weight: .semibold))
                Text(activity.type)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.orange)

            Text(activity.name)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(distanceLabel, systemImage: "ruler")
                    .labelStyle(.titleOnly)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Label(durationLabel, systemImage: "clock")
                    .labelStyle(.titleOnly)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(relativeDate)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private var distanceLabel: String {
        UnitSettingsManager.shared.formatStravaDistance(meters: activity.distance)
    }

    private var durationLabel: String {
        let h = activity.movingTime / 3600
        let m = (activity.movingTime % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var relativeDate: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: activity.startDate, relativeTo: Date())
    }
}
