import SwiftUI
import MapKit
import CoreLocation

// MARK: - OutdoorCardioActiveView
//
// Cardio Redesign Phase 1 — Wave 4b.
// New active workout screen for outdoor walk / run / cycle / hike
// sessions. Replaces the GPS half of the legacy `CardioActiveWorkoutView`
// (which kept its own duplicate `CardioLocationManager`) and the
// legacy `RunningWorkoutView` chrome — both are still wired in until
// the cleanup pass; this view is the canonical experience for new
// outdoor sessions.
//
// Layout:
//   ┌──────────────────────────────────────┐
//   │           GPS MAP (40-45%)            │
//   │      polyline + user marker          │
//   ├──────────────────────────────────────┤
//   │     FOCUSED METRIC TILE              │  big number (Pace by default)
//   │     pace: 7'42"/mi                   │
//   ├──────────────────────────────────────┤
//   │  Distance │ Time │ Calories │ HR     │  2×2 grid
//   ├──────────────────────────────────────┤
//   │  splits ──── ──── ──── ──── (scroll) │
//   ├──────────────────────────────────────┤
//   │   ⏸ Pause       ✕ End                │  control bar (sticky)
//   └──────────────────────────────────────┘
//
// Sourced state:
//   • `RunningManager.shared`  → live telemetry (distance, pace, route…)
//   • `CardioSessionManager.shared` → phase, countdown, recap routing
//
// File length budget: ≤ 300 lines per `codingrules.mdc`.
struct OutdoorCardioActiveView: View {
    @ObservedObject private var run = RunningManager.shared
    @ObservedObject private var session = CardioSessionManager.shared
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .automatic
    )
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
            VStack(spacing: 0) {
                mapSection
                    .frame(maxHeight: .infinity)
                metricsSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                splitsStrip
                controlBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }

            if run.isAutoPaused {
                autoPausedChip
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
            }

            if session.countdownValue != nil {
                countdownOverlay
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.container, edges: .top)
        .navigationBarBackButtonHidden(true)
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
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundColor(.secondary)
            Text(focusedMetricValue)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(activityAccent)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
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
                .font(.caption2)
                .fontWeight(.semibold)
                .tracking(1)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
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
        HStack(spacing: 12) {
            Button(action: togglePause) {
                Label(run.isPaused ? "Resume" : "Pause",
                      systemImage: run.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .foregroundColor(.primary)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))

            Button(action: endWorkout) {
                Label("End", systemImage: "stop.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.red.gradient)
                    )
                    .foregroundColor(.white)
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
