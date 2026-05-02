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

    @State private var cameraPosition: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .automatic
    )
    @State private var focusedMetric: FocusedMetric = .pace

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
                ProgressView(value: run.goalProgress)
                    .progressViewStyle(.linear)
                    .tint(activityAccent)
                    .frame(maxWidth: 240)
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
        switch run.activityType {
        case .walk:         return .mint
        case .run:          return .green
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
