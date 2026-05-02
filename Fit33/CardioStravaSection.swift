import SwiftUI

// MARK: - Phase 4 Cardio Section Strava Surface
//
// Two pieces that the Cardio landing view drops in below the
// "Powered by Strava" lockup:
//
//   • CardioStravaWeeklyDeltaChip  — single-line "This week vs last week"
//                                     summary (distance + time deltas).
//                                     Pulls from `StravaService.shared.recentActivities`,
//                                     gates on `StravaService.shared.isConnected`.
//
//   • CardioRecentLogSection       — UNIFIED recent activity log (Strava +
//                                     Fit33 native + WHOOP / Apple Watch /
//                                     Oura / Fitbit / Garmin / etc.).
//                                     Shape-matches the Home tab's
//                                     `RecentCardioWorkoutCard` but paints
//                                     SOURCE-driven accents:
//                                       - Strava   → orange (#FC4C02)
//                                       - Fit33    → blue
//                                       - Wearables (WHOOP / Apple Watch /
//                                         Oura / Fitbit / Garmin / etc.)
//                                                  → "white" (.primary —
//                                         renders white in dark mode and
//                                         dark gray in light mode so it
//                                         stays visible on both card fills)
//                                     Loads via `SupabaseManager.fetchRecentCardioWorkouts`,
//                                     so it surfaces ANY cardio history —
//                                     no Strava-connected gate.

// MARK: - Container (legacy — kept thin for backward compat)
//
// Pre-2026-05-02 this struct rendered both the weekly delta chip and a
// horizontal mini-card recent row. The recent row has been promoted to
// `CardioRecentLogSection` (a sibling section on `CardioLandingView`)
// because the unified log shouldn't gate on Strava-connected. The
// container now only holds the Strava-specific weekly trend chip — the
// only piece that legitimately depends on `StravaService.recentActivities`.
struct CardioStravaSection: View {
    @ObservedObject private var stravaService = StravaService.shared

    var body: some View {
        if stravaService.isConnected {
            CardioStravaWeeklyDeltaChip()
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

// MARK: - Cardio Recent Log Section
//
// 2026-05-02 (per-user request) — the cardio landing's "Recent" surface
// is now a UNIFIED activity log, not a Strava-only mini-card row.
//
// Visual: shape-matches the Home tab's `RecentCardioWorkoutCard` (icon
// ring + title + date + 4-stat row + chevron + sleek card border).
//
// Color: source-driven accent override
//   • Strava        → Strava brand orange  (#FC4C02)
//   • Fit33         → system blue
//   • WHOOP / Apple Watch / Oura / Fitbit / Garmin / Nike / Peloton /
//     Zwift / MapMyRun / Runkeeper / adidas / Apple Health (.unknown)
//                    → `.primary` (white in dark mode, dark gray in
//                       light mode — stays legible on both card fills,
//                       matches the user's "white" intent for
//                       passive wearable data)
//
// Data: pulls from `SupabaseManager.fetchRecentCardioWorkouts(limit: 8)`
// — same RPC the Home tab uses, just deeper. No Strava-connected gate
// since the log is meant to surface ALL cardio sources.
//
// Empty state: a thin "Your cardio log will live here" hint when the
// user has zero rows so the section never renders as blank space.
struct CardioRecentLogSection: View {
    @State private var workouts: [CardioWorkoutDTO] = []
    @State private var loaded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }

            if loaded && workouts.isEmpty {
                emptyHint
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(workouts, id: \.id) { workout in
                        RecentCardioWorkoutCard(
                            cardioWorkout: workout,
                            isMostRecent: false,
                            accentColorOverride: Self.sourceAccent(for: workout.resolvedOrigin)
                        )
                    }
                }
            }
        }
        .task { await loadRecent() }
    }

    @MainActor
    private func loadRecent() async {
        do {
            // limit: 8 — matches the legacy Strava mini-card cap and
            // gives the user a full week of recent activity at typical
            // 4-6 sessions/week without overwhelming the page.
            let rows = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 8)
            self.workouts = rows
        } catch {
            AppLogger.warning(
                "[CARDIO] CardioRecentLogSection load failed: \(error.localizedDescription)",
                category: .ui
            )
            self.workouts = []
        }
        self.loaded = true
    }

    // MARK: - Source-driven accent palette

    /// Maps a cardio workout's resolved origin to the accent color the
    /// recent log should paint. Returns `nil` only for the
    /// best-effort `.unknown` fallback when we want the per-activity
    /// color to take over (e.g., legacy Apple Health imports without
    /// origin tagging).
    static func sourceAccent(for origin: WorkoutOrigin) -> Color? {
        switch origin {
        case .strava:
            // Strava brand orange #FC4C02.
            return Color(red: 0xFC/255, green: 0x4C/255, blue: 0x02/255)
        case .fit33:
            return .blue
        case .whoop, .appleWatch, .oura, .fitbit, .garmin,
             .nikeRunClub, .peloton, .zwift, .mapMyRun,
             .runkeeper, .adidasRunning:
            // "White" per-user request. `.primary` is white in dark mode
            // and near-black in light mode — the only neutral that stays
            // visible on both `.adaptiveSleekCard` fills. WHOOP /
            // wearables get the same neutral so the entire passive-data
            // bucket reads as one visual category.
            return .primary
        case .unknown:
            // Legacy HK rows without origin_app — let the per-activity
            // color (running=green, walk=blue, etc.) take over.
            return nil
        }
    }

    private var emptyHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run.circle")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Your cardio log will live here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
    }
}
