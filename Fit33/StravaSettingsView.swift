//
//  StravaSettingsView.swift
//  Fit33
//
//  Premium Strava integration page — connection management + as much of the
//  rich data we pull from Strava as we can surface in one place. Mirrors the
//  visual language of `WhoopSettingsView` (sleek hero card + grouped sleek
//  cards on `AnimatedOrbBackground`) so the wearable settings pages feel
//  cohesive.
//
//  Sections (in order):
//   1. Connection card — profile, name, last sync, sync now, disconnect.
//   2. This Week / This Month — quick totals from the synced activity list.
//   3. Recent (4w) / YTD / All-Time — long-form `/athletes/{id}/stats` totals
//      per sport (run / ride / swim).
//   4. Mileage chart — weekly km stacked by activity type.
//   5. Pace trend chart — 4-week rolling avg run pace.
//   6. Recent activities list — tap → `StravaActivityRecapSheet`.
//   7. About — what syncs, automatic refresh, 60-day inactivity behavior.
//

import SwiftUI
import AuthenticationServices

// MARK: - Strava Settings View

struct StravaSettingsView: View {
    @StateObject private var strava = StravaService.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDisconnectAlert = false
    @State private var selectedActivity: StravaActivity?
    @State private var showingRecap = false
    @State private var isAuthenticating = false
    @State private var authErrorMessage: String?
    @State private var webAuthSession: ASWebAuthenticationSession?

    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    connectionTile

                    if strava.isConnected {
                        section(title: "This Period", icon: "calendar.badge.clock") {
                            thisPeriodCard
                        }
                        section(title: "Lifetime Totals", icon: "trophy.fill") {
                            longFormStatsCard
                        }
                        chartsCard
                        section(title: "Recent Activities", icon: "figure.run") {
                            recentActivitiesCard
                        }
                        syncStatusCard
                    }

                    section(title: "About", icon: "info.circle.fill", iconColor: .secondary) {
                        aboutCard
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, 60)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("PoweredByStrava")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
                    .accessibilityLabel("Powered by Strava")
            }
        }
        .alert("Disconnect Strava?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                strava.disconnect()
            }
        } message: {
            Text("Your synced activities will remain in Fit33, but new activities won't sync until you reconnect.")
        }
        .sheet(isPresented: $showingRecap) {
            if let selectedActivity {
                StravaActivityRecapSheet(activity: selectedActivity)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            // Refresh keychain-backed connection state on every appearance —
            // mirrors the WHOOP / Oura settings pages.
            strava.refreshConnectionState()
        }
        .task {
            // Best-effort foreground sync on entry. Throttled internally so
            // tab-switching back here doesn't spam the API.
            if strava.isConnected {
                await strava.syncActivities(daysBack: 30, force: false)
            }
        }
    }

    // MARK: - OAuth (direct ASWebAuthenticationSession, no intermediate sheet)

    private func startAuth() {
        guard let authURL = strava.getAuthorizationURL() else {
            authErrorMessage = "Could not create authorization URL"
            return
        }

        isAuthenticating = true
        authErrorMessage = nil

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            Task { @MainActor in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        AppLogger.debug("[STRAVA] User cancelled login", category: .health)
                    } else {
                        authErrorMessage = error.localizedDescription
                    }
                    isAuthenticating = false
                    return
                }

                guard let callbackURL = callbackURL else {
                    authErrorMessage = "No callback URL received"
                    isAuthenticating = false
                    return
                }

                await handleAuthCallback(callbackURL)
            }
        }

        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
        webAuthSession = session
    }

    private func handleAuthCallback(_ url: URL) async {
        do {
            try await strava.handleCallback(url: url)
            await MainActor.run {
                isAuthenticating = false
            }
        } catch {
            await MainActor.run {
                authErrorMessage = error.localizedDescription
                isAuthenticating = false
            }
        }
    }

    // MARK: - 1. Connection Tile (floating, no card chrome)

    /// Section wrapper that renders a `SectionHeader` above the supplied
    /// content with tight `Spacing.sm` between them — mirrors the dashboard
    /// pattern of "title outside the card".
    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        iconColor: Color = Color.stravaOrange,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: title, icon: icon, iconColor: iconColor)
            content()
        }
    }

    private var connectionTile: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                profileAvatar
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: strava.isConnected ? "checkmark.circle.fill" : "link.badge.plus")
                            .foregroundColor(strava.isConnected ? .green : .secondary)
                            .font(.ds_bodySmall)
                        Text(strava.isConnected ? "Connected" : "Not connected")
                            .font(.ds_labelLarge)
                            .foregroundColor(strava.isConnected ? .green : .secondary)
                    }
                    if let athlete = strava.athleteProfile {
                        Text(athlete.fullName)
                            .font(.ds_heading3)
                    } else if !strava.isConnected {
                        Text("Connect Strava")
                            .font(.ds_heading3)
                    }
                    if let location = athleteLocation {
                        Text(location)
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            if strava.isConnected {
                Button {
                    showingDisconnectAlert = true
                } label: {
                    Text("Disconnect")
                        .font(.ds_labelLarge)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color.red.opacity(0.12))
                        )
                }
                .buttonStyle(UniversalScaleButtonStyle())
                .accessibilityLabel("Disconnect Strava")
                .accessibilityHint("Removes Strava connection and stops syncing new activities.")
            } else {
                Button(action: startAuth) {
                    ZStack {
                        Image("ConnectWithStravaButton")
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(height: 44)
                            .opacity(isAuthenticating ? 0 : 1)

                        if isAuthenticating {
                            ProgressView()
                                .tint(Color.stravaOrange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(UniversalScaleButtonStyle())
                .disabled(isAuthenticating)
                .accessibilityLabel("Connect Strava")
                .accessibilityHint("Opens Strava sign-in to link your account.")

                Text("Sync runs, rides, walks, hikes, swims and more. We refresh automatically — once you connect, you stay connected.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = authErrorMessage ?? strava.errorMessage {
                    Text(error)
                        .font(.ds_bodySmall)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
    }

    private var profileAvatar: some View {
        Group {
            if let profileUrl = strava.athleteProfile?.profile,
               let url = URL(string: profileUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.stravaOrange.opacity(0.3), lineWidth: 1.5)
                )
            } else {
                avatarPlaceholder
                    .frame(width: 56, height: 56)
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.stravaOrange.opacity(0.18))
            .overlay(
                Image(systemName: "figure.run")
                    .font(.ds_heading3)
                    .foregroundColor(Color.stravaOrange)
            )
    }

    private var athleteLocation: String? {
        guard let athlete = strava.athleteProfile else { return nil }
        let parts = [athlete.city, athlete.state, athlete.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - 2. This Week / This Month Card

    private var thisPeriodCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(spacing: Spacing.sm) {
                periodRow(
                    title: "This Week",
                    activityCount: weeklyActivityCount,
                    distanceKm: strava.weeklyDistanceKm,
                    minutes: strava.weeklyCardioMinutes,
                    calories: strava.weeklyCaloriesBurned,
                    elevationM: Int(strava.weeklyElevationGain)
                )

                Divider().opacity(0.35)

                periodRow(
                    title: "This Month",
                    activityCount: strava.monthlyActivities.count,
                    distanceKm: monthlyDistanceKm,
                    minutes: monthlyMinutes,
                    calories: monthlyCalories,
                    elevationM: Int(monthlyElevation)
                )

                if let pace = strava.weeklyAveragePaceSecondsPerKm {
                    Divider().opacity(0.35)
                    HStack {
                        Image(systemName: "stopwatch")
                            .foregroundColor(.green)
                        Text("Avg run pace this week")
                            .font(.ds_bodyMedium)
                        Spacer()
                        Text(formatPace(pace))
                            .font(.ds_statSmall)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
    }

    private func periodRow(
        title: String,
        activityCount: Int,
        distanceKm: Double,
        minutes: Int,
        calories: Int,
        elevationM: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(activityCount) activit\(activityCount == 1 ? "y" : "ies")")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 0) {
                miniMetric(
                    value: String(format: "%.1f", unitSettings.stravaDistanceValue(meters: distanceKm * 1_000)),
                    unit: unitSettings.stravaDistanceShortLabel,
                    label: "Distance",
                    color: Color.stravaOrange
                )
                miniMetric(value: "\(minutes)", unit: "min", label: "Time", color: .blue)
                miniMetric(value: "\(calories)", unit: "cal", label: "Burned", color: .orange)
                miniMetric(
                    value: elevationDisplay(metersInt: elevationM).value,
                    unit: elevationDisplay(metersInt: elevationM).unit,
                    label: "Elev",
                    color: .brown
                )
            }
        }
    }

    private func miniMetric(value: String, unit: String, label: String, color: Color) -> some View {
        VStack(spacing: Spacing.xxxs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(value == "0" || value == "0.0" ? .primary.opacity(0.5) : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. Long-Form Stats (Recent / YTD / All-Time)

    private var longFormStatsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let stats = strava.athleteStats, hasAnyTotals(stats) {
                VStack(spacing: Spacing.md) {
                    if let runs = stats.recentRunTotals, (runs.count ?? 0) > 0 {
                        sportTotalsBlock(sport: "Running", icon: "figure.run", recent: stats.recentRunTotals, ytd: stats.ytdRunTotals, allTime: stats.allRunTotals)
                    }
                    if let rides = stats.recentRideTotals, (rides.count ?? 0) > 0 {
                        sportTotalsBlock(sport: "Cycling", icon: "bicycle", recent: stats.recentRideTotals, ytd: stats.ytdRideTotals, allTime: stats.allRideTotals)
                    }
                    if let swims = stats.recentSwimTotals, (swims.count ?? 0) > 0 {
                        sportTotalsBlock(sport: "Swimming", icon: "figure.pool.swim", recent: stats.recentSwimTotals, ytd: stats.ytdSwimTotals, allTime: stats.allSwimTotals)
                    }
                }
            } else {
                Text("Lifetime totals will appear once Strava finishes computing your athlete stats.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
    }

    private func hasAnyTotals(_ stats: StravaAthleteStats) -> Bool {
        return [stats.recentRunTotals, stats.recentRideTotals, stats.recentSwimTotals]
            .compactMap { $0?.count }
            .contains(where: { $0 > 0 })
    }

    private func sportTotalsBlock(sport: String, icon: String, recent: StravaTotals?, ytd: StravaTotals?, allTime: StravaTotals?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .foregroundColor(Color.stravaOrange)
                Text(sport)
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
            }

            HStack(spacing: 0) {
                totalsCell(label: "Recent (4w)", totals: recent)
                totalsCell(label: "Year to Date", totals: ytd)
                totalsCell(label: "All-Time", totals: allTime)
            }
        }
    }

    private func totalsCell(label: String, totals: StravaTotals?) -> some View {
        VStack(spacing: Spacing.xxxs) {
            Text(formatDistance(totals?.distance))
                .font(.ds_statSmall)
                .foregroundColor(totals?.distance == nil ? .primary.opacity(0.5) : Color.stravaOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(totals?.count ?? 0) activit\((totals?.count ?? 0) == 1 ? "y" : "ies")")
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4 & 5. Charts Card

    private var chartsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // The two existing chart widgets read directly from
            // `StravaService.shared.recentActivities` and gate their own
            // empty states. We just stack them inside one sleek card so the
            // section reads as "Trends".
            StravaMileageChartWidget()
            StravaPaceTrendChartWidget()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
    }

    // MARK: - 6. Recent Activities

    private var recentActivitiesCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if strava.recentActivities.isEmpty {
                if strava.isLoading {
                    Text("Syncing activities…")
                        .font(.ds_bodyMedium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else {
                    laceUpEmptyState
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(strava.recentActivities.prefix(10).enumerated()), id: \.element.id) { index, activity in
                        Button {
                            HapticManager.tap()
                            selectedActivity = activity
                            showingRecap = true
                        } label: {
                            activityRow(activity)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityHint("Tap to see splits, segments, and a recap")

                        if index < min(10, strava.recentActivities.count) - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
    }

    /// Friendly nudge shown when the user is connected but has no recent
    /// Strava activities synced yet. Encourages them to start a run; the
    /// activity will then auto-sync on completion.
    private var laceUpEmptyState: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.stravaOrange.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color.stravaOrange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Lace up — your next run lands here")
                    .font(.ds_bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Start a run on Strava and it'll sync the moment you finish — splits, HR, segments, and your pace trends update automatically.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.stravaOrange.opacity(0.08))
        )
    }

    private func activityRow(_ activity: StravaActivity) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: activity.activityIcon)
                .font(.ds_heading3)
                .foregroundColor(Color.stravaOrange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.ds_bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(activity.distanceFormatted)
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(activity.durationFormatted)
                    if let pace = activity.paceFormatted {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(pace)
                    }
                    if let hr = activity.averageHeartrate {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("\(Int(hr)) bpm")
                    }
                }
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }

            Spacer(minLength: Spacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(activity.startDate, format: .dateTime.month(.abbreviated).day())
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                if let suffer = activity.sufferScore {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("\(suffer)")
                    }
                    .font(.ds_labelSmall)
                    .foregroundColor(.purple)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - 7. Sync Status

    private var syncStatusCard: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text("Last Sync")
                    .font(.ds_bodyMedium)
                Spacer()
                if strava.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let date = strava.lastSyncDate {
                    Text(date, style: .relative)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                } else {
                    Text("Never")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task { await strava.syncActivities(daysBack: 30, force: true) }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Now")
                }
                .font(.ds_labelMedium)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(UniversalScaleButtonStyle())
            .disabled(strava.isLoading)
            .accessibilityLabel("Sync Strava data now")
            .accessibilityHint("Forces an immediate refresh of activities and lifetime totals.")

            if let error = strava.errorMessage {
                Text(error)
                    .font(.ds_bodySmall)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Strava sync error")
                    .accessibilityValue(error)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            aboutBullet(icon: "figure.run", text: "Runs, rides, walks, hikes, swims and more")
            aboutBullet(icon: "heart.fill", text: "Heart rate (avg + max), pace, splits, calories")
            aboutBullet(icon: "mountain.2.fill", text: "Elevation gain and effort (suffer score)")
            aboutBullet(icon: "map.fill", text: "Route map, segment efforts, and HR streams")
            aboutBullet(icon: "arrow.triangle.2.circlepath", text: "Auto-syncs in the background — once connected, you stay connected")
            aboutBullet(icon: "lock.fill", text: "Tokens refresh automatically; only disconnects if you tap Disconnect, delete your account, or stay away 60+ days")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .secondary)
    }

    private func aboutBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(Color.stravaOrange)
                .frame(width: 18)
            Text(text)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Computed period totals

    private var weeklyActivityCount: Int {
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        return strava.recentActivities.filter { $0.startDate >= start }.count
    }

    private var monthlyDistanceKm: Double {
        strava.monthlyActivities.reduce(0) { $0 + ($1.distance / 1000) }
    }

    private var monthlyMinutes: Int {
        strava.monthlyActivities.reduce(0) { $0 + ($1.movingTime / 60) }
    }

    private var monthlyCalories: Int {
        strava.monthlyActivities.reduce(0) { $0 + ($1.calories ?? 0) }
    }

    private var monthlyElevation: Double {
        strava.monthlyActivities.reduce(0) { $0 + ($1.totalElevationGain ?? 0) }
    }

    // MARK: - Formatters

    private func formatDistance(_ meters: Double?) -> String {
        guard let m = meters, m > 0 else { return "—" }
        return unitSettings.formatStravaDistance(meters: m)
    }

    private func formatPace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "—" }
        return unitSettings.formatStravaPace(secondsPerKm: secondsPerKm)
    }

    /// Format an elevation given as integer meters into the user's
    /// preferred unit (meters or feet) for the period mini-metric strip.
    private func elevationDisplay(metersInt: Int) -> (value: String, unit: String) {
        switch unitSettings.distanceUnit {
        case .imperial:
            let feet = Int((Double(metersInt) * 3.28084).rounded())
            return ("\(feet)", "ft")
        case .metric:
            return ("\(metersInt)", "m")
        }
    }

}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StravaSettingsView()
    }
}
