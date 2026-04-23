import Foundation
import CoreLocation
import MapKit
import Combine
import ActivityKit

// MARK: - GPS Accuracy Level
enum GPSAccuracy: String {
    case acquiring = "Acquiring GPS..."
    case excellent = "GPS Excellent"
    case good = "GPS Good"
    case fair = "GPS Fair"
    case weak = "GPS Weak"
    
    var color: String {
        switch self {
        case .acquiring: return "gray"
        case .excellent: return "green"
        case .good: return "green"
        case .fair: return "yellow"
        case .weak: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .acquiring: return "location.slash"
        case .excellent: return "location.fill"
        case .good: return "location.fill"
        case .fair: return "location"
        case .weak: return "location.slash.fill"
        }
    }
}

// MARK: - Pace History Point (for chart)
struct PaceHistoryPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let pace: Double // seconds per km
    let distance: Double // meters at this point
}

// MARK: - Running Manager
/// Manages outdoor running workouts with GPS tracking, pace, distance, and route recording
@MainActor
class RunningManager: NSObject, ObservableObject {
    static let shared = RunningManager()
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isAutoPaused = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var distance: Double = 0 // meters
    @Published var currentPace: Double = 0 // seconds per kilometer
    @Published var averagePace: Double = 0 // seconds per kilometer
    @Published var currentSpeed: Double = 0 // meters per second
    @Published var calories: Double = 0
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var currentHeading: Double = 0 // degrees
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var splits: [RunSplit] = [] // Per-kilometer/mile splits
    @Published var gpsAccuracy: GPSAccuracy = .acquiring
    @Published var paceHistory: [PaceHistoryPoint] = [] // For pace trend chart
    @Published var isMapFollowing = true // Auto-follow user location
    @Published var elevationGain: Double = 0 // meters
    @Published var currentElevation: Double = 0 // meters
    
    // MARK: - Goal Properties
    @Published var goalType: RunGoalType = .none
    @Published var goalValue: Double = 0 // distance in meters or time in seconds
    @Published var targetPaceMin: Double = 0 // seconds per km (lower bound)
    @Published var targetPaceMax: Double = 0 // seconds per km (upper bound)
    
    // MARK: - Audio Cue Properties
    @Published var audioCuesEnabled = true
    @Published var audioCueInterval: Double = 1609.34 // Every 1 mile by default
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var lastLocation: CLLocation?
    private var lastSplitDistance: Double = 0
    private var lastSplitTime: TimeInterval = 0
    private var lastPaceRecordTime: Date?
    private var lastElevation: Double?
    private var autoPauseTimer: Timer?
    private var stationaryStartTime: Date?
    
    // MARK: - Live Activity
    private var liveActivity: Activity<RunningActivityAttributes>?
    
    // MARK: - Computed Properties
    var distanceInKilometers: Double {
        distance / 1000.0
    }
    
    var distanceInMiles: Double {
        distance / 1609.34
    }
    
    var formattedDistanceMiles: String {
        String(format: "%.2f", distanceInMiles)
    }
    
    var formattedDistance: String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.2f km", distanceInKilometers)
        }
    }
    
    var formattedPace: String {
        formatPace(averagePace)
    }
    
    var formattedCurrentPace: String {
        formatPace(currentPace)
    }
    
    /// Format pace for miles (US default)
    var formattedPacePerMile: String {
        formatPacePerMile(averagePace)
    }
    
    var formattedCurrentPacePerMile: String {
        formatPacePerMile(currentPace)
    }
    
    var formattedElapsedTime: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// Best split pace (fastest mile/km)
    var bestSplitPace: Double? {
        splits.map { $0.pace }.min()
    }
    
    var formattedBestSplit: String? {
        guard let best = bestSplitPace else { return nil }
        return formatPacePerMile(best)
    }
    
    /// Last completed split
    var lastSplit: RunSplit? {
        splits.last
    }
    
    var formattedLastSplitPace: String? {
        guard let last = lastSplit else { return nil }
        return formatPacePerMile(last.pace)
    }
    
    /// Goal progress (0.0 to 1.0)
    var goalProgress: Double {
        guard goalValue > 0 else { return 0 }
        switch goalType {
        case .distance:
            return min(distance / goalValue, 1.0)
        case .time:
            return min(elapsedTime / goalValue, 1.0)
        case .none:
            return 0
        }
    }
    
    /// Remaining goal value
    var goalRemaining: Double {
        guard goalValue > 0 else { return 0 }
        switch goalType {
        case .distance:
            return max(goalValue - distance, 0)
        case .time:
            return max(goalValue - elapsedTime, 0)
        case .none:
            return 0
        }
    }
    
    var formattedGoalRemaining: String {
        switch goalType {
        case .distance:
            let miles = goalRemaining / 1609.34
            return String(format: "%.2f mi left", miles)
        case .time:
            let minutes = Int(goalRemaining) / 60
            let seconds = Int(goalRemaining) % 60
            return String(format: "%d:%02d left", minutes, seconds)
        case .none:
            return ""
        }
    }
    
    /// Recent pace history (last 10 minutes) for chart
    var recentPaceHistory: [PaceHistoryPoint] {
        let cutoff = Date().addingTimeInterval(-600) // Last 10 minutes
        return paceHistory.filter { $0.timestamp > cutoff }
    }
    
    var formattedElevationGain: String {
        String(format: "%.0f ft", elevationGain * 3.28084) // Convert to feet
    }
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
    }

    // Q2-80 residual (Sprint 9 2026-04-28): the repeating `timer` is tied to
    // a live run UI and is invalidated on `stopRun()` / `pauseRun()`, so
    // iOS's normal background-location lifecycle keeps it honest. The only
    // remaining leak vector is the singleton being deallocated mid-run —
    // which shouldn't happen in production but is cheap to guard against.
    // `BluetoothFitnessManager` got the scan-timer fix in Sprint 7; here we
    // just clean up state if the manager is ever torn down.
    deinit {
        timer?.invalidate()
        timer = nil
        autoPauseTimer?.invalidate()
        autoPauseTimer = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5 // Update every 5 meters
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Check current status
        locationAuthStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Authorization
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    var isLocationAuthorized: Bool {
        locationAuthStatus == .authorizedWhenInUse || locationAuthStatus == .authorizedAlways
    }
    
    // MARK: - Run Control
    func startRun(goal: RunGoalType = .none, goalValue: Double = 0, targetPaceRange: (min: Double, max: Double)? = nil) {
        guard isLocationAuthorized else {
            requestLocationPermission()
            return
        }
        
        // Reset state
        elapsedTime = 0
        distance = 0
        currentPace = 0
        averagePace = 0
        currentSpeed = 0
        calories = 0
        routeCoordinates = []
        splits = []
        paceHistory = []
        lastLocation = nil
        lastSplitDistance = 0
        lastSplitTime = 0
        pausedTime = 0
        lastPaceRecordTime = nil
        lastElevation = nil
        elevationGain = 0
        currentElevation = 0
        gpsAccuracy = .acquiring
        isAutoPaused = false
        isMapFollowing = true
        
        // Set goal
        self.goalType = goal
        self.goalValue = goalValue
        if let range = targetPaceRange {
            self.targetPaceMin = range.min
            self.targetPaceMax = range.max
        } else {
            self.targetPaceMin = 0
            self.targetPaceMax = 0
        }
        
        // Start tracking
        isRunning = true
        isPaused = false
        startTime = Date()
        
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        startTimer()
        startLiveActivity()
        
        AppLogger.debug("🏃 [RUNNING] Started run tracking", category: .health)
    }
    
    func pauseRun() {
        guard isRunning && !isPaused else { return }
        
        isPaused = true
        pausedTime = elapsedTime
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        updateLiveActivity()
        
        AppLogger.debug("⏸️ [RUNNING] Paused run", category: .health)
    }
    
    func resumeRun() {
        guard isRunning && isPaused else { return }
        
        isPaused = false
        startTime = Date()
        locationManager.startUpdatingLocation()
        startTimer()
        updateLiveActivity()
        
        AppLogger.debug("▶️ [RUNNING] Resumed run", category: .health)
    }
    
    func stopRun() -> RunWorkoutResult? {
        guard isRunning else { return nil }
        
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        endLiveActivity()
        
        let result = RunWorkoutResult(
            startTime: startTime ?? Date(),
            endTime: Date(),
            duration: elapsedTime,
            distance: distance,
            averagePace: averagePace,
            calories: calories,
            routeCoordinates: routeCoordinates,
            splits: splits
        )
        
        // Reset state
        isRunning = false
        isPaused = false
        
        AppLogger.debug("🏁 [RUNNING] Finished run: \(formattedDistance) in \(formattedElapsedTime)", category: .health)
        
        return result
    }
    
    // MARK: - Timer
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }
    
    private func updateElapsedTime() {
        guard let startTime = startTime, !isPaused else { return }
        elapsedTime = pausedTime + Date().timeIntervalSince(startTime)
        
        // Update average pace
        if distance > 0 {
            averagePace = (elapsedTime / distance) * 1000 // seconds per km
        }
        
        // Estimate calories (rough calculation)
        updateCalories()
        
        // Update Live Activity every 2 seconds for battery efficiency
        if Int(elapsedTime) % 2 == 0 {
            updateLiveActivity()
        }
    }
    
    private func updateCalories() {
        // METs for running: ~10 for moderate pace
        // Calories = METs × weight(kg) × time(hours)
        let weightKg = Double(UserManager.shared.currentUser?.weightLbs ?? 160) * 0.453592
        let hours = elapsedTime / 3600
        let mets = 10.0 // Approximate for running
        calories = mets * weightKg * hours
    }
    
    // MARK: - Helpers
    private func formatPace(_ paceInSecondsPerKm: Double) -> String {
        guard paceInSecondsPerKm > 0 && paceInSecondsPerKm < 3600 else {
            return "--:--"
        }
        let minutes = Int(paceInSecondsPerKm) / 60
        let seconds = Int(paceInSecondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
    
    private func formatPacePerMile(_ paceInSecondsPerKm: Double) -> String {
        // Convert pace from /km to /mi
        let pacePerMile = paceInSecondsPerKm * 1.60934
        guard pacePerMile > 0 && pacePerMile < 3600 else {
            return "--:--"
        }
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Record pace for history chart
    private func recordPaceHistory() {
        guard currentPace > 0 && currentPace < 1800 else { return } // Valid pace under 30 min/km
        
        let now = Date()
        // Record every 10 seconds
        if lastPaceRecordTime.map({ now.timeIntervalSince($0) >= 10 }) ?? true {
            let point = PaceHistoryPoint(timestamp: now, pace: currentPace, distance: distance)
            paceHistory.append(point)
            lastPaceRecordTime = now
            
            // Keep only last 30 minutes of data
            let cutoff = now.addingTimeInterval(-1800)
            paceHistory = paceHistory.filter { $0.timestamp > cutoff }
        }
    }
    
    /// Update GPS accuracy based on horizontal accuracy
    private func updateGPSAccuracy(_ horizontalAccuracy: Double) {
        if horizontalAccuracy < 0 {
            gpsAccuracy = .acquiring
        } else if horizontalAccuracy <= 5 {
            gpsAccuracy = .excellent
        } else if horizontalAccuracy <= 10 {
            gpsAccuracy = .good
        } else if horizontalAccuracy <= 20 {
            gpsAccuracy = .fair
        } else {
            gpsAccuracy = .weak
        }
    }
    
    /// Manual lap/split
    func recordManualLap() {
        guard isRunning && distance > 0 else { return }
        
        let splitTime = elapsedTime - lastSplitTime
        let splitDistance = distance - lastSplitDistance
        
        guard splitDistance > 0 else { return }
        
        let splitPace = (splitTime / splitDistance) * 1000
        
        let split = RunSplit(
            kilometer: splits.count + 1,
            time: splitTime,
            pace: splitPace,
            isManual: true
        )
        splits.append(split)
        
        lastSplitDistance = distance
        lastSplitTime = elapsedTime
        
        HapticManager.notification(.success)
        AppLogger.debug("📍 [RUNNING] Manual lap recorded: \(formatPacePerMile(splitPace))", category: .health)
    }
    
    /// Toggle map following
    func toggleMapFollowing() {
        isMapFollowing.toggle()
    }
    
    /// Set run goal
    func setGoal(type: RunGoalType, value: Double) {
        self.goalType = type
        self.goalValue = value
    }
    
    /// Toggle audio cues
    func toggleAudioCues() {
        audioCuesEnabled.toggle()
    }
    
    /// Set audio cue interval
    func setAudioCueInterval(_ interval: Double) {
        audioCueInterval = interval
    }
    
    private func checkForSplit() {
        let kmCompleted = Int(distance / 1000)
        let lastKm = Int(lastSplitDistance / 1000)
        
        if kmCompleted > lastKm && kmCompleted > 0 {
            // New kilometer completed
            let splitTime = elapsedTime - lastSplitTime
            let splitDistance = distance - lastSplitDistance
            let splitPace = (splitTime / splitDistance) * 1000
            
            let split = RunSplit(
                kilometer: kmCompleted,
                time: splitTime,
                pace: splitPace
            )
            splits.append(split)
            
            lastSplitDistance = Double(kmCompleted) * 1000
            lastSplitTime = elapsedTime
            
            AppLogger.debug("📍 [RUNNING] Split \(kmCompleted)km: \(formatPace(splitPace))", category: .health)
        }
    }
    
    // MARK: - Live Activity Management
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            AppLogger.warning("⚠️ [RUNNING] Live Activities not enabled", category: .health)
            return
        }
        
        let attributes = RunningActivityAttributes(
            startTime: startTime ?? Date(),
            activityName: "Outdoor Run"
        )
        
        let contentState = RunningActivityAttributes.ContentState(
            elapsedTime: elapsedTime,
            distance: distanceInMiles,
            currentPace: formatPaceForLiveActivity(currentPace),
            averagePace: formatPaceForLiveActivity(averagePace),
            calories: calories,
            isPaused: isPaused
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            liveActivity = activity
            AppLogger.debug("🟢 [RUNNING] Live Activity started: \(activity.id)", category: .health)
        } catch {
            AppLogger.error("❌ [RUNNING] Failed to start Live Activity: \(error.localizedDescription)", category: .health)
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = liveActivity else { return }
        
        let contentState = RunningActivityAttributes.ContentState(
            elapsedTime: elapsedTime,
            distance: distanceInMiles,
            currentPace: formatPaceForLiveActivity(currentPace),
            averagePace: formatPaceForLiveActivity(averagePace),
            calories: calories,
            isPaused: isPaused
        )
        
        Task {
            await activity.update(.init(state: contentState, staleDate: nil))
        }
    }
    
    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        
        let finalState = RunningActivityAttributes.ContentState(
            elapsedTime: elapsedTime,
            distance: distanceInMiles,
            currentPace: formatPaceForLiveActivity(currentPace),
            averagePace: formatPaceForLiveActivity(averagePace),
            calories: calories,
            isPaused: false
        )
        
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
            AppLogger.debug("🔴 [RUNNING] Live Activity ended", category: .health)
        }
        
        liveActivity = nil
    }
    
    private func formatPaceForLiveActivity(_ paceInSecondsPerKm: Double) -> String {
        // Convert to pace per mile for US users
        let pacePerMile = paceInSecondsPerKm * 1.60934
        guard pacePerMile > 0 && pacePerMile < 3600 else {
            return "--:--"
        }
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - CLLocationManagerDelegate
extension RunningManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard isRunning && !isPaused else { return }
            
            for location in locations {
                // Update GPS accuracy
                updateGPSAccuracy(location.horizontalAccuracy)
                
                // Filter out very inaccurate readings
                guard location.horizontalAccuracy < 30 else { continue }
                
                currentLocation = location.coordinate
                routeCoordinates.append(location.coordinate)
                
                // Track elevation
                if location.verticalAccuracy >= 0 {
                    currentElevation = location.altitude
                    if let lastElev = lastElevation {
                        let elevDelta = location.altitude - lastElev
                        if elevDelta > 0 {
                            elevationGain += elevDelta
                        }
                    }
                    lastElevation = location.altitude
                }
                
                // Calculate distance
                if let last = lastLocation {
                    let delta = location.distance(from: last)
                    
                    // Filter out GPS jumps (unrealistic speeds > 50 km/h for running)
                    let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
                    if timeDelta > 0 {
                        let speed = delta / timeDelta
                        if speed < 13.9 { // ~50 km/h max
                            distance += delta
                            currentSpeed = speed
                            
                            // Current pace (smoothed)
                            if speed > 0.5 { // Moving faster than 0.5 m/s
                                currentPace = 1000 / speed // seconds per km
                            }
                            
                            // Record pace history
                            recordPaceHistory()
                            
                            checkForSplit()
                        }
                    }
                }
                
                lastLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthStatus = manager.authorizationStatus
            AppLogger.debug("📍 [RUNNING] Location auth changed: \(locationAuthStatus.rawValue)", category: .health)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLogger.error("❌ [RUNNING] Location error: \(error.localizedDescription)", category: .health)
    }
}

// MARK: - Run Goal Type
enum RunGoalType {
    case none
    case distance // in meters
    case time // in seconds
}

// MARK: - Data Models
struct RunSplit: Identifiable {
    let id = UUID()
    let kilometer: Int
    let time: TimeInterval
    let pace: Double // seconds per km
    var isManual: Bool = false
    
    var formattedPace: String {
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Format pace per mile (US default)
    var formattedPacePerMile: String {
        let pacePerMile = pace * 1.60934
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedTime: String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct RunWorkoutResult {
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let distance: Double // meters
    let averagePace: Double // seconds per km
    let calories: Double
    let routeCoordinates: [CLLocationCoordinate2D]
    let splits: [RunSplit]
    
    var distanceKm: Double { distance / 1000 }
    var distanceMiles: Double { distance / 1609.34 }
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

