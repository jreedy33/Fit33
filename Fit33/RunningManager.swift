import Foundation
import CoreLocation
import MapKit
import Combine
import ActivityKit

// MARK: - Running Manager
/// Manages outdoor running workouts with GPS tracking, pace, distance, and route recording
@MainActor
class RunningManager: NSObject, ObservableObject {
    static let shared = RunningManager()
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var distance: Double = 0 // meters
    @Published var currentPace: Double = 0 // seconds per kilometer
    @Published var averagePace: Double = 0 // seconds per kilometer
    @Published var currentSpeed: Double = 0 // meters per second
    @Published var calories: Double = 0
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var splits: [RunSplit] = [] // Per-kilometer splits
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    private var lastLocation: CLLocation?
    private var lastSplitDistance: Double = 0
    private var lastSplitTime: TimeInterval = 0
    
    // MARK: - Live Activity
    private var liveActivity: Activity<RunningActivityAttributes>?
    
    // MARK: - Computed Properties
    var distanceInKilometers: Double {
        distance / 1000.0
    }
    
    var distanceInMiles: Double {
        distance / 1609.34
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
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
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
    func startRun() {
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
        lastLocation = nil
        lastSplitDistance = 0
        lastSplitTime = 0
        pausedTime = 0
        
        // Start tracking
        isRunning = true
        isPaused = false
        startTime = Date()
        
        locationManager.startUpdatingLocation()
        startTimer()
        startLiveActivity()
        
        print("🏃 [RUNNING] Started run tracking")
    }
    
    func pauseRun() {
        guard isRunning && !isPaused else { return }
        
        isPaused = true
        pausedTime = elapsedTime
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        updateLiveActivity()
        
        print("⏸️ [RUNNING] Paused run")
    }
    
    func resumeRun() {
        guard isRunning && isPaused else { return }
        
        isPaused = false
        startTime = Date()
        locationManager.startUpdatingLocation()
        startTimer()
        updateLiveActivity()
        
        print("▶️ [RUNNING] Resumed run")
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
        
        print("🏁 [RUNNING] Finished run: \(formattedDistance) in \(formattedElapsedTime)")
        
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
            
            print("📍 [RUNNING] Split \(kmCompleted)km: \(formatPace(splitPace))")
        }
    }
    
    // MARK: - Live Activity Management
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ [RUNNING] Live Activities not enabled")
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
            print("🟢 [RUNNING] Live Activity started: \(activity.id)")
        } catch {
            print("❌ [RUNNING] Failed to start Live Activity: \(error.localizedDescription)")
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
            print("🔴 [RUNNING] Live Activity ended")
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
                // Filter out inaccurate readings
                guard location.horizontalAccuracy < 20 else { continue }
                
                currentLocation = location.coordinate
                routeCoordinates.append(location.coordinate)
                
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
                            
                            checkForSplit()
                        }
                    }
                }
                
                lastLocation = location
            }
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthStatus = manager.authorizationStatus
            print("📍 [RUNNING] Location auth changed: \(locationAuthStatus.rawValue)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [RUNNING] Location error: \(error.localizedDescription)")
    }
}

// MARK: - Data Models
struct RunSplit: Identifiable {
    let id = UUID()
    let kilometer: Int
    let time: TimeInterval
    let pace: Double // seconds per km
    
    var formattedPace: String {
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
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

