import SwiftUI
import MapKit
import CoreLocation

// MARK: - Cardio Active Workout View
struct CardioActiveWorkoutView: View {
    let activityType: CardioActivityType
    let goalType: CardioGoalType
    let timeGoal: Int
    let distanceGoal: Double
    let calorieGoal: Int
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var locationManager = CardioLocationManager()
    @StateObject private var bluetoothManager = BluetoothFitnessManager.shared
    @ObservedObject private var workoutManager = WorkoutManager.shared
    
    // Workout state
    @State private var isRunning = true
    @State private var isPaused = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var distance: Double = 0 // meters
    @State private var calories: Double = 0
    @State private var currentPace: Double = 0 // min/km
    @State private var averagePace: Double = 0
    @State private var heartRate: Int = 0
    @State private var maxHeartRate: Int = 0
    @State private var cadence: Int = 0
    @State private var power: Int = 0 // watts
    @State private var startTime: Date = Date()
    
    // UI state
    @State private var showingFinishAlert = false
    @State private var showingCompletionView = false
    @State private var timer: Timer?
    
    // Animation
    @State private var progressPulse = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background — only the gradient ignores the safe area.
                // The outer ZStack used to apply `.ignoresSafeArea()`
                // globally, which slid the controlButtons row off the
                // bottom of the screen on devices with home-indicator
                // (XR/12+/13+/14+/15+/16+) — see PP-018 / Quality §2.
                backgroundGradient

                VStack(spacing: 0) {
                    // Top bar with activity and controls
                    topBar

                    // Main content
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            // Goal Progress Ring
                            goalProgressSection

                            // Primary Stats Grid
                            primaryStatsGrid

                            // Secondary Stats (from Bluetooth if connected)
                            if bluetoothManager.connectionState == .connected {
                                bluetoothStatsSection
                            }

                            // Map for GPS activities
                            if activityType.requiresGPS {
                                mapSection
                            }

                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    // Bottom control buttons — must remain inside the safe
                    // area so they're visually + tappably reachable.
                    controlButtons
                }
            }
        }
        .onAppear {
            startWorkout()
        }
        .onDisappear {
            stopTimer()
        }
        .alert("End Workout?", isPresented: $showingFinishAlert) {
            Button("Continue", role: .cancel) { }
            Button("End", role: .destructive) {
                finishWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout?")
        }
        .fullScreenCover(isPresented: $showingCompletionView) {
            CardioCompletionView(
                activityType: activityType,
                duration: elapsedTime,
                distance: distance,
                calories: calories,
                averagePace: averagePace,
                goalType: goalType,
                goalValue: goalValueForType,
                goalAchieved: isGoalAchieved,
                heartRate: heartRate > 0 ? heartRate : nil,
                maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
                cadence: cadence > 0 ? cadence : nil,
                power: power > 0 ? power : nil,
                startTime: startTime,
                equipmentName: bluetoothManager.connectedDevice?.name,
                routeCoordinates: activityType.requiresGPS ? locationManager.routeCoordinates : nil
            )
        }
        .onChange(of: workoutManager.shouldDismissCardioFlow) { _, shouldDismiss in
            if shouldDismiss {
                showingCompletionView = false
                dismiss()
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Activity color glow
            activityType.color.opacity(0.15)
                .blur(radius: 80)
                .offset(y: -100)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            // Activity indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(isPaused ? Color.orange : Color.green)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(isPaused ? Color.orange : Color.green, lineWidth: 2)
                            .scaleEffect(progressPulse ? 1.5 : 1.0)
                            .opacity(progressPulse ? 0 : 1)
                    )
                
                Text(activityType.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1)
            }
            
            Spacer()
            
            // Timer
            Text(formatTime(elapsedTime))
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            // Bluetooth indicator
            if activityType.supportsBluetooth {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(bluetoothManager.connectionState == .connected ? .green : .gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }
    
    // MARK: - Goal Progress Section
    private var goalProgressSection: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 14)
                .frame(width: 200, height: 200)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: min(goalProgress, 1.0))
                .stroke(
                    LinearGradient(
                        colors: [activityType.color, activityType.color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: goalProgress)
            
            // Center content
            VStack(spacing: 8) {
                // Main value
                Text(mainGoalValue)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                // Goal info
                Text(goalLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                
                // Progress percentage
                if goalType != .openGoal {
                    Text("\(Int(min(goalProgress * 100, 100)))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(activityType.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(activityType.color.opacity(0.2))
                        )
                }
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Primary Stats Grid
    private var primaryStatsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            // Time
            CardioStatCard(
                icon: "clock.fill",
                value: formatTime(elapsedTime),
                label: "Time",
                color: .blue
            )
            
            // Distance
            CardioStatCard(
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                value: String(format: "%.2f", distance / 1000),
                label: "Distance (km)",
                color: .green
            )
            
            // Calories
            CardioStatCard(
                icon: "flame.fill",
                value: "\(Int(calories))",
                label: "Calories",
                color: .orange
            )
            
            // Pace
            CardioStatCard(
                icon: "speedometer",
                value: currentPace > 0 ? String(format: "%.1f", currentPace) : "--",
                label: "Pace (min/km)",
                color: .purple
            )
        }
    }
    
    // MARK: - Bluetooth Stats Section
    private var bluetoothStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.cyan)
                Text("EQUIPMENT DATA")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                let data = bluetoothManager.liveData
                
                if data.heartRate > 0 {
                    MiniStatCard(icon: "heart.fill", value: "\(data.heartRate)", label: "BPM", color: .red)
                }
                
                if data.cadence > 0 {
                    MiniStatCard(icon: "metronome.fill", value: "\(data.cadence)", label: "RPM", color: .yellow)
                }
                
                if data.power > 0 {
                    MiniStatCard(icon: "bolt.fill", value: "\(data.power)", label: "Watts", color: .cyan)
                }
                
                if data.incline != 0 {
                    MiniStatCard(icon: "arrow.up.right", value: String(format: "%.1f", data.incline), label: "%", color: .mint)
                }
                
                if data.speed > 0 {
                    MiniStatCard(icon: "gauge.high", value: String(format: "%.1f", data.speed), label: "km/h", color: .green)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Map Section
    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.green)
                Text("ROUTE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
            }
            
            Map(coordinateRegion: $locationManager.region,
                showsUserLocation: true,
                annotationItems: [MapAnnotationItem]()) { item in
                MapMarker(coordinate: item.coordinate)
            }
            .overlay(
                // Route polyline would go here
                RouteOverlayView(coordinates: locationManager.routeCoordinates, color: activityType.color)
            )
            .frame(height: 200)
            .cornerRadius(CornerRadius.lg)
        }
    }
    
    // MARK: - Control Buttons
    private var controlButtons: some View {
        HStack(spacing: 20) {
            // Pause/Resume Button
            Button(action: {
                HapticManager.impact(.medium)
                togglePause()
            }) {
                ZStack {
                    Circle()
                        .fill(isPaused ? Color.green : Color.orange)
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.white)
                }
            }
            
            // Finish Button
            Button(action: {
                HapticManager.impact(.heavy)
                showingFinishAlert = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "stop.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Computed Properties
    private var goalProgress: CGFloat {
        switch goalType {
        case .openGoal:
            return min(CGFloat(elapsedTime / 3600), 1.0) // Progress based on 1 hour
        case .time:
            return CGFloat(elapsedTime / Double(timeGoal * 60))
        case .distance:
            return CGFloat((distance / 1000) / distanceGoal)
        case .calories:
            return CGFloat(calories / Double(calorieGoal))
        }
    }
    
    private var mainGoalValue: String {
        switch goalType {
        case .openGoal:
            return formatTime(elapsedTime)
        case .time:
            let remaining = max(0, Double(timeGoal * 60) - elapsedTime)
            return formatTimeShort(remaining)
        case .distance:
            let remaining = max(0, distanceGoal - (distance / 1000))
            return String(format: "%.2f", remaining)
        case .calories:
            let remaining = max(0, Double(calorieGoal) - calories)
            return "\(Int(remaining))"
        }
    }
    
    private var goalLabel: String {
        switch goalType {
        case .openGoal:
            return "ELAPSED"
        case .time:
            return "REMAINING"
        case .distance:
            return "km LEFT"
        case .calories:
            return "cal LEFT"
        }
    }
    
    private var isGoalAchieved: Bool {
        goalProgress >= 1.0
    }
    
    private var goalValueForType: Double? {
        switch goalType {
        case .openGoal:
            return nil
        case .time:
            return Double(timeGoal) // minutes
        case .distance:
            return distanceGoal // km
        case .calories:
            return Double(calorieGoal) // calories
        }
    }
    
    // MARK: - Helper Functions
    private func startWorkout() {
        isRunning = true
        isPaused = false
        startTime = Date()
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if !isPaused {
                elapsedTime += 1
                updateStats()
            }
        }
        
        // Start location tracking for GPS activities
        if activityType.requiresGPS {
            locationManager.startTracking()
        }
        
        // Start pulse animation
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            progressPulse = true
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        
        if activityType.requiresGPS {
            locationManager.stopTracking()
        }
    }
    
    private func togglePause() {
        isPaused.toggle()
        
        if isPaused {
            locationManager.stopTracking()
        } else if activityType.requiresGPS {
            locationManager.startTracking()
        }
    }
    
    private func updateStats() {
        // Update distance from location manager or bluetooth
        if activityType.requiresGPS {
            distance = locationManager.totalDistance
            if elapsedTime > 0 && distance > 0 {
                currentPace = (elapsedTime / 60) / (distance / 1000) // min/km
                averagePace = currentPace
            }
        } else {
            let btData = bluetoothManager.liveData
            if btData.distance > 0 {
                distance = btData.distance
            }
            if btData.speed > 0 {
                currentPace = 60 / btData.speed // Convert km/h to min/km
            }
        }
        
        // Estimate calories (simplified - can be made more accurate)
        let met = getMETValue()
        let weightKg: Double = 70 // Default, could use user's actual weight
        let hours = elapsedTime / 3600
        calories = met * weightKg * hours
        
        // Update from bluetooth if connected
        let btData = bluetoothManager.liveData
        if btData.calories > 0 {
            calories = Double(btData.calories)
        }
        heartRate = btData.heartRate
        if btData.heartRate > maxHeartRate {
            maxHeartRate = btData.heartRate
        }
        cadence = btData.cadence
        power = btData.power
        
        // Check if goal achieved
        if isGoalAchieved && goalType != .openGoal {
            HapticManager.notification(.success)
        }
    }
    
    private func getMETValue() -> Double {
        // MET values for different activities
        switch activityType {
        case .outdoorRun: return 9.8
        case .treadmill: return 9.0
        case .walk: return 3.5
        case .indoorCycle: return 7.0
        case .outdoorCycle: return 8.0
        case .rowing: return 7.0
        case .elliptical: return 5.0
        case .stairClimber: return 9.0
        case .hiit: return 12.0
        case .swimming: return 8.0
        }
    }
    
    private func finishWorkout() {
        stopTimer()
        showingCompletionView = true
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private func formatTimeShort(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Cardio Stat Card
struct CardioStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.ds_bodySmall)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Mini Stat Card
struct MiniStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Map Annotation Item
struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Route Overlay View (placeholder for map polyline)
struct RouteOverlayView: View {
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    
    var body: some View {
        // This would be a proper MapKit overlay in production
        EmptyView()
    }
}

// MARK: - Cardio Location Manager
class CardioLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var totalDistance: Double = 0
    
    private var lastLocation: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        manager.startUpdatingLocation()
    }
    
    func stopTracking() {
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update region
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        
        // Add to route
        routeCoordinates.append(location.coordinate)
        
        // Calculate distance
        if let last = lastLocation {
            totalDistance += location.distance(from: last)
        }
        lastLocation = location
    }
}

// MARK: - Cardio Completion View
struct CardioCompletionView: View {
    let activityType: CardioActivityType
    let duration: TimeInterval
    let distance: Double
    let calories: Double
    let averagePace: Double
    let goalType: CardioGoalType
    let goalValue: Double?
    let goalAchieved: Bool
    let heartRate: Int?
    let maxHeartRate: Int?
    let cadence: Int?
    let power: Int?
    let startTime: Date
    let equipmentName: String?
    let routeCoordinates: [CLLocationCoordinate2D]?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSaving = true
    @State private var savedSuccessfully = false
    @State private var newPRs: [String] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [activityType.color.opacity(0.3), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Achievement badge
                        achievementBadge
                        
                        // New PRs if any
                        if !newPRs.isEmpty {
                            prBadges
                        }
                        
                        // Stats summary
                        statsSummary
                        
                        // Additional stats (heart rate, power, etc.)
                        if heartRate != nil || power != nil || cadence != nil {
                            additionalStats
                        }
                        
                        // Save status
                        if isSaving {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Saving workout...")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else if savedSuccessfully {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Workout saved")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            // Save failed → queued on CloudSyncRetryQueue,
                            // which completes the XP/quest fanout after the
                            // first successful retry. Previously this state
                            // rendered NOTHING (2026-07-31 P0 fix).
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Saved offline — will sync automatically")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Workout saved offline, it will sync automatically")
                        }
                        
                        // Done button
                        Button(action: {
                            // Dismiss entire cardio flow and go home
                            WorkoutManager.shared.shouldDismissCardioFlow = true
                            WorkoutManager.shared.navigateToHomeTab()
                        }) {
                            Text("Done")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(activityType.color)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 60)
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await saveWorkout()
        }
    }
    
    private var achievementBadge: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(activityType.color.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                if goalAchieved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(activityType.color)
                } else {
                    Image(systemName: activityType.icon)
                        .font(.system(size: 50))
                        .foregroundColor(activityType.color)
                }
            }
            
            VStack(spacing: 4) {
                Text(goalAchieved ? "Goal Achieved!" : "Workout Complete")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(activityType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private var prBadges: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                Text("NEW PERSONAL RECORDS!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.yellow)
                    .tracking(1)
            }
            
            ForEach(newPRs, id: \.self) { pr in
                HStack {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(pr)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.2))
                )
            }
        }
        .padding(.vertical, Spacing.md)
    }
    
    private var statsSummary: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                SummaryStatBubble(
                    icon: "clock.fill",
                    value: formatDuration(duration),
                    label: "Duration",
                    color: .blue
                )
                
                SummaryStatBubble(
                    icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    value: String(format: "%.2f km", distance / 1000),
                    label: "Distance",
                    color: .green
                )
            }
            
            HStack(spacing: 16) {
                SummaryStatBubble(
                    icon: "flame.fill",
                    value: "\(Int(calories)) cal",
                    label: "Calories",
                    color: .orange
                )
                
                if averagePace > 0 {
                    SummaryStatBubble(
                        icon: "speedometer",
                        value: String(format: "%.1f min/km", averagePace),
                        label: "Avg Pace",
                        color: .purple
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var additionalStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADDITIONAL METRICS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            HStack(spacing: 16) {
                if let hr = heartRate {
                    SummaryStatBubble(
                        icon: "heart.fill",
                        value: "\(hr)",
                        label: "Avg HR",
                        color: .red
                    )
                }
                
                if let maxHR = maxHeartRate {
                    SummaryStatBubble(
                        icon: "heart.fill",
                        value: "\(maxHR)",
                        label: "Max HR",
                        color: .red.opacity(0.7)
                    )
                }
                
                if let cad = cadence {
                    SummaryStatBubble(
                        icon: "metronome.fill",
                        value: "\(cad)",
                        label: "Cadence",
                        color: .cyan
                    )
                }
                
                if let pow = power {
                    SummaryStatBubble(
                        icon: "bolt.fill",
                        value: "\(pow)W",
                        label: "Avg Power",
                        color: .yellow
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func saveWorkout() async {
        // Convert route coordinates to JSON if available
        var routeJSON: String? = nil
        if let coords = routeCoordinates, !coords.isEmpty {
            let coordsArray = coords.map { ["lat": $0.latitude, "lng": $0.longitude] }
            // `try?` does NOT catch Objective-C `NSInvalidArgumentException` thrown when
            // the payload is not a valid JSON object — guard with `isValidJSONObject` to
            // avoid SIGABRT on unexpected route data. Per QP invariant #7.
            if JSONSerialization.isValidJSONObject(coordsArray),
               let jsonData = try? JSONSerialization.data(withJSONObject: coordsArray),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                routeJSON = jsonString
            }
        }
        
        // Create workout data
        let workoutData = CardioWorkoutData(
            activityType: activityType.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
            // Canonical key per migration #184. `rawValue.lowercased()`
            // produced `'open_goal'` which fails the CHECK constraint;
            // `canonicalKey` returns `'open'` for `.openGoal`.
            goalType: goalType.canonicalKey,
            goalValue: goalValue,
            goalAchieved: goalAchieved,
            durationSeconds: Int(duration),
            distanceMeters: distance,
            caloriesBurned: calories,
            averagePace: averagePace > 0 ? averagePace : nil,
            averageHeartRate: heartRate,
            maxHeartRate: maxHeartRate,
            cadence: cadence,
            averagePower: power,
            equipmentName: equipmentName,
            equipmentType: activityType.supportsBluetooth ? activityType.rawValue.lowercased() : nil,
            routeCoordinatesJSON: routeJSON,
            startedAt: startTime,
            completedAt: Date()
        )
        
        do {
            // Save to Supabase
            let workoutId = try await SupabaseManager.shared.saveCardioWorkout(workoutData)
            
            await MainActor.run {
                savedSuccessfully = workoutId != nil
                isSaving = false
            }

            // RPC returned nil without throwing — treat like a failed save:
            // queue for retry so the fanout credit isn't silently dropped
            // (2026-07-31; the retry queue completes the fanout).
            if workoutId == nil {
                await MainActor.run {
                    CloudSyncRetryQueue.shared.enqueueCardioCloudSync(workoutData)
                }
            }

            // Sprint 2 Q2-5 — wire into gamification (XP, streak, league,
            // quests, challenges, feed, badges). Mirrors strength parity.
            if let id = workoutId {
                await MainActor.run {
                    UserManager.shared.completeCardioWorkout(
                        workoutId: id,
                        activityType: workoutData.activityType,
                        durationSeconds: workoutData.durationSeconds,
                        distanceMeters: workoutData.distanceMeters,
                        caloriesBurned: Int(workoutData.caloriesBurned),
                        averageHeartRate: workoutData.averageHeartRate,
                        savedViaRPC: true,
                        goalAchieved: workoutData.goalAchieved
                    )
                }

                // Cardio Redesign Phase 1 — fire the verify_quests RPC
                // so cardio-context daily quests flip on the widget
                // without waiting for foreground refresh.
                await DailyQuestService.shared.onCardioActivityImported(source: "fit33")
            }
            
            // Check for any new PRs achieved (these would have been saved during saveCardioWorkout)
            let prs = await SupabaseManager.shared.fetchCardioPRs(activityType: workoutData.activityType)
            let recentPRs = prs.filter { pr in
                // Check if PR was achieved today
                if let achievedDate = ISO8601DateFormatter().date(from: pr.achievedAt) {
                    return Calendar.current.isDateInToday(achievedDate)
                }
                return false
            }
            
            await MainActor.run {
                newPRs = recentPRs.map { pr in
                    formatPRDescription(pr)
                }
            }
            
            #if DEBUG
            AppLogger.info("✅ [CARDIO] Workout saved successfully", category: .workout)
            #endif
        } catch {
            #if DEBUG
            AppLogger.error("❌ [CARDIO] Failed to save workout: \(error)", category: .workout)
            #endif
            // PR-22 residual (2026-07-30): queue for offline retry so an
            // indoor session isn't silently lost to a network blip — the
            // RPC's external_id idempotency makes retries duplicate-safe.
            await MainActor.run {
                CloudSyncRetryQueue.shared.enqueueCardioCloudSync(workoutData)
                isSaving = false
                savedSuccessfully = false
            }
        }
    }
    
    private func formatPRDescription(_ pr: CardioPRDTO) -> String {
        switch pr.recordType {
        case "longest_distance":
            return "Longest Distance: \(String(format: "%.2f", pr.value / 1000)) km"
        case "longest_duration":
            let minutes = Int(pr.value) / 60
            return "Longest Workout: \(minutes) min"
        case "most_calories":
            return "Most Calories: \(Int(pr.value)) cal"
        case "fastest_pace":
            return "Fastest Pace: \(String(format: "%.1f", pr.value)) min/km"
        case "fastest_5k":
            let minutes = Int(pr.value) / 60
            let seconds = Int(pr.value) % 60
            return "Fastest 5K: \(minutes):\(String(format: "%02d", seconds))"
        case "fastest_10k":
            let minutes = Int(pr.value) / 60
            let seconds = Int(pr.value) % 60
            return "Fastest 10K: \(minutes):\(String(format: "%02d", seconds))"
        default:
            return "\(pr.recordType): \(pr.value) \(pr.unit)"
        }
    }
}

// MARK: - Summary Stat Bubble
struct SummaryStatBubble: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.ds_heading2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.white.opacity(0.1))
        )
    }
}

#Preview {
    CardioActiveWorkoutView(
        activityType: .treadmill,
        goalType: .time,
        timeGoal: 30,
        distanceGoal: 5.0,
        calorieGoal: 300
    )
    .environmentObject(UserManager.shared)
}
