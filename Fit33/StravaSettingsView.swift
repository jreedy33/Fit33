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
//  Sections (in order — 2026-05-02 layout):
//   • Toolbar:    Powered-by-Strava lockup (center) + manual-sync arrow
//                 button (trailing — spins while `strava.isLoading`).
//   1. Connection card — avatar + Connected chip + name + location.
//                        NO disconnect / export / sync buttons; those
//                        live elsewhere now.
//   2. This Week / This Month — quick totals from the synced activity list.
//   3. Recent (4w) / YTD / All-Time — long-form `/athletes/{id}/stats` totals
//      per sport (run / ride / swim).
//   4. Mileage chart — weekly km stacked by activity type.
//   5. Pace trend chart — 4-week rolling avg run pace.
//   6. Recent activities list — tap → `StravaActivityRecapSheet`.
//   7. About — what syncs, automatic refresh, 48h-deletion compliance.
//   8. Account actions — Disconnect + Export my Strava data.
//                        Sits BELOW About so the destructive / data-rights
//                        controls are at the END of the page (per user
//                        request), not stacked under the avatar.
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

    /// 2026-05-02 Strava compliance: temp-file URL of the user's exported
    /// Strava activity JSON, populated on demand by `prepareDataExport()`
    /// when they tap "Export my Strava data". Cleared after the share
    /// sheet dismisses to keep the temp dir tidy.
    @State private var dataExportFile: DataExportFile?

    /// 2026-05-02 — when the user taps a Strava-origin row in the home
    /// dashboard's recent-activity list, we reuse this view as the
    /// activity recap surface (per user request). The "This Period"
    /// section's first row swaps from "This Week" totals to "This Run"
    /// stats sourced from this single activity, while "This Month" and
    /// every section below stays unchanged. `nil` keeps the legacy
    /// behavior (settings entry from the dashboard widget tap or the
    /// settings menu).
    let focusedActivity: StravaActivity?

    init(focusedActivity: StravaActivity? = nil) {
        self.focusedActivity = focusedActivity
    }

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
                    }

                    section(title: "About", icon: "info.circle.fill", iconColor: .secondary) {
                        aboutCard
                    }

                    // 2026-05-02 layout follow-up: Disconnect + Export
                    // moved from the top connection tile to a dedicated
                    // card BELOW About, so the destructive / data-export
                    // controls are at the bottom of the page (where the
                    // user has finished reading what the integration
                    // does), not stacked under the user's avatar.
                    if strava.isConnected {
                        accountActionsCard
                    }

                    if let error = strava.errorMessage, strava.isConnected {
                        // The old syncStatusCard surfaced sync errors
                        // inline. With the manual sync now living in the
                        // toolbar, errors get a small standalone caption
                        // so the user can still see WHY a sync didn't go
                        // through.
                        Text(error)
                            .font(.ds_bodySmall)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Spacing.md)
                            .accessibilityLabel("Strava sync error")
                            .accessibilityValue(error)
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
            // 2026-05-02 layout follow-up: dedicated "Sync now" affordance
            // sits to the right of the Powered-by-Strava lockup. Replaces
            // the prior `syncStatusCard` (the "Last Sync" widget). When
            // `strava.isLoading == true`, the icon spins continuously to
            // show in-flight progress; otherwise tapping kicks a manual
            // force-refresh of the activity list.
            ToolbarItem(placement: .topBarTrailing) {
                if strava.isConnected {
                    Button {
                        Task { await strava.syncActivities(daysBack: 30, force: true) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.ds_labelLarge.weight(.semibold))
                            .foregroundColor(Color.stravaOrange)
                            .rotationEffect(.degrees(strava.isLoading ? 360 : 0))
                            .animation(
                                strava.isLoading
                                    ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                    : .default,
                                value: strava.isLoading
                            )
                    }
                    .disabled(strava.isLoading)
                    .accessibilityLabel("Sync Strava data now")
                    .accessibilityHint("Forces an immediate refresh of activities and lifetime totals.")
                }
            }
        }
        .alert("Disconnect Strava?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect & Delete Data", role: .destructive) {
                strava.disconnect()
            }
        } message: {
            // Strava API Agreement requires that revoking authorization
            // purges all Personal Data we hold for the user. The
            // destructive button is now explicit so the user knows what
            // will happen — and `disconnect()` calls the
            // `delete_my_strava_data` RPC to actually do the cascade
            // delete on the server (cardio_workouts + user_strava_tokens).
            Text("Disconnecting will delete every Strava activity Fit33 has imported and remove our access to your Strava account. Your activities on Strava itself are not affected. You can reconnect any time to start syncing fresh.")
        }
        .sheet(isPresented: $showingRecap) {
            if let selectedActivity {
                StravaActivityRecapSheet(activity: selectedActivity)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $dataExportFile, onDismiss: {
            // Cleanup the temp file when the sheet dismisses.
            cleanupDataExport()
        }) { exportFile in
            // 2026-05-02 Strava compliance: data-access right via iOS share
            // sheet. Reuses the canonical `ShareSheet` from
            // `Fit33/DevSessionLogsView.swift` (it lives outside #if DEBUG).
            ShareSheet(items: [exportFile.url])
                .ignoresSafeArea()
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
            if strava.isConnected {
                // 2026-05-02 layout follow-up: only profile + connected
                // chip live up here now. Disconnect + Export moved into
                // `accountActionsCard` (below About). Manual sync moved
                // to the toolbar trailing edge.
                //
                // 2026-05-02 (later) — also surface the Strava
                // `@username` handle so the "this is YOUR Strava" signal
                // is unambiguous when the page is reused as the activity
                // recap target (focusedActivity). The avatar comes from
                // `athlete.profile`, full name from `firstname lastname`,
                // username from `athlete.username` (Strava's user-chosen
                // handle, may be nil for older accounts), location from
                // `city / state / country` joined with commas.
                HStack(spacing: Spacing.md) {
                    profileAvatar
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.ds_bodySmall)
                            Text("Connected")
                                .font(.ds_labelLarge)
                                .foregroundColor(.green)
                        }
                        if let athlete = strava.athleteProfile {
                            Text(athlete.fullName)
                                .font(.ds_heading3)
                            if let handle = athlete.username, !handle.isEmpty {
                                Text("@\(handle)")
                                    .font(.ds_bodySmall)
                                    .foregroundColor(Color.stravaOrange)
                                    .accessibilityLabel("Strava username at \(handle)")
                            }
                        }
                        if let location = athleteLocation {
                            Text(location)
                                .font(.ds_bodySmall)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(Color.stravaOrange)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.sm)
                    .accessibilityHidden(true)

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
                // "This Run" row replaces "This Week" when the screen
                // was opened by tapping a specific Strava activity from
                // the home dashboard. Same `periodRow` shape (so the
                // visual rhythm of the card is preserved) — count is
                // forced to 1, totals are sourced from the single
                // activity. When unfocused (settings entry), we render
                // the legacy "This Week" rollup.
                if let activity = focusedActivity {
                    periodRow(
                        title: "This Run",
                        activityCount: 1,
                        distanceKm: activity.distance / 1_000,
                        minutes: activity.movingTime / 60,
                        calories: activity.calories ?? 0,
                        elevationM: Int(activity.totalElevationGain ?? 0)
                    )
                } else {
                    periodRow(
                        title: "This Week",
                        activityCount: weeklyActivityCount,
                        distanceKm: strava.weeklyDistanceKm,
                        minutes: strava.weeklyCardioMinutes,
                        calories: strava.weeklyCaloriesBurned,
                        elevationM: Int(strava.weeklyElevationGain)
                    )
                }

                Divider().opacity(0.35)

                periodRow(
                    title: "This Month",
                    activityCount: strava.monthlyActivities.count,
                    distanceKm: monthlyDistanceKm,
                    minutes: monthlyMinutes,
                    calories: monthlyCalories,
                    elevationM: Int(monthlyElevation)
                )

                // Pace row swaps too: when focused, show the tapped
                // activity's pace ("Pace this run") instead of the
                // weekly avg ("Avg run pace this week"). Strava reports
                // pace as seconds/meter on the activity, so we convert
                // to the canonical seconds-per-km the rest of the page
                // uses via `activity.paceSecondsPerKm`.
                if let activity = focusedActivity {
                    if let pace = activity.paceSecondsPerKm {
                        Divider().opacity(0.35)
                        HStack {
                            Image(systemName: "stopwatch")
                                .foregroundColor(.green)
                            Text("Pace this run")
                                .font(.ds_bodyMedium)
                            Spacer()
                            Text(formatPace(pace))
                                .font(.ds_statSmall)
                                .foregroundColor(.green)
                        }
                    }
                } else if let pace = strava.weeklyAveragePaceSecondsPerKm {
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
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
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
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
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
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
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
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: Color.stravaOrange)
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

    // MARK: - Account Actions (Disconnect + Export)
    //
    // 2026-05-02 layout follow-up: lives BELOW About (per user request)
    // so the destructive / data-export controls sit at the bottom of the
    // page after the user has read what the integration does. Both
    // buttons used to live in `connectionTile` at the top; moving them
    // here also tightens the connection-tile visual to "who you are"
    // signal only (avatar + name + location + Connected chip).
    //
    // Manual sync isn't here — it's in the toolbar (see top-of-file
    // `.toolbar` block). The card has no card chrome (`.adaptiveSleekCard`)
    // so the buttons read as a discrete actions block, not a third stats
    // card.

    private var accountActionsCard: some View {
        VStack(spacing: Spacing.sm) {
            // 2026-05-02 Strava compliance: API Agreement §"Privacy"
            // requires that revoking authorization deletes all Personal
            // Data. The destructive label + alert copy make that
            // explicit (cardio_workouts WHERE source='strava' + the
            // user_strava_tokens row are purged via
            // `delete_my_strava_data` RPC; webhook also handles the
            // server-initiated revoke path).
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
            .accessibilityHint("Removes Strava connection and deletes every Strava activity Fit33 has imported.")

            // 2026-05-02 Strava compliance: API Agreement requires the
            // user be able to access the Strava data we've collected on
            // their behalf at any time. Serializes `recentActivities`
            // to JSON, writes a temp file, opens the iOS share sheet.
            Button {
                prepareDataExport()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export my Strava data")
                }
                .font(.ds_labelLarge)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.blue.opacity(0.10))
                )
            }
            .buttonStyle(UniversalScaleButtonStyle())
            .accessibilityLabel("Export Strava data")
            .accessibilityHint("Saves a JSON file of every Strava activity Fit33 has imported.")
        }
        .padding(.horizontal, Spacing.xs)
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            aboutBullet(icon: "figure.run", text: "Runs, rides, walks, hikes, swims and more")
            aboutBullet(icon: "heart.fill", text: "Heart rate (avg + max), pace, splits, calories")
            aboutBullet(icon: "mountain.2.fill", text: "Elevation gain and effort (suffer score)")
            aboutBullet(icon: "map.fill", text: "Route map, segment efforts, and HR streams")
            aboutBullet(icon: "arrow.triangle.2.circlepath", text: "Auto-syncs in the background — once connected, you stay connected")
            aboutBullet(icon: "trash.fill", text: "Delete an activity on Strava and we'll remove it from Fit33 within minutes — disconnecting also deletes everything Fit33 has imported")
            // Strava API Agreement: Activity data via the Strava API may
            // include data that requires attribution to Garmin. Fit33
            // renders Strava-normalized metrics (distance, time, pace, HR)
            // and links out to Strava itself for the canonical device /
            // gear attribution surface — that's where third-party device
            // brand names (Garmin / Wahoo / etc.) live. We disclose this
            // here so the user (and any Strava reviewer) can see the
            // attribution chain.
            aboutBullet(
                icon: "applewatch.side.right",
                text: "Activities recorded on third-party devices (Garmin, Wahoo, etc.) are attributed to those device makers on Strava itself — tap 'View on Strava' on any activity to see the original source"
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: .secondary)
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

    // MARK: - Strava Data Export (2026-05-02 compliance)
    //
    // Strava API Agreement §"Privacy" requires that we make Strava data
    // we've collected available to the user on demand. Export path:
    //   1. Encode `recentActivities` (the in-memory cache that
    //      `StravaService` keeps fresh) as pretty-printed JSON.
    //   2. Write to a temp file named `fit33-strava-export-{ISO8601}.json`.
    //   3. Present the iOS share sheet so the user can save to Files,
    //      iCloud, AirDrop, email it, etc.
    //   4. Clean up the temp file on share-sheet dismiss.

    private func prepareDataExport() {
        let activities = strava.recentActivities
        guard !activities.isEmpty else {
            authErrorMessage = "No Strava activities to export. Pull to refresh and try again."
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        do {
            let data = try encoder.encode(activities)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let timestamp = isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let fileName = "fit33-strava-export-\(timestamp).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            AppLogger.info("[STRAVA] Prepared data export at \(url.lastPathComponent) (\(activities.count) activities)", category: .health)
            dataExportFile = DataExportFile(url: url)
        } catch {
            AppLogger.error("[STRAVA] Data export failed: \(error.localizedDescription)", category: .health)
            authErrorMessage = "Couldn't prepare your data export. Please try again."
        }
    }

    private func cleanupDataExport() {
        guard let exportFile = dataExportFile else { return }
        try? FileManager.default.removeItem(at: exportFile.url)
        dataExportFile = nil
    }
}

// MARK: - Strava Data Export File

/// Identifiable wrapper for the temp file URL produced by
/// `StravaSettingsView.prepareDataExport()`. URL-keyed so SwiftUI's
/// `.sheet(item:)` correctly re-renders if the user re-exports during
/// the same session (each export gets a unique timestamped filename).
private struct DataExportFile: Identifiable {
    let url: URL
    var id: URL { url }
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
