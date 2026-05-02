import SwiftUI
import MapKit
import CoreLocation

// MARK: - OutdoorCardioActiveView
//
// Cardio Redesign — Wave 4b → Wave 4f visual refresh (2026-05-02).
//
// Active workout screen for outdoor walk / run / cycle / hike sessions.
// Strava-style: the GPS map fills the entire screen and frosted
// (`.ultraThinMaterial`) widgets float on top, branded with the
// per-activity accent color (Walk = teal, Run = blue, Cycle = cyan,
// Hike = orange) so the user can see the route through the chrome.
//
// Layout (ZStack):
//   [ Map full-bleed                                          ]
//   [    polyline (accent color) + UserAnnotation             ]
//   ┌──────────────────────────────────────────────────────────┐
//   │  ◀  return     [ 🏃 Run · 12:34 ]      📍 GPS Excellent │  topBar (frosted)
//   │                                                          │
//   │  (map shows through here)                                │
//   │                                                          │
//   │  ┌────────────────────────────────────────────────────┐  │
//   │  │ PACE                                               │  │  focused tile (frosted)
//   │  │   7'42"                                            │  │
//   │  │   ████████░░░░  2.30 / 3.11 mi                     │  │
//   │  └────────────────────────────────────────────────────┘  │
//   │  ┌──────────┐  ┌──────────┐                              │
//   │  │ DISTANCE │  │ TIME     │                              │  2×2 frosted grid
//   │  │ 2.30 mi  │  │ 18:42    │                              │
//   │  └──────────┘  └──────────┘                              │
//   │  ⏸ Pause                ✕ End                            │  control bar
//   └──────────────────────────────────────────────────────────┘
//
// Top-left chevron MINIMIZES the cover — `CardioSessionManager.minimize()`
// hides this view without ending the workout (GPS engine + Live Activity
// keep running). The user returns by tapping the (now red) Workout tab in
// the bottom tab bar — `MainTabView` calls `restore()` on tap.
//
// Sourced state:
//   • `RunningManager.shared`  → live telemetry (distance, pace, route…)
//   • `CardioSessionManager.shared` → phase, countdown, minimize/restore.
struct OutdoorCardioActiveView: View {
    @ObservedObject private var run = RunningManager.shared
    @ObservedObject private var session = CardioSessionManager.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    /// Heading-up map follow with the user's location dot pushed UP into
    /// the visible map window (above the bottom frosted stack). Strava
    /// does the same — the user is roughly 1/3 down from the top, so the
    /// route they're about to traverse fills the screen. We achieve this
    /// by manually driving a `MapCamera` whose `centerCoordinate` is
    /// offset ~80m BEHIND the user (opposite the heading direction) — in
    /// heading-up mode that visually shifts the dot upward by ~25-30%
    /// of the viewport. Updates on every `currentLocation` /
    /// `currentHeading` change. Falls back to plain user-location follow
    /// before GPS lock.
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            latitudinalMeters: 400,
            longitudinalMeters: 400
        ))
    )

    /// How far the camera center sits BEHIND the user (opposite the
    /// heading direction). Larger value = dot pushed higher on screen.
    /// 100m at 1300m camera distance ≈ user dot ~25% above geometric
    /// screen center — clears the bottom frosted stack, leaves plenty
    /// of map ahead. Tuned 2026-05-02 (user feedback iterations: "too
    /// zoomed in" → 1300m, "too high" → 70m, "too low, move north" →
    /// 100m).
    private let cameraOffsetMeters: Double = 100

    /// Live camera zoom distance in meters. Seeded to 1300m — wider
    /// default so the user sees the next 1-2 blocks ahead instead of
    /// just the street they're on (per 2026-05-02 user feedback:
    /// "zoom the map out by default when the walk/run starts").
    /// If the user pinches to zoom in/out, we capture their preferred
    /// distance via `.onMapCameraChange` and re-use it on every
    /// subsequent programmatic camera update — so heading +
    /// center-offset follow continues but their zoom level is
    /// preserved instead of snapping back on the next GPS sample.
    @State private var userCameraDistance: CLLocationDistance = 1300
    @State private var focusedMetric: FocusedMetric = .pace
    /// Cardio Redesign — Goal-Met sheet (2026-05-02 per user request).
    /// Flips `true` once `RunningManager.goalReached` rises. Shows the
    /// "You hit your X goal!" celebration with End / Keep-going CTAs.
    /// Held outside the sheet's `isPresented:` because we need to
    /// observe `run.goalReached` separately and only allow the sheet to
    /// open ONCE per session (`hasShownGoalMet` keeps it idempotent).
    @State private var showGoalMetSheet: Bool = false
    @State private var hasShownGoalMet: Bool = false

    private enum FocusedMetric: String, CaseIterable {
        case pace, speed, heartRate
        var label: String {
            switch self {
            case .pace:       return "PACE"
            case .speed:      return "SPEED"
            case .heartRate:  return "HEART RATE"
            }
        }
    }

    var body: some View {
        ZStack {
            // Strava-style full-bleed map fills the entire screen — the
            // frosted overlay cards sit ON TOP so the route shows
            // through. Map ignores ALL safe areas (top + bottom) so the
            // route extends edge-to-edge behind the top bar / control
            // bar.
            mapSection
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, Spacing.md)

                Spacer(minLength: 0)

                // Bottom frosted stack — focused metric, 2×2 grid, splits,
                // Pause / End. Padding bottom respects the home indicator.
                VStack(spacing: Spacing.sm) {
                    metricsSection
                    splitsStrip
                    controlBar
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.lg)
                .background(
                    // Soft scrim under the metrics so white text reads
                    // against bright map tiles. Kept very subtle — the
                    // frosted cards do the heavy lifting; this is just
                    // a fallback for satellite-style overlays.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                )
            }

            if run.isAutoPaused {
                autoPausedChip
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 100)
            }

            if session.countdownValue != nil {
                countdownOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(false)
        // Drive the camera manually so the user dot sits HIGH in the
        // visible map (above the frosted bottom stack) — heading-up,
        // tight zoom, center offset ~80m behind the user. See header
        // comment on `cameraOffsetMeters`.
        // 2026-05-02 (per-user request, "i don't want the map moving so
        // much — keep it straight in the clear direction i'm running"):
        // we only re-project the camera when the USER MOVES, not on
        // every magnetometer tick. The motion-derived heading
        // (`motionHeading`) is computed from the GPS polyline so the
        // map only rotates when the user actually changes direction
        // (turn left → map rotates clockwise, stand still → map sits
        // still). The old `run.currentHeading` magnetometer onChange
        // was the source of the jitter and has been removed.
        .onChange(of: run.currentLocation?.latitude) { _, _ in
            updateCameraIfReady()
        }
        .onChange(of: run.currentLocation?.longitude) { _, _ in
            updateCameraIfReady()
        }
        // Capture user pinch-to-zoom so subsequent programmatic
        // camera updates preserve their preferred zoom level instead
        // of snapping back to the default on the next GPS sample.
        // `.onEnd` fires once when the gesture completes — we don't
        // want a per-frame storm during the pinch itself.
        .onMapCameraChange(frequency: .onEnd) { ctx in
            // Sanity-clamp so a runaway value can't break the follow.
            // 100m floor keeps us readable; 5km ceiling matches the
            // furthest a runner would ever reasonably zoom on a route.
            userCameraDistance = max(100, min(5_000, ctx.camera.distance))
        }
        .onAppear {
            updateCameraIfReady()
        }
        // Goal-Met sheet wiring (2026-05-02 per user request).
        // We listen for the `goalReached` rising edge and open the
        // celebration sheet ONCE per session. Subsequent oscillations
        // (e.g., if the engine is paused/resumed) don't re-fire.
        .onChange(of: run.goalReached) { _, reached in
            if reached, !hasShownGoalMet {
                hasShownGoalMet = true
                showGoalMetSheet = true
            }
        }
        .sheet(isPresented: $showGoalMetSheet) {
            CardioGoalMetSheet(
                accent: activityAccent,
                goalLabel: goalLabelForCelebration,
                distance: run.formattedDistance,
                time: run.formattedElapsedTime,
                calories: Int(run.calories),
                onKeepGoing: {
                    showGoalMetSheet = false
                },
                onEnd: {
                    showGoalMetSheet = false
                    // Same end path the bottom red button uses — flips
                    // session phase to `.ended` → `.recap`, the recap
                    // does the Supabase RPC + LP/quest fanout, then
                    // surfaces a card in the unified recent log.
                    HapticManager.notification(.warning)
                    session.end()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if run.routeCoordinates.count >= 2 {
                MapPolyline(coordinates: run.routeCoordinates)
                    .stroke(activityAccent, style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round,
                        lineJoin: .round
                    ))
            }
        }
        .mapControlVisibility(.hidden)
        .mapStyle(.standard(elevation: .realistic))
    }

    // MARK: - Top Bar
    //
    // Strava-inspired floating chrome:
    //   • Left chevron — minimize the cover (workout keeps running).
    //   • Center pill   — activity icon + display name + elapsed time.
    //   • Right pill    — GPS accuracy chip (color-coded).
    //
    // All three sit on `.ultraThinMaterial` capsules so the map shows
    // through. Border picks up the activity accent (teal walk / blue run)
    // for branding signal.
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            minimizeButton
            Spacer(minLength: Spacing.xs)
            activityBadge
            Spacer(minLength: Spacing.xs)
            gpsChip
        }
    }

    /// Top-left chevron-LEFT (back arrow). Tapping minimizes the
    /// active-cardio cover AND navigates the user to the Home tab —
    /// the workout keeps running (GPS engine + Live Activity stay
    /// alive) and the (now red) Workout tab in the bottom tab bar
    /// re-presents this screen on tap.
    private var minimizeButton: some View {
        Button(action: minimize) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle().stroke(activityAccent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        .accessibilityLabel("Back to home")
        .accessibilityHint("Returns to the Home tab — your \(run.activityType.displayName.lowercased()) keeps tracking. Tap the Workout tab to come back to this screen.")
    }

    /// Center activity pill — icon + display name + elapsed time. Uses
    /// the accent color for the icon so the user's eye lands on the
    /// brand color first.
    private var activityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: run.activityType.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(activityAccent)
            Text(run.activityType.displayName.uppercased())
                .font(.ds_labelMedium)
                .foregroundColor(.primary)
                .tracking(1.2)
            Text("•")
                .foregroundColor(.secondary)
            Text(run.formattedElapsedTime)
                .font(.ds_labelMedium)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().stroke(activityAccent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    /// GPS accuracy pill — same `RunningManager.gpsAccuracy` enum that
    /// drives the legacy chip. Color-coded so the user can glance up
    /// and know whether the route is going to be clean.
    private var gpsChip: some View {
        HStack(spacing: 4) {
            Image(systemName: run.gpsAccuracy.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(gpsAccuracyColor)
            Text(gpsShortLabel)
                .font(.ds_labelSmall)
                .tracking(0.5)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().stroke(gpsAccuracyColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .accessibilityLabel("GPS \(run.gpsAccuracy.rawValue)")
    }

    // MARK: - Metrics block (focus + 2x2)

    private var metricsSection: some View {
        VStack(spacing: 12) {
            focusedMetricTile
            secondaryMetricsGrid
        }
    }

    private var focusedMetricTile: some View {
        VStack(spacing: 6) {
            Text(focusedMetric.label)
                .font(.ds_labelMedium)
                .tracking(1.5)
                .foregroundColor(.secondary)
            Text(focusedMetricValue)
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .foregroundStyle(activityAccent)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .shadow(color: activityAccent.opacity(0.35), radius: 8, y: 2)
            if run.goalType != .none, run.goalValue > 0 {
                // Cardio Redesign — labeled goal progress (2026-05-02
                // per user request). The legacy bare `ProgressView`
                // gave the user no idea where they were in the goal;
                // now we surface "2.30 / 3.11 mi" (or "12:34 / 30:00",
                // "187 / 350 kcal") directly under the bar so the
                // remainder is obvious at a glance.
                VStack(spacing: 4) {
                    ProgressView(value: run.goalProgress)
                        .progressViewStyle(.linear)
                        .tint(run.goalReached ? .green : activityAccent)
                        .frame(maxWidth: 240)
                    HStack(spacing: 4) {
                        if run.goalReached {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        Text(goalProgressLabel)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(run.goalReached ? .green : .secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .stroke(activityAccent.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
        .onTapGesture {
            HapticManager.selectionChanged()
            cycleFocusedMetric()
        }
    }

    private var secondaryMetricsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: columns, spacing: 10) {
            metricCard(label: "DISTANCE", value: run.formattedDistance)
            metricCard(label: "TIME", value: run.formattedElapsedTime)
            metricCard(label: "CALORIES", value: String(format: "%.0f", run.calories))
            metricCard(label: "ELEVATION", value: String(format: "%.0f m", run.elevationGain))
        }
    }

    private func metricCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.ds_labelSmall)
                .tracking(1)
                .foregroundColor(.secondary)
            Text(value)
                .font(.ds_stat)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .stroke(activityAccent.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    // MARK: - Splits strip

    @ViewBuilder
    private var splitsStrip: some View {
        if !run.splits.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(run.splits) { split in
                        VStack(spacing: 2) {
                            Text("\(split.kilometer)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(split.formattedPace)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                        .frame(width: 56, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(activityAccent.opacity(0.10))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: togglePause) {
                Label(run.isPaused ? "Resume" : "Pause",
                      systemImage: run.isPaused ? "play.fill" : "pause.fill")
                    .font(.ds_labelLarge)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .stroke(activityAccent.opacity(0.45), lineWidth: 1)
                    )
                    .foregroundStyle(activityAccent)
                    .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))

            Button(action: endWorkout) {
                Label("End", systemImage: "stop.fill")
                    .font(.ds_labelLarge.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                            .fill(Color.red.gradient)
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.red.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        }
    }

    // MARK: - Auto-paused chip

    private var autoPausedChip: some View {
        Label("Auto-paused", systemImage: "pause.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(.ultraThickMaterial)
            )
            .overlay(
                Capsule().stroke(activityAccent.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Countdown overlay (Wave 4c)

    @ViewBuilder
    private var countdownOverlay: some View {
        if let n = session.countdownValue {
            ZStack {
                // Subtle scrim — keeps the map readable underneath.
                Color.black.opacity(0.55).ignoresSafeArea()
                Text("\(n)")
                    .font(.system(size: 220, weight: .black, design: .rounded))
                    .foregroundStyle(activityAccent)
                    .shadow(color: activityAccent.opacity(0.5), radius: 24)
                    .scaleEffect(1.0)
                    .id(n) // re-runs the transition each tick
                    .transition(.scale.combined(with: .opacity))
            }
            .animation(.easeOut(duration: 0.35), value: n)
            .contentShape(Rectangle())
            .onTapGesture { session.skipCountdown() }
        }
    }

    // MARK: - Helpers

    private var activityAccent: Color {
        // 2026-05-02 (per-user request): Walk = teal, Run = blue
        // (was mint / green). Drives the GPS-route polyline color,
        // focused-metric tile gradient, splits chip tint, countdown
        // overlay glow — the entire active-screen identity. Cycling
        // stays cyan, hike stays orange.
        switch run.activityType {
        case .walk:         return .teal
        case .run:          return .blue
        case .outdoorCycle: return .cyan
        case .hike:         return .orange
        }
    }

    private var focusedMetricValue: String {
        switch focusedMetric {
        case .pace:
            // Imperial-default for now. Unit-pref toggle ships in Wave 3b
            // (first-cardio mini-onboarding). We'll read from
            // UserDefaults once it lands.
            return run.formattedCurrentPacePerMile
        case .speed:
            let mph = run.currentSpeed * 2.23694
            return String(format: "%.1f mph", mph)
        case .heartRate:
            // No live HR wired in Phase 1 (Watch lands in Wave 6). Show
            // dash so the slot exists for users who tap-cycle to it.
            return "—"
        }
    }

    private func cycleFocusedMetric() {
        let all = FocusedMetric.allCases
        if let idx = all.firstIndex(of: focusedMetric) {
            focusedMetric = all[(idx + 1) % all.count]
        }
    }

    private func togglePause() {
        HapticManager.impact(.medium)
        if run.isPaused {
            session.resume()
        } else {
            session.pause()
        }
    }

    private func endWorkout() {
        HapticManager.notification(.warning)
        session.end()
    }

    /// Top-left chevron action — hide the active cover AND land the user
    /// on the Home tab (Dashboard) without ending the workout. The user
    /// comes back via the (red) Workout tab.
    private func minimize() {
        session.minimize()
        // Land on Home so the chevron always means "back to the app",
        // not "stay where you were". `shouldClearWorkoutTabNav` also
        // pops the Workout-tab nav stack so a stale Cardio Landing /
        // Goal Setup view doesn't sit underneath the (red) tab.
        WorkoutManager.shared.shouldClearWorkoutTabNav = true
        WorkoutManager.shared.shouldNavigateToHomeTabInstant = true
    }

    // MARK: - Camera offset (Strava-style "user dot high")

    /// Recompute the `MapCamera` so the user-location dot sits in the
    /// upper third of the visible map (above the bottom frosted stack)
    /// using a MOTION-DERIVED heading (computed from the GPS polyline,
    /// not the magnetometer) so the map only rotates when the user
    /// actually changes direction. No-ops until we have a valid GPS
    /// fix — until then the `.userLocation(...)` fallback is doing the
    /// right thing.
    private func updateCameraIfReady() {
        guard let loc = run.currentLocation else { return }
        let heading = motionHeading
        let centerCoord = coordinateBehind(
            from: loc,
            headingDegrees: heading,
            meters: cameraOffsetMeters
        )
        let camera = MapCamera(
            centerCoordinate: centerCoord,
            distance: userCameraDistance,
            heading: heading,
            pitch: 0
        )
        // Skip the SwiftUI `withAnimation` here — MapKit interpolates
        // camera changes internally with a smoother curve than
        // `.easeOut`, and stacking the two produces visible jitter on
        // every GPS sample.
        cameraPosition = .camera(camera)
    }

    /// Heading derived from the GPS polyline rather than the
    /// magnetometer — looks back ≥25m along the route for a stable
    /// anchor and computes the great-circle bearing from there to the
    /// current location. Result: the map's "up" tracks ACTUAL
    /// direction of motion, not which way the phone happens to be
    /// pointing in the user's hand. Falls back to the magnetometer
    /// during the first few seconds of a session before 25m of route
    /// has accumulated (so we still face roughly the right way at the
    /// jump-off line).
    private var motionHeading: Double {
        guard let current = run.currentLocation else { return run.currentHeading }
        let coords = run.routeCoordinates
        guard coords.count >= 2 else { return run.currentHeading }

        let currentLoc = CLLocation(latitude: current.latitude, longitude: current.longitude)
        // Scan the polyline backwards for the first sample that's at
        // least `minAnchorMeters` away — gives a smooth bearing that
        // doesn't whip on tiny GPS jitters at the front of the route.
        let minAnchorMeters: CLLocationDistance = 25
        for coord in coords.reversed() {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if loc.distance(from: currentLoc) >= minAnchorMeters {
                return bearing(from: coord, to: current)
            }
        }
        // Polyline is too short — keep the magnetometer until we have
        // enough motion to compute a real bearing.
        return run.currentHeading
    }

    /// Great-circle bearing from `a` to `b` in degrees (0-360, 0=N,
    /// 90=E). Standard formula — accurate enough for the sub-100m
    /// segments we're working with.
    private func bearing(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let phi1 = a.latitude  * .pi / 180
        let phi2 = b.latitude  * .pi / 180
        let dLambda = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let theta = atan2(y, x)
        return (theta * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Returns a coordinate `meters` away from `coord` in the OPPOSITE
    /// of the supplied heading. In heading-up map mode this shifts the
    /// camera viewport so the user's actual location renders ABOVE
    /// screen center (Strava convention). Equirectangular approximation
    /// is plenty accurate for sub-100m offsets.
    private func coordinateBehind(
        from coord: CLLocationCoordinate2D,
        headingDegrees: Double,
        meters: Double
    ) -> CLLocationCoordinate2D {
        let oppositeHeading = (headingDegrees + 180).truncatingRemainder(dividingBy: 360)
        let radians = oppositeHeading * .pi / 180
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(coord.latitude * .pi / 180)
        let deltaLat = meters * cos(radians) / metersPerDegLat
        // Negative because positive longitude = east; sin(radians) is +
        // for east-of-north headings, so deltaLon should track that.
        let deltaLon = meters * sin(radians) / metersPerDegLon
        return CLLocationCoordinate2D(
            latitude: coord.latitude + deltaLat,
            longitude: coord.longitude + deltaLon
        )
    }

    // MARK: - GPS chip styling

    private var gpsAccuracyColor: Color {
        switch run.gpsAccuracy {
        case .acquiring: return .secondary
        case .excellent, .good: return .green
        case .fair: return .yellow
        case .weak: return .red
        }
    }

    /// Short label for the top-bar GPS pill — the full
    /// "GPS Excellent" reads heavy at this size, so we strip the
    /// "GPS " prefix and uppercase what's left ("EXCELLENT").
    private var gpsShortLabel: String {
        switch run.gpsAccuracy {
        case .acquiring: return "ACQUIRING…"
        case .excellent: return "GPS HIGH"
        case .good:      return "GPS GOOD"
        case .fair:      return "GPS FAIR"
        case .weak:      return "GPS WEAK"
        }
    }

    // MARK: - Goal Progress Formatting (2026-05-02 user request)
    //
    // The user wants to see "2.30 / 3.11 mi" in real time on the active
    // screen so they always know how far they have left. Distance label
    // honors `UnitSettingsManager.shared.distanceUnit`; time / calorie
    // labels are unit-independent.

    /// "Current / target" progress string, e.g.:
    ///   • Distance (5K imperial): "2.30 / 3.11 mi"
    ///   • Distance (5K metric):   "2.5 / 5.0 km"
    ///   • Time:                   "12:34 / 30:00"
    ///   • Calories:               "187 / 350 kcal"
    private var goalProgressLabel: String {
        switch run.goalType {
        case .distance:
            switch unitSettings.distanceUnit {
            case .imperial:
                let cur = run.distance / 1609.344
                let goal = run.goalValue / 1609.344
                return String(format: "%.2f / %.2f mi", cur, goal)
            case .metric:
                let cur = run.distance / 1000.0
                let goal = run.goalValue / 1000.0
                return String(format: "%.2f / %.2f km", cur, goal)
            }
        case .time:
            return "\(formatSeconds(run.elapsedTime)) / \(formatSeconds(run.goalValue))"
        case .calories:
            return "\(Int(run.calories)) / \(Int(run.goalValue)) kcal"
        case .pace, .none:
            return ""
        }
    }

    /// Friendly label inside the celebration sheet headline. Maps round
    /// race distances to their canonical name ("5K", "10K", "Half
    /// Marathon", "Marathon") and falls back to the raw goal value
    /// otherwise. Time / calorie goals get their natural string.
    private var goalLabelForCelebration: String {
        switch run.goalType {
        case .distance:
            // Snap to canonical race distances within ±1% of the
            // metric target; otherwise show the user's preferred unit.
            let raceLabels: [(meters: Double, label: String)] = [
                (5_000,  "5K"),
                (10_000, "10K"),
                (15_000, "15K"),
                (21_097, "Half Marathon"),
                (42_195, "Marathon")
            ]
            for race in raceLabels {
                if abs(run.goalValue - race.meters) / race.meters < 0.01 {
                    return race.label
                }
            }
            switch unitSettings.distanceUnit {
            case .imperial: return String(format: "%.2f mi", run.goalValue / 1609.344)
            case .metric:   return String(format: "%.2f km", run.goalValue / 1000.0)
            }
        case .time:
            let mins = Int(run.goalValue) / 60
            let secs = Int(run.goalValue) % 60
            if mins >= 60 {
                let hrs = mins / 60
                let rem = mins % 60
                return rem > 0 ? "\(hrs)h \(rem) min" : "\(hrs) hour\(hrs == 1 ? "" : "s")"
            }
            return secs == 0 ? "\(mins)-min" : String(format: "%d:%02d", mins, secs)
        case .calories:
            return "\(Int(run.goalValue)) kcal"
        case .pace, .none:
            return ""
        }
    }

    private func formatSeconds(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - CardioGoalMetSheet
//
// Cardio Redesign — Goal-Met celebration (2026-05-02 per user request).
//
// Surfaced from `OutdoorCardioActiveView` the moment
// `RunningManager.goalReached` flips true. Two CTAs:
//   • "End workout" — primary, red gradient. Routes through the
//     normal `CardioSessionManager.end()` path → `.recap` →
//     `CardioRecapView` → Supabase RPC → unified recent log card.
//   • "Keep going"  — secondary. Closes the sheet only; the run
//     continues uninterrupted (timer, GPS, splits all keep ticking
//     because `OutdoorCardioActiveView` never paused).
//
// Stats row mirrors the recap card's hero metrics (distance / time /
// calories) so the user gets immediate validation of the milestone
// they just hit.
private struct CardioGoalMetSheet: View {
    let accent: Color
    let goalLabel: String
    let distance: String
    let time: String
    let calories: Int
    let onKeepGoing: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Trophy hero
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.30), accent.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(accent)
                    .shadow(color: accent.opacity(0.45), radius: 12)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("You hit your \(goalLabel) goal!")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Crush it. Keep moving — or save what you've got.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            statsRow

            VStack(spacing: 10) {
                Button(action: onEnd) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("End workout")
                            .fontWeight(.bold)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: Color.red.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(UniversalScaleButtonStyle(scale: .standard))

                Button(action: onKeepGoing) {
                    Text("Keep going")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(accent.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(icon: "figure.run", value: distance, label: "Distance")
            divider
            statColumn(icon: "clock.fill", value: time, label: "Time")
            divider
            statColumn(icon: "flame.fill", value: "\(calories)", label: "Calories")
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func statColumn(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(accent)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 32)
    }
}

// MARK: - CardioActiveSessionHost
//
// Phase-aware container that's presented as a fullScreenCover from the
// goal-setup view. Swaps between the active workout surface and the
// recap as `CardioSessionManager.phase` advances. Keeps the host
// fullScreenCover binding pinned for the lifetime of the session so we
// don't get a presentation-tree thrash between active → recap.
struct CardioActiveSessionHost: View {
    @Binding var isPresented: Bool
    @ObservedObject private var session = CardioSessionManager.shared

    var body: some View {
        ZStack {
            switch session.phase {
            case .preStart, .active, .paused, .ended:
                OutdoorCardioActiveView()
                    .transition(.opacity)
            case .recap:
                if let result = session.endedResult {
                    CardioRecapView(result: result) {
                        session.markSaved()
                        isPresented = false
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.onAppear { isPresented = false }
                }
            case .idle, .goalSetup, .saved:
                // Phase fell back to a non-active state (recovery
                // discarded, etc.) — bail out of the cover.
                Color.clear.onAppear { isPresented = false }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

#Preview {
    OutdoorCardioActiveView()
}
