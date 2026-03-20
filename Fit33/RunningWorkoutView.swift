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
                            .font(.ds_labelLarge)
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
                    .padding(.horizontal, Spacing.md)
                
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
                        .padding(.horizontal, Spacing.md)
                    
                    // Goal Progress (if set)
                    if runningManager.goalType != .none {
                        goalProgressStrip
                            .padding(.horizontal, Spacing.md)
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
                        .font(.ds_labelMedium)
                        .foregroundColor(color)
                }
            }
            
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
        }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                    .font(.ds_labelMedium)
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
                        .font(.ds_labelMedium)
                    
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
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                
                Text(runningManager.formattedLastSplitPace ?? "--:--")
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.white)
            }
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 16)
            
            // Best Mile
            HStack(spacing: 6) {
                Text("Best")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                
                Text(runningManager.formattedBestSplit ?? "--:--")
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(accentColor)
            }
        }
        .padding(.horizontal, Spacing.md)
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
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                selectedChartTab == tab ?
                                Capsule().fill(accentColor.opacity(0.3)) :
                                Capsule().fill(Color.clear)
                            )
                    }
                }
            }
            .padding(Spacing.xxs)
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
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
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
                        .font(.ds_bodySmall)
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
                        .font(.ds_bodySmall)
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
                    .font(.ds_caption).fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.5))
                Text(runningManager.formattedElevationGain)
                    .font(.ds_statSmall)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT")
                    .font(.ds_caption).fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.5))
                Text(String(format: "%.0f ft", runningManager.currentElevation * 3.28084))
                    .font(.ds_statSmall)
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
                    .font(.ds_bodySmall)
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
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
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
                        .font(.ds_heading3)
                        .foregroundColor(runningManager.audioCuesEnabled ? accentColor : .white.opacity(0.5))
                    
                    Text("Audio")
                        .font(.ds_caption)
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
                        .font(.ds_heading3)
                        .foregroundColor(.orange)
                    
                    Text("Lap")
                        .font(.ds_caption)
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
                        .font(.ds_heading3)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("Lock")
                        .font(.ds_caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
                    }
                    .padding(.horizontal, Spacing.lg)
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
                    .font(.ds_heading2)
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
                                .font(.ds_bodySmall).fontWeight(.medium)
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
                        .padding(.vertical, Spacing.md)
                        .background(accentGradient)
                        .cornerRadius(CornerRadius.lg)
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
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Outdoor Run")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("GPS tracking • Live pace • Route map")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 20)
                    
                    // MARK: - Open Run Section
                    openRunSection
                    
                    // MARK: - Goals & Challenges Section
                    goalsAndChallengesSection
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Open Run Section
    private var openRunSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.title3)
                    .foregroundColor(accentColor)
                Text("Open Run")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Open Run Card with GO button
            VStack(spacing: 20) {
                Text("Just run - no distance or time goal")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Big GO Button
                Button(action: {
                    HapticManager.impact(.heavy)
                    runningManager.goalType = .none
                    runningManager.startRun()
                }) {
                    ZStack {
                        Circle()
                            .fill(accentGradient)
                            .frame(width: 100, height: 100)
                            .shadow(color: accentColor.opacity(0.5), radius: 20, y: 10)
                        
                        Text("GO")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(.black)
                    }
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Goals & Challenges Section
    private var goalsAndChallengesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)
                Text("Goals & Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Distance Goals
            VStack(alignment: .leading, spacing: 12) {
                Text("DISTANCE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    RunChallengeCard(challenge: .distance1K)
                    RunChallengeCard(challenge: .distance5K)
                    RunChallengeCard(challenge: .distance10K)
                    RunChallengeCard(challenge: .halfMarathon)
                    RunChallengeCard(challenge: .marathon)
                    RunChallengeCard(challenge: .ultra50K)
                }
            }
            
            // Time Challenges
            VStack(alignment: .leading, spacing: 12) {
                Text("TIME")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    RunChallengeCard(challenge: .time15Min)
                    RunChallengeCard(challenge: .time30Min)
                    RunChallengeCard(challenge: .time45Min)
                    RunChallengeCard(challenge: .time60Min)
                    RunChallengeCard(challenge: .time90Min)
                    RunChallengeCard(challenge: .time120Min)
                }
            }
            
            // Speed Challenges
            VStack(alignment: .leading, spacing: 12) {
                Text("SPEED RECORDS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    RunChallengeCard(challenge: .fastest1K)
                    RunChallengeCard(challenge: .fastest5K)
                    RunChallengeCard(challenge: .fastest10K)
                    RunChallengeCard(challenge: .fastestMile)
                }
            }
            
            // Training Programs
            VStack(alignment: .leading, spacing: 12) {
                Text("TRAINING PROGRAMS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                    RunChallengeCard(challenge: .couch5K)
                    RunChallengeCard(challenge: .halfMarathonTraining)
                    RunChallengeCard(challenge: .marathonTraining)
                }
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
        NavigationStack {
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
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(CornerRadius.lg)
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
                    .font(.ds_bodySmall).fontWeight(.medium)
            }
            .foregroundColor(selectedGoalType == type ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
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
        NavigationStack {
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
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
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
                                        .padding(.vertical, Spacing.xs)
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
                                .padding(.vertical, Spacing.md)
                                .background(
                                    savedToHealth 
                                        ? Color.white.opacity(0.1) 
                                        : Color.red.opacity(0.8)
                                )
                                .cornerRadius(CornerRadius.lg)
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
                                .padding(.vertical, Spacing.md)
                                .background(
                                    LinearGradient(colors: [accentColor, accentColor.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(CornerRadius.lg)
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
                .font(.ds_heading3)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.white.opacity(0.05))
        .cornerRadius(CornerRadius.lg)
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

// MARK: - Run Challenge Types
enum RunChallenge: String, CaseIterable, Identifiable {
    // Distance Goals
    case distance1K = "1K"
    case distance5K = "5K"
    case distance10K = "10K"
    case halfMarathon = "Half Marathon"
    case marathon = "Marathon"
    case ultra50K = "50K Ultra"
    
    // Time Challenges
    case time15Min = "15 Minutes"
    case time30Min = "30 Minutes"
    case time45Min = "45 Minutes"
    case time60Min = "60 Minutes"
    case time90Min = "90 Minutes"
    case time120Min = "2 Hours"
    
    // Speed Records
    case fastest1K = "Fastest 1K"
    case fastest5K = "Fastest 5K"
    case fastest10K = "Fastest 10K"
    case fastestMile = "Fastest Mile"
    
    // Training Programs
    case couch5K = "Couch to 5K"
    case halfMarathonTraining = "Half Marathon Training"
    case marathonTraining = "Marathon Training"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .distance1K, .distance5K, .distance10K, .halfMarathon, .marathon, .ultra50K:
            return "figure.run"
        case .time15Min, .time30Min, .time45Min, .time60Min, .time90Min, .time120Min:
            return "clock.fill"
        case .fastest1K, .fastest5K, .fastest10K, .fastestMile:
            return "bolt.fill"
        case .couch5K, .halfMarathonTraining, .marathonTraining:
            return "calendar.badge.clock"
        }
    }
    
    var subtitle: String {
        switch self {
        case .distance1K: return "1 kilometer"
        case .distance5K: return "5 kilometers"
        case .distance10K: return "10 kilometers"
        case .halfMarathon: return "21.1 kilometers"
        case .marathon: return "42.2 kilometers"
        case .ultra50K: return "50 kilometers"
        case .time15Min: return "Run for 15 min"
        case .time30Min: return "Run for 30 min"
        case .time45Min: return "Run for 45 min"
        case .time60Min: return "Run for 1 hour"
        case .time90Min: return "Run for 1.5 hours"
        case .time120Min: return "Run for 2 hours"
        case .fastest1K: return "Beat your PR"
        case .fastest5K: return "Beat your PR"
        case .fastest10K: return "Beat your PR"
        case .fastestMile: return "Beat your PR"
        case .couch5K: return "8 week program"
        case .halfMarathonTraining: return "12 week program"
        case .marathonTraining: return "16 week program"
        }
    }
    
    var completedColor: Color {
        switch self {
        case .distance1K, .distance5K, .distance10K: return .green
        case .halfMarathon, .marathon, .ultra50K: return .orange
        case .time15Min, .time30Min, .time45Min, .time60Min, .time90Min, .time120Min: return .blue
        case .fastest1K, .fastest5K, .fastest10K, .fastestMile: return .yellow
        case .couch5K, .halfMarathonTraining, .marathonTraining: return .purple
        }
    }
    
    var targetDistance: Double? {
        switch self {
        case .distance1K: return 1000
        case .distance5K: return 5000
        case .distance10K: return 10000
        case .halfMarathon: return 21097
        case .marathon: return 42195
        case .ultra50K: return 50000
        case .fastest1K: return 1000
        case .fastest5K: return 5000
        case .fastest10K: return 10000
        case .fastestMile: return 1609
        default: return nil
        }
    }
    
    var targetTime: TimeInterval? {
        switch self {
        case .time15Min: return 15 * 60
        case .time30Min: return 30 * 60
        case .time45Min: return 45 * 60
        case .time60Min: return 60 * 60
        case .time90Min: return 90 * 60
        case .time120Min: return 120 * 60
        default: return nil
        }
    }
}

// MARK: - Run Challenge Manager
class RunChallengeManager: ObservableObject {
    static let shared = RunChallengeManager()
    
    @Published var completedChallenges: Set<String> = []
    @Published var bestTimes: [String: TimeInterval] = [:]
    
    private let completedKey = "completedRunChallenges"
    private let bestTimesKey = "bestRunTimes"
    
    init() {
        loadProgress()
    }
    
    func isCompleted(_ challenge: RunChallenge) -> Bool {
        completedChallenges.contains(challenge.rawValue)
    }
    
    func markCompleted(_ challenge: RunChallenge) {
        completedChallenges.insert(challenge.rawValue)
        saveProgress()
    }
    
    func getBestTime(for challenge: RunChallenge) -> TimeInterval? {
        bestTimes[challenge.rawValue]
    }
    
    func updateBestTime(for challenge: RunChallenge, time: TimeInterval) {
        if let existing = bestTimes[challenge.rawValue] {
            if time < existing {
                bestTimes[challenge.rawValue] = time
                saveProgress()
            }
        } else {
            bestTimes[challenge.rawValue] = time
            saveProgress()
        }
    }
    
    private func loadProgress() {
        if let saved = UserDefaults.standard.stringArray(forKey: completedKey) {
            completedChallenges = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: bestTimesKey) as? [String: TimeInterval] {
            bestTimes = saved
        }
    }
    
    private func saveProgress() {
        UserDefaults.standard.set(Array(completedChallenges), forKey: completedKey)
        UserDefaults.standard.set(bestTimes, forKey: bestTimesKey)
    }
}

// MARK: - Run Challenge Card
struct RunChallengeCard: View {
    let challenge: RunChallenge
    @StateObject private var challengeManager = RunChallengeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCompleted: Bool {
        challengeManager.isCompleted(challenge)
    }
    
    private let accentColor = Color(red: 0.2, green: 1.0, blue: 0.6)
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            // Start run with this challenge as goal
            RunningManager.shared.setGoal(for: challenge)
            RunningManager.shared.startRun()
        }) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isCompleted ? challenge.completedColor.opacity(0.2) : Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: challenge.icon)
                        .font(.ds_heading3)
                        .foregroundColor(isCompleted ? challenge.completedColor : .white.opacity(0.4))
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.rawValue)
                        .font(.ds_labelLarge)
                        .foregroundColor(isCompleted ? .white : .white.opacity(0.5))
                    
                    Text(challenge.subtitle)
                        .font(.caption)
                        .foregroundColor(isCompleted ? .white.opacity(0.6) : .white.opacity(0.3))
                }
                
                Spacer()
                
                // Completed badge or chevron
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(challenge.completedColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isCompleted 
                        ? challenge.completedColor.opacity(0.15)
                        : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isCompleted 
                                ? challenge.completedColor.opacity(0.3) 
                                : Color.white.opacity(0.1), 
                                lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isCompleted ? 1.0 : 0.7)
    }
}

// MARK: - RunningManager Extension for Challenges
extension RunningManager {
    func setGoal(for challenge: RunChallenge) {
        if let distance = challenge.targetDistance {
            goalType = .distance
            goalValue = distance
        } else if let time = challenge.targetTime {
            goalType = .time
            goalValue = time
        }
    }
}

#Preview {
    RunningWorkoutView()
}
