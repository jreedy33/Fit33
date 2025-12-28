import SwiftUI
import MapKit
import CoreLocation
import Combine
import Charts

// MARK: - Running Workout View
/// Premium live run screen with Strava/NRC-level features
struct RunningWorkoutView: View {
    @StateObject private var runningManager = RunningManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showStopConfirmation = false
    @State private var showCompletionSheet = false
    @State private var completedRun: RunWorkoutResult?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    // UI State
    @State private var isControlsLocked = false
    @State private var holdProgress: CGFloat = 0
    @State private var isHoldingStop = false
    @State private var selectedChartTab: ChartTabType = .pace
    @State private var showGoalSetup = false
    @State private var showMetricPicker = false
    
    // Neon accent color
    private let accentColor = Color(red: 0.2, green: 1.0, blue: 0.6)
    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 1.0, blue: 0.6), Color(red: 0.0, green: 0.9, blue: 0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack {
            if !runningManager.isLocationAuthorized {
                locationPermissionView
            } else if !runningManager.isRunning {
                preRunView
            } else {
                activeRunView
            }
        }
        .navigationBarBackButtonHidden(runningManager.isRunning)
        .toolbar {
            if !runningManager.isRunning {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .sheet(isPresented: $showCompletionSheet) {
            if let run = completedRun {
                RunCompletionView(result: run) {
                    showCompletionSheet = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showGoalSetup) {
            GoalSetupSheet(runningManager: runningManager)
                .presentationDetents([.medium])
        }
        .onReceive(runningManager.$currentLocation) { location in
            if let location = location, runningManager.isMapFollowing {
                withAnimation(.easeOut(duration: 0.3)) {
                    mapRegion.center = location
                }
            }
        }
    }
    
    // MARK: - Active Run View (The Main Event)
    private var activeRunView: some View {
        ZStack {
            // Full screen map background
            EnhancedRunningMapView(
                coordinates: runningManager.routeCoordinates,
                currentLocation: runningManager.currentLocation,
                heading: runningManager.currentHeading,
                region: $mapRegion,
                isFollowing: runningManager.isMapFollowing
            )
            .ignoresSafeArea()
            
            // Gradient overlays for readability
            VStack(spacing: 0) {
                // Top gradient (for metrics)
        LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.6), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
                .frame(height: 220)
                
                Spacer()
                
                // Bottom gradient (for controls)
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.7), Color.black.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 420)
            }
            .ignoresSafeArea()
            
            // Content overlay
            VStack(spacing: 0) {
                // Top: Hero Metrics 2x2 Grid
                heroMetricsGrid
                    .padding(.top, 60)
                    .padding(.horizontal, 16)
                
                // GPS Status + Map Controls
                mapControlsBar
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                
            Spacer()
            
                // Bottom Panel
                VStack(spacing: 12) {
                    // Last Split Pill (if available)
                    if runningManager.splits.count > 0 {
                        lastSplitPill
                    }
                    
                    // Live Chart Strip
                    liveChartStrip
                        .padding(.horizontal, 16)
                    
                    // Goal Progress (if set)
                    if runningManager.goalType != .none {
                        goalProgressStrip
                            .padding(.horizontal, 16)
                    }
                    
                    // Quick Controls Row
                    quickControlsRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    // Main Control Buttons
                    mainControlButtons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
            
            // Paused Overlay
            if runningManager.isPaused {
                pausedOverlay
            }
            
            // Lock Overlay
            if isControlsLocked {
                lockOverlay
            }
        }
    }
    
    // MARK: - Hero Metrics Grid (2x2)
    private var heroMetricsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Distance
                heroMetricCard(
                    value: runningManager.formattedDistanceMiles,
                    unit: "mi",
                    label: "DISTANCE",
                    color: accentColor
                )
                
                // Elapsed Time
                heroMetricCard(
                    value: runningManager.formattedElapsedTime,
                    unit: "",
                    label: "TIME",
                    color: .cyan
                )
            }
            
            HStack(spacing: 12) {
                // Current Pace
                heroMetricCard(
                    value: runningManager.formattedCurrentPacePerMile,
                    unit: "/mi",
                    label: "PACE",
                    color: paceColor(runningManager.currentPace)
                )
                
                // Average Pace
                heroMetricCard(
                    value: runningManager.formattedPacePerMile,
                    unit: "/mi",
                    label: "AVG PACE",
                    color: .orange
                )
            }
        }
    }
    
    private func heroMetricCard(value: String, unit: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                    .monospacedDigit()
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
        }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Map Controls Bar
    private var mapControlsBar: some View {
        HStack {
            // GPS Status
            HStack(spacing: 6) {
                Image(systemName: runningManager.gpsAccuracy.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(gpsStatusColor)
                
                Text(gpsStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(gpsStatusColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.8))
            )
            
            Spacer()
            
            // Map Follow Toggle
            Button(action: {
                HapticManager.impact(.light)
                runningManager.toggleMapFollowing()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: runningManager.isMapFollowing ? "location.fill" : "location")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Text(runningManager.isMapFollowing ? "Following" : "Free")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(runningManager.isMapFollowing ? accentColor : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.8))
                )
            }
        }
    }
    
    private var gpsStatusColor: Color {
        switch runningManager.gpsAccuracy {
        case .acquiring: return .gray
        case .excellent, .good: return accentColor
        case .fair: return .yellow
        case .weak: return .red
        }
    }
    
    private var gpsStatusText: String {
        switch runningManager.gpsAccuracy {
        case .acquiring: return "Acquiring..."
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .weak: return "Weak"
        }
    }
    
    // MARK: - Last Split Pill
    private var lastSplitPill: some View {
        HStack(spacing: 16) {
            // Last Mile
            HStack(spacing: 6) {
                Text("Last mi")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(runningManager.formattedLastSplitPace ?? "--:--")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 16)
            
            // Best Mile
            HStack(spacing: 6) {
                Text("Best")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(runningManager.formattedBestSplit ?? "--:--")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial.opacity(0.8))
                .overlay(
                    Capsule()
                        .stroke(accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Live Chart Strip
    private var liveChartStrip: some View {
        VStack(spacing: 8) {
            // Tab Selector
            HStack(spacing: 0) {
                ForEach(ChartTabType.allCases, id: \.self) { tab in
            Button(action: {
                        HapticManager.impact(.light)
                        selectedChartTab = tab
                    }) {
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(selectedChartTab == tab ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedChartTab == tab ?
                                Capsule().fill(accentColor.opacity(0.3)) :
                                Capsule().fill(Color.clear)
                            )
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial.opacity(0.5))
            )
            
            // Chart Content
            Group {
                switch selectedChartTab {
                case .pace:
                    paceChartView
                case .splits:
                    splitsBarView
                case .elevation:
                    elevationView
                }
            }
            .frame(height: 56)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial.opacity(0.6))
            )
        }
    }
    
    private var paceChartView: some View {
        Group {
            if runningManager.recentPaceHistory.count > 2 {
                Chart(runningManager.recentPaceHistory) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(accentGradient)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Pace", point.pace)
                    )
                    .foregroundStyle(
                LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            } else {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.white.opacity(0.4))
                    Text("Pace trend will appear here")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }
    
    private var splitsBarView: some View {
        Group {
            if runningManager.splits.isEmpty {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.white.opacity(0.4))
                    Text("Complete your first mile to see splits")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(runningManager.splits.suffix(8)) { split in
                        VStack(spacing: 2) {
                            // Bar
                            let normalizedHeight = normalizedSplitHeight(split.pace)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(splitColor(split.pace))
                                .frame(width: 20, height: 24 * normalizedHeight)
                            
                            // Mile number
                            Text("\(split.kilometer)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                Spacer()
                }
            }
        }
    }
    
    private var elevationView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GAIN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text(runningManager.formattedElevationGain)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text(String(format: "%.0f ft", runningManager.currentElevation * 3.28084))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
                    
                    Spacer()
                    
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 24))
                .foregroundColor(accentColor.opacity(0.5))
        }
    }
    
    // MARK: - Goal Progress Strip
    private var goalProgressStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "target")
                    .font(.system(size: 12))
                    .foregroundColor(accentColor)
                
                Text("GOAL")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                Text(runningManager.formattedGoalRemaining)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentGradient)
                        .frame(width: geo.size.width * runningManager.goalProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Controls Row
    private var quickControlsRow: some View {
        HStack(spacing: 16) {
            // Audio Cues Toggle
            Button(action: {
                HapticManager.impact(.light)
                runningManager.toggleAudioCues()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: runningManager.audioCuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(runningManager.audioCuesEnabled ? accentColor : .white.opacity(0.5))
                    
                    Text("Audio")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
                
                Spacer()
                
            // Lap Button
            Button(action: {
                HapticManager.notification(.success)
                runningManager.recordManualLap()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    
                    Text("Lap")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Lock Toggle
            Button(action: {
                HapticManager.impact(.medium)
                isControlsLocked = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("Lock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
                    }
                    .padding(.horizontal, 24)
    }
    
    // MARK: - Main Control Buttons
    private var mainControlButtons: some View {
        HStack(spacing: 24) {
            // Pause/Resume Button
                        Button(action: {
                            HapticManager.impact(.medium)
                            if runningManager.isPaused {
                                runningManager.resumeRun()
                            } else {
                                runningManager.pauseRun()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 70, height: 70)
                                    .overlay(
                                        Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                    )
                                
                                Image(systemName: runningManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
            // Hold to Stop Button
                            ZStack {
                // Background
                                Circle()
                                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.8), .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                                    )
                                    .frame(width: 80, height: 80)
                
                // Progress Ring
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                // Icon
                                Image(systemName: "stop.fill")
                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white)
                            }
            .shadow(color: .red.opacity(0.4), radius: 15, y: 5)
            .gesture(
                LongPressGesture(minimumDuration: 2.0)
                    .onChanged { _ in
                        if !isHoldingStop {
                            isHoldingStop = true
                            HapticManager.impact(.heavy)
                            startHoldAnimation()
                        }
                    }
                    .onEnded { _ in
                        endRun()
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        cancelHold()
                    }
            )
        }
    }
    
    private func startHoldAnimation() {
        withAnimation(.linear(duration: 2.0)) {
            holdProgress = 1.0
        }
    }
    
    private func cancelHold() {
        isHoldingStop = false
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }
    
    // MARK: - Paused Overlay
    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(accentGradient)
                
                Text("RUN PAUSED")
                    .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
                Text(runningManager.formattedElapsedTime)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Lock Overlay
    private var lockOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Controls Locked")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                // Swipe to unlock
                GeometryReader { geo in
                    ZStack {
                        Capsule()
                            .fill(.white.opacity(0.1))
                        
                        HStack {
                            Image(systemName: "chevron.right.2")
                                .foregroundColor(.white.opacity(0.5))
                            Text("Swipe to unlock")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .frame(width: 200, height: 50)
                .gesture(
                    DragGesture(minimumDistance: 100)
                        .onEnded { value in
                            if value.translation.width > 100 {
                                HapticManager.notification(.success)
                                withAnimation {
                                    isControlsLocked = false
                                }
                            }
                        }
                )
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Helper Functions
    private func paceColor(_ pace: Double) -> Color {
        guard pace > 0 && pace < 1800 else { return .white.opacity(0.5) }
        
        // Check if within target range
        if runningManager.targetPaceMin > 0 && runningManager.targetPaceMax > 0 {
            if pace >= runningManager.targetPaceMin && pace <= runningManager.targetPaceMax {
                return accentColor
            } else if pace < runningManager.targetPaceMin {
                return .orange // Too fast
            } else {
                return .red // Too slow
            }
        }
        
        return accentColor
    }
    
    private func splitColor(_ pace: Double) -> Color {
        guard let best = runningManager.bestSplitPace else { return accentColor }
        
        if pace == best {
            return accentColor
        } else if pace < best * 1.1 {
            return accentColor.opacity(0.7)
        } else {
            return .orange
        }
    }
    
    private func normalizedSplitHeight(_ pace: Double) -> CGFloat {
        guard let best = runningManager.bestSplitPace,
              let worst = runningManager.splits.map({ $0.pace }).max() else { return 0.5 }
        
        let range = worst - best
        guard range > 0 else { return 1.0 }
        
        let normalized = 1.0 - ((pace - best) / range)
        return CGFloat(max(0.3, min(1.0, normalized)))
    }
    
    // MARK: - Location Permission View
    private var locationPermissionView: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "location.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(accentGradient)
                
                Text("Location Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("To track your runs, we need access to your location. Your route is stored locally and you control your data.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: {
                    runningManager.requestLocationPermission()
                }) {
                    Text("Enable Location")
                        .font(.headline)
                        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accentGradient)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Pre-Run View
    private var preRunView: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "figure.run")
                        .font(.system(size: 50))
                        .foregroundStyle(accentGradient)
                }
                
        VStack(spacing: 8) {
                    Text("Outdoor Run")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("GPS tracking • Live pace • Route map")
                        .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                }
                
                // Goal Setup Button
                Button(action: { showGoalSetup = true }) {
                    HStack {
                        Image(systemName: "target")
                        Text(runningManager.goalType == .none ? "Set a goal" : "Goal set")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .stroke(accentColor.opacity(0.5), lineWidth: 1)
                    )
                }
                
                Spacer()
                
                // Start Button
                Button(action: {
                    HapticManager.impact(.heavy)
                    runningManager.startRun()
                }) {
                    ZStack {
                        Circle()
                            .fill(accentGradient)
                            .frame(width: 100, height: 100)
                            .shadow(color: accentColor.opacity(0.5), radius: 20, y: 10)
                        
                        Text("START")
                            .font(.title2)
                            .fontWeight(.heavy)
                            .foregroundColor(.black)
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.03, green: 0.08, blue: 0.06),
                Color(red: 0.02, green: 0.05, blue: 0.04),
                Color.black
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Actions
    private func endRun() {
        HapticManager.notification(.success)
        cancelHold()
        
        if let result = runningManager.stopRun() {
            completedRun = result
            showCompletionSheet = true
        }
    }
}

// MARK: - Chart Tab Type
enum ChartTabType: CaseIterable {
    case pace, splits, elevation
    
    var title: String {
        switch self {
        case .pace: return "Pace"
        case .splits: return "Splits"
        case .elevation: return "Elevation"
        }
    }
}

// MARK: - Enhanced Running Map View
struct EnhancedRunningMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let currentLocation: CLLocationCoordinate2D?
    let heading: Double
    @Binding var region: MKCoordinateRegion
    let isFollowing: Bool
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false // We'll use custom annotation
        mapView.userTrackingMode = .none
        mapView.mapType = .standard
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        
        // Dark map style
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        // Add route polyline (thicker, more vibrant)
        if coordinates.count > 1 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
            
            // Add start marker
            let startAnnotation = RunAnnotation(coordinate: coordinates.first!, type: .start)
            mapView.addAnnotation(startAnnotation)
        }
        
        // Add current position with heading
        if let current = currentLocation {
            let currentAnnotation = RunAnnotation(coordinate: current, type: .current, heading: heading)
            mapView.addAnnotation(currentAnnotation)
            
            // Update region if following
            if isFollowing {
            let region = MKCoordinateRegion(
                    center: current,
                    span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )
            mapView.setRegion(region, animated: true)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0)
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let runAnnotation = annotation as? RunAnnotation else { return nil }
            
            let identifier = runAnnotation.type.rawValue
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if view == nil {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            
            view?.annotation = annotation
            
            // Create custom annotation image
            let size: CGFloat = runAnnotation.type == .current ? 28 : 20
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            
            let image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
                
                if runAnnotation.type == .start {
                    // Green circle for start
                    UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0).setFill()
                    ctx.cgContext.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
                    UIColor.black.setFill()
                    ctx.cgContext.fillEllipse(in: rect.insetBy(dx: 6, dy: 6))
                } else {
                    // Arrow for current position
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: size/2, y: 2))
                    path.addLine(to: CGPoint(x: size - 4, y: size - 4))
                    path.addLine(to: CGPoint(x: size/2, y: size - 8))
                    path.addLine(to: CGPoint(x: 4, y: size - 4))
                    path.close()
                    
                    UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0).setFill()
                    path.fill()
                }
            }
            
            view?.image = image
            view?.centerOffset = CGPoint(x: 0, y: 0)
            
            // Rotate arrow based on heading
            if runAnnotation.type == .current {
                view?.transform = CGAffineTransform(rotationAngle: CGFloat(runAnnotation.heading * .pi / 180))
            }
            
            return view
        }
    }
}

// MARK: - Run Annotation
class RunAnnotation: NSObject, MKAnnotation {
    enum AnnotationType: String {
        case start, current
    }
    
    let coordinate: CLLocationCoordinate2D
    let type: AnnotationType
    let heading: Double
    
    init(coordinate: CLLocationCoordinate2D, type: AnnotationType, heading: Double = 0) {
        self.coordinate = coordinate
        self.type = type
        self.heading = heading
        super.init()
    }
}

// MARK: - Goal Setup Sheet
struct GoalSetupSheet: View {
    @ObservedObject var runningManager: RunningManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedGoalType: RunGoalType = .none
    @State private var distanceValue: Double = 3.0 // miles
    @State private var timeMinutes: Double = 30.0
    
    private let accentColor = Color(red: 0.2, green: 1.0, blue: 0.6)
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Goal Type Selector
                    HStack(spacing: 12) {
                        goalTypeButton(.none, title: "None", icon: "xmark.circle")
                        goalTypeButton(.distance, title: "Distance", icon: "ruler")
                        goalTypeButton(.time, title: "Time", icon: "clock")
                    }
                    .padding(.horizontal)
                    
                    // Value Picker
                    if selectedGoalType == .distance {
                        VStack(spacing: 8) {
                            Text("\(String(format: "%.1f", distanceValue)) mi")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Slider(value: $distanceValue, in: 0.5...26.2, step: 0.5)
                                .tint(accentColor)
                                .padding(.horizontal)
                        }
                    } else if selectedGoalType == .time {
                        VStack(spacing: 8) {
                            Text("\(Int(timeMinutes)) min")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Slider(value: $timeMinutes, in: 5...180, step: 5)
                                .tint(accentColor)
                                .padding(.horizontal)
                        }
                    }
                    
                    Spacer()
                    
                    // Save Button
                    Button(action: saveGoal) {
                        Text("Set Goal")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.top)
            }
            .navigationTitle("Set a Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private func goalTypeButton(_ type: RunGoalType, title: String, icon: String) -> some View {
        Button(action: { selectedGoalType = type }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(selectedGoalType == type ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedGoalType == type ? accentColor : Color.white.opacity(0.1))
            )
        }
    }
    
    private func saveGoal() {
        switch selectedGoalType {
        case .none:
            runningManager.setGoal(type: .none, value: 0)
        case .distance:
            runningManager.setGoal(type: .distance, value: distanceValue * 1609.34) // Convert miles to meters
        case .time:
            runningManager.setGoal(type: .time, value: timeMinutes * 60) // Convert to seconds
        }
        dismiss()
    }
}

// MARK: - Run Completion View
struct RunCompletionView: View {
    let result: RunWorkoutResult
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSplits = false
    @State private var isSavingToHealth = false
    @State private var savedToHealth = false
    
    private let accentColor = Color(red: 0.2, green: 1.0, blue: 0.6)
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.1, blue: 0.06), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(colors: [accentColor, accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            
                            Text("Run Complete! 🎉")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.top, 20)
                        
                        // Main Stats
                        VStack(spacing: 16) {
                            mainStat(value: String(format: "%.2f mi", result.distanceMiles), label: "Distance")
                            
                            HStack(spacing: 16) {
                                statBox(value: result.formattedDuration, label: "Duration", icon: "clock.fill", color: .cyan)
                                statBox(value: formatPace(result.averagePace), label: "Avg Pace", icon: "speedometer", color: .orange)
                            }
                            
                            HStack(spacing: 16) {
                                statBox(value: String(format: "%.0f", result.calories), label: "Calories", icon: "flame.fill", color: .red)
                                statBox(value: "\(result.splits.count)", label: "Miles", icon: "point.topleft.down.curvedto.point.bottomright.up", color: .purple)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Map Preview
                        if result.routeCoordinates.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Route")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                RoutePreviewMap(coordinates: result.routeCoordinates)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 20)
                            }
                        }
                        
                        // Splits
                        if !result.splits.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(action: { showSplits.toggle() }) {
                                    HStack {
                                        Text("Mile Splits")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                if showSplits {
                                    ForEach(result.splits) { split in
                                        HStack {
                                            Text("Mile \(split.kilometer)")
                                                .foregroundColor(.white.opacity(0.7))
                                            
                                            Spacer()
                                            
                                            Text(split.formattedPacePerMile + " /mi")
                                                .foregroundColor(accentColor)
                                                .fontWeight(.semibold)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                        
                        // Save to Apple Health
                        if HealthKitManager.shared.saveWorkoutsToHealth {
                            Button(action: saveToHealth) {
                                HStack {
                                    if isSavingToHealth {
                                        ProgressView()
                                            .tint(.white)
                                    } else if savedToHealth {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Saved to Apple Health")
                                    } else {
                                        Image(systemName: "heart.fill")
                                        Text("Save to Apple Health")
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(savedToHealth ? accentColor : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    savedToHealth 
                                        ? Color.white.opacity(0.1) 
                                        : Color.red.opacity(0.8)
                                )
                                .cornerRadius(16)
                            }
                            .disabled(isSavingToHealth || savedToHealth)
                            .padding(.horizontal, 20)
                        }
                        
                        // Done Button
                        Button(action: onDismiss) {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func mainStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }
    
    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private func formatPace(_ pace: Double) -> String {
        // Convert pace from /km to /mi
        let pacePerMile = pace * 1.60934
        guard pacePerMile > 0 && pacePerMile < 3600 else { return "--:--" }
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func saveToHealth() {
        isSavingToHealth = true
        
        Task {
            do {
                try await HealthKitManager.shared.saveRunningWorkoutToHealth(
                    startDate: result.startTime,
                    endDate: result.endTime,
                    durationSeconds: result.duration,
                    distanceMeters: result.distance,
                    caloriesBurned: result.calories
                )
                
                await MainActor.run {
                    savedToHealth = true
                    isSavingToHealth = false
                    HapticManager.notification(.success)
                }
            } catch {
                await MainActor.run {
                    isSavingToHealth = false
                    HapticManager.notification(.error)
                }
                print("❌ Failed to save running workout to Health: \(error)")
            }
        }
    }
}

// MARK: - Route Preview Map
struct RoutePreviewMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    
    private let accentUIColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0)
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = false
        
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        guard coordinates.count > 1 else { return }
        
        // Add route
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        
        // Add start/end markers
        let startAnnotation = MKPointAnnotation()
        startAnnotation.coordinate = coordinates.first!
        startAnnotation.title = "Start"
        
        let endAnnotation = MKPointAnnotation()
        endAnnotation.coordinate = coordinates.last!
        endAnnotation.title = "Finish"
        
        mapView.addAnnotations([startAnnotation, endAnnotation])
        
        // Fit to show entire route
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: false
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 1.0)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#Preview {
    RunningWorkoutView()
}
