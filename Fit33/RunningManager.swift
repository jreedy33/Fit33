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

// MARK: - Cardio Activity Type
//
// Cardio Redesign Phase 1: the engine formerly known as `RunningManager` now
// powers walk + run + hike + outdoor cycle. Per-activity thresholds branch on
// this enum (MET coefficients, `distanceFilter`, GPS jump cap, auto-pause
// stationary grace). See FITNESS_EXPERT_AGENT.md §2 for the MET science.
enum CardioActivity: String, Codable, CaseIterable, Identifiable {
    case walk
    case run
    case outdoorCycle = "outdoor_cycle"
    case hike

    var id: String { rawValue }

    /// Human-facing one-word label used on tiles, hero metric headers,
    /// and Live Activity titles. Keeps support-knowledge invariant: vocab
    /// matches user phrasing ("Run" / "Walk", not "Outdoor Running Activity").
    var displayName: String {
        switch self {
        case .walk:         return "Walk"
        case .run:          return "Run"
        case .outdoorCycle: return "Cycle"
        case .hike:         return "Hike"
        }
    }

    var liveActivityName: String {
        switch self {
        case .walk:         return "Outdoor Walk"
        case .run:          return "Outdoor Run"
        case .outdoorCycle: return "Outdoor Cycle"
        case .hike:         return "Hike"
        }
    }

    /// SF Symbol used across landing tiles + active screen header.
    var icon: String {
        switch self {
        case .walk:         return "figure.walk"
        case .run:          return "figure.run"
        case .outdoorCycle: return "figure.outdoor.cycle"
        case .hike:         return "figure.hiking"
        }
    }

    /// `CLLocationManager.distanceFilter` — meters between location updates.
    /// Walking samples less aggressively (lower speed, smaller deltas matter
    /// less); cycling tolerates larger jumps. Per QP §1 (battery on long
    /// workouts).
    var distanceFilter: Double {
        switch self {
        case .walk:         return 10
        case .run:          return 5
        case .outdoorCycle: return 10
        case .hike:         return 8
        }
    }

    /// Maximum plausible speed in meters/second. GPS samples above this are
    /// rejected as jumps (tunnel exits, reflections in dense urban canyons).
    /// Walking caps at ~8 km/h (you're not race-walking 14 km/h on the
    /// commute). Cycling caps high enough for descents.
    var maxValidSpeedMps: Double {
        switch self {
        case .walk:         return 2.8   // 10 km/h
        case .run:          return 13.9  // 50 km/h (existing run cap)
        case .outdoorCycle: return 22.2  // 80 km/h (downhill MTB)
        case .hike:         return 5.0   // 18 km/h
        }
    }

    /// Auto-pause stationary grace: how long the user must be stopped
    /// (speed < 0.5 m/s) before we auto-pause the workout. Walking gets a
    /// longer grace (waiting at crosswalks is normal); running pauses
    /// faster (any stop is intentional).
    var autoPauseGraceSeconds: TimeInterval {
        switch self {
        case .walk:         return 30
        case .run:          return 15
        case .outdoorCycle: return 30
        case .hike:         return 60
        }
    }

    /// Live Activity update cadence in seconds. Walking updates less often
    /// to save battery on multi-hour outings.
    var liveActivityUpdateSeconds: Int {
        switch self {
        case .walk:         return 4
        case .run:          return 2
        case .outdoorCycle: return 3
        case .hike:         return 6
        }
    }

    /// MET coefficient at zero-pace baseline (used when pace is unknown,
    /// e.g. before the first GPS lock or in a brief paused state). Per
    /// Compendium of Physical Activities (Ainsworth 2011) — see
    /// `metForCurrentPace(_:)` for pace-aware values.
    var baseMET: Double {
        switch self {
        case .walk:         return 3.5   // Moderate walk (3.0 mph)
        case .run:          return 9.8   // 6.0 mph / 10:00 mi pace
        case .outdoorCycle: return 8.0   // Moderate cycling 12-14 mph
        case .hike:         return 6.0
        }
    }

    /// Returns the activity-appropriate MET coefficient for a given pace
    /// (in seconds per kilometer). Pace-aware MET tables are far more
    /// accurate than a flat coefficient — sub-7-min/mile running is ~3×
    /// more metabolically expensive than a stroll. See Compendium
    /// Compendium of Physical Activities (Ainsworth 2011).
    ///
    /// Returns `baseMET` if pace is unknown (0) or stationary (>30 min/km).
    func metForCurrentPace(_ paceInSecondsPerKm: Double) -> Double {
        guard paceInSecondsPerKm > 0 && paceInSecondsPerKm < 1800 else {
            return baseMET
        }
        // Convert to mph for table lookup (more familiar units, also matches
        // the published Compendium tables directly).
        let metersPerSecond = 1000.0 / paceInSecondsPerKm
        let mph = metersPerSecond * 2.23694

        switch self {
        case .walk, .hike:
            // ACSM walking metabolic equation (3.5 + 0.1 × m/min × 1):
            //   <2.0 mph → 2.0 MET (slow stroll)
            //   2.0     → 2.8
            //   3.0     → 3.5
            //   3.5     → 4.3
            //   4.0     → 5.0
            //   >4.5    → 6.3 (very brisk)
            switch mph {
            case ..<1.5:        return 2.0
            case 1.5..<2.5:     return 2.8
            case 2.5..<3.25:    return 3.5
            case 3.25..<3.75:   return 4.3
            case 3.75..<4.25:   return 5.0
            default:            return 6.3
            }
        case .run:
            // ACSM running metabolic equation simplified by mph:
            //   5.0 mph (12:00/mi) → 8.3
            //   6.0     (10:00/mi) → 9.8
            //   7.0     ( 8:34/mi) → 11.0
            //   8.0     ( 7:30/mi) → 11.8
            //   9.0     ( 6:40/mi) → 12.8
            //   10.0+              → 14.5
            switch mph {
            case ..<5.5:        return 8.3
            case 5.5..<6.5:     return 9.8
            case 6.5..<7.5:     return 11.0
            case 7.5..<8.5:     return 11.8
            case 8.5..<9.5:     return 12.8
            default:            return 14.5
            }
        case .outdoorCycle:
            // Compendium cycling outdoor:
            //   <10 mph         → 4.0 (light)
            //   10-12           → 6.8
            //   12-14           → 8.0
            //   14-16           → 10.0
            //   16-19           → 12.0
            //   >19             → 15.8 (racing)
            switch mph {
            case ..<10:         return 4.0
            case 10..<12:       return 6.8
            case 12..<14:       return 8.0
            case 14..<16:       return 10.0
            case 16..<19:       return 12.0
            default:            return 15.8
            }
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
    /// Set by the redesigned `CardioSessionManager` / Goal-Setup sheet
    /// before calling `startRun(...)`. Defaults to `.run` so existing
    /// `RunningManager.shared.startRun(...)` call sites continue to work
    /// without change. Drives MET / GPS-jump-cap / `distanceFilter` /
    /// auto-pause grace branches throughout the file.
    @Published var activityType: CardioActivity = .run
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

    /// Cardio Redesign — Goal-Met detection (2026-05-02 per user request).
    /// Flips `true` on the first frame `goalProgress >= 1.0` during an
    /// active session; reset on `startRun(...)`. The active-cardio view
    /// observes this via `.onChange` to surface the "You hit your X
    /// goal!" celebration sheet (with End / Keep-going CTAs). Stays
    /// `true` for the rest of the session even if the user keeps going
    /// past the goal — the sheet is one-shot per session.
    @Published var goalReached: Bool = false
    
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
    /// Rolling list of horizontalAccuracy values across the session — used
    /// to populate `cardio_workouts.gps_avg_accuracy_m` for the leaderboard
    /// "junk run" filter.
    private var gpsAccuracySamples: [Double] = []
    /// Timestamp of the last `updateLiveActivity` fire — coalesces updates
    /// per activityType.liveActivityUpdateSeconds. Drops Live Activity
    /// chatter on long sessions (QP §3).
    private var lastLiveActivityUpdate: Date?
    
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
        case .calories:
            return min(calories / goalValue, 1.0)
        case .pace, .none:
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
        case .calories:
            return max(goalValue - calories, 0)
        case .pace, .none:
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
        case .calories:
            return String(format: "%.0f kcal left", goalRemaining)
        case .pace, .none:
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
        // 2026-05-02 — re-attach to any live activity that survived an
        // app kill or crash. Without this, `liveActivity` stays nil for
        // the rest of the process and a later `endLiveActivity()` from
        // the recap save / discard / dismiss-to-idle path becomes a
        // no-op while iOS keeps the lock-screen widget visible until
        // its stale-after timer expires (≈4h). Attaching the surviving
        // activity here lets the next end-cleanup tear it down properly.
        reattachExistingLiveActivity()
    }

    /// If iOS still has a `RunningActivityAttributes` Live Activity for
    /// this app (because the user force-quit or the app crashed
    /// mid-session), grab a reference so subsequent `endLiveActivity()`
    /// calls can dismiss it. Best-effort — silent no-op when ActivityKit
    /// is unavailable / disabled.
    private func reattachExistingLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Newest-first — multiple activities shouldn't exist for this
        // attribute set in practice, but if they do (defensive), end
        // the older ones immediately and keep the newest reference.
        let activities = Activity<RunningActivityAttributes>.activities
        guard let newest = activities.max(by: {
            $0.attributes.startTime < $1.attributes.startTime
        }) else { return }
        liveActivity = newest
        AppLogger.debug(
            "🔁 [CARDIO] Re-attached to surviving Live Activity \(newest.id)",
            category: .health
        )
        // End any older lingering activities (shouldn't happen, but
        // ActivityKit doesn't dedupe across requests; cheap to be safe).
        for stale in activities where stale.id != newest.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Ends any in-flight Live Activity even when there's no held
    /// reference — used by the cardio recovery / discard / dismiss-to-idle
    /// paths to guarantee the lock-screen widget tears down with the
    /// session. Idempotent.
    func forceEndAnyLiveActivity() {
        // First try the normal end path (uses the held reference + final
        // content state).
        endLiveActivity()
        // Belt-and-suspenders: if anything is still in `Activity.activities`
        // (e.g. the held reference was nil because the app was just
        // launched), end them all immediately.
        let surviving = Activity<RunningActivityAttributes>.activities
        guard !surviving.isEmpty else { return }
        for activity in surviving {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        liveActivity = nil
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
        // distanceFilter defaults to .run's 5m and is overwritten in
        // applyActivityTypeSettings() at startRun() time. Walking gets 10m,
        // cycling gets 10m — keeps battery friendly on multi-hour walks.
        locationManager.distanceFilter = activityType.distanceFilter
        locationManager.activityType = .fitness
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false

        // Check current status
        locationAuthStatus = locationManager.authorizationStatus
    }

    /// Applies activity-specific tuning to the location manager. Called when
    /// `activityType` changes mid-session OR at the top of `startRun`.
    private func applyActivityTypeSettings() {
        locationManager.distanceFilter = activityType.distanceFilter
    }
    
    // MARK: - Authorization
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    var isLocationAuthorized: Bool {
        locationAuthStatus == .authorizedWhenInUse || locationAuthStatus == .authorizedAlways
    }
    
    // MARK: - Run Control
    func startRun(
        activityType: CardioActivity = .run,
        goal: RunGoalType = .none,
        goalValue: Double = 0,
        targetPaceRange: (min: Double, max: Double)? = nil
    ) {
        guard isLocationAuthorized else {
            requestLocationPermission()
            return
        }

        // Activity type FIRST so distanceFilter / MET / auto-pause grace are
        // configured before we start streaming locations.
        self.activityType = activityType
        applyActivityTypeSettings()

        // Reset state
        elapsedTime = 0
        distance = 0
        currentPace = 0
        averagePace = 0
        currentSpeed = 0
        calories = 0
        routeCoordinates = []
        gpsAccuracySamples = []
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
        stationaryStartTime = nil

        // Set goal
        self.goalType = goal
        self.goalValue = goalValue
        // Reset goal-met flag — fresh session, fresh celebration.
        self.goalReached = false
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

        AppLogger.debug("🏃 [\(activityType.rawValue.uppercased())] Started cardio tracking", category: .health)
    }
    
    func pauseRun() {
        guard isRunning && !isPaused else { return }

        // Manual user pause clears auto-pause state — once the user taps
        // pause, the auto-resume detector should not fire on its own.
        isAutoPaused = false
        isPaused = true
        pausedTime = elapsedTime
        timer?.invalidate()
        timer = nil
        // Keep location updates running so we can still detect the resume
        // gesture (motion-based) AND so the next sample timestamps line up
        // when the user manually resumes. Battery cost is negligible
        // because UI redraws are paused via the timer.
        // (Stopping startUpdatingLocation here historically caused GPS
        // drift on resume — see QP §1 / §6.)
        updateLiveActivity()

        AppLogger.debug("⏸️ [\(activityType.rawValue.uppercased())] Paused (manual)", category: .health)
    }

    func resumeRun() {
        guard isRunning && isPaused else { return }

        isPaused = false
        isAutoPaused = false
        stationaryStartTime = nil
        startTime = Date()
        startTimer()
        updateLiveActivity()

        AppLogger.debug("▶️ [\(activityType.rawValue.uppercased())] Resumed (manual)", category: .health)
    }
    
    func stopRun() -> RunWorkoutResult? {
        guard isRunning else { return nil }

        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        endLiveActivity()

        // Simplify the polyline for storage + share-card render. RDP ε=2m
        // typically cuts point count 60-80% with no perceptible visual loss.
        // The RAW polyline is kept on `RunningManager` for the live recap
        // map; the simplified version is what we ship to the server.
        let simplified = RunningManager.simplifyPolyline(routeCoordinates, epsilonMeters: 2.0)
        let goalAchieved: Bool = {
            guard goalValue > 0 else { return false }
            return goalProgress >= 1.0
        }()

        let result = RunWorkoutResult(
            startTime: startTime ?? Date(),
            endTime: Date(),
            duration: elapsedTime,
            distance: distance,
            averagePace: averagePace,
            calories: calories,
            routeCoordinates: routeCoordinates,
            simplifiedRouteCoordinates: simplified,
            splits: splits,
            activityType: activityType,
            goalType: goalType,
            goalValue: goalValue,
            goalAchieved: goalAchieved,
            averageHeartRate: nil, // populated by HK observer attach in Wave 2
            elevationGain: elevationGain,
            gpsAvgAccuracyMeters: averageGPSAccuracyMeters
        )

        // Reset state
        isRunning = false
        isPaused = false
        isAutoPaused = false

        AppLogger.debug(
            "🏁 [\(activityType.rawValue.uppercased())] Finished: \(formattedDistance) in \(formattedElapsedTime)",
            category: .health
        )

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

        // Estimate calories (MET-by-pace; see updateCalories docstring)
        updateCalories()

        // Goal-met edge detection — covers time + calorie goals (which
        // tick on the timer). Distance goals also pass through here as a
        // safety net in case the GPS update path doesn't fire on a
        // borderline tick (e.g., user is stationary at the goal line).
        checkGoalReached()

        // Coalesce Live Activity updates per activity type (walk = 4s,
        // run = 2s, cycle = 3s, hike = 6s). Walking sessions can be 60+
        // minutes — dropping update freq saves measurable battery on
        // long outings (QP §3).
        let now = Date()
        let cadence = TimeInterval(activityType.liveActivityUpdateSeconds)
        if lastLiveActivityUpdate.map({ now.timeIntervalSince($0) >= cadence }) ?? true {
            lastLiveActivityUpdate = now
            updateLiveActivity()
        }
    }
    
    private func updateCalories() {
        // Cardio Redesign Phase 1 — MET-by-pace calorie engine.
        //
        // Previous implementation was a hardcoded `mets = 10.0` regardless
        // of activity OR pace. Walking 30 min was over-estimated by ~2.8×
        // (true MET ≈ 3.5), and slow jogs were over-estimated by ~30%.
        // FITNESS_EXPERT_AGENT.md §2 specifies the three-source calorie
        // ladder; this implementation handles the MET-fallback rung.
        // (HealthKit live energy + HR-derived Keytel paths come in
        // subsequent waves where we attach to live HKWorkoutSession.)
        //
        //   kcal = MET × weight_kg × hours
        //
        // MET is pulled from the Compendium of Physical Activities table
        // baked into `CardioActivity.metForCurrentPace(...)`. We use the
        // rolling `currentPace` (smoothed over the last sample) so the
        // estimate tracks sprint intervals and walk breaks.
        let weightKg = Double(UserManager.shared.currentUser?.weightLbs ?? 160) * 0.453592
        let hours = elapsedTime / 3600
        let mets = activityType.metForCurrentPace(currentPace)
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
        // New goal mid-session — re-arm the celebration. The active
        // view's `.onChange(of: goalReached)` ignores false→false; this
        // is mainly for the goal-setup → countdown → active path where
        // the goal is set BEFORE startRun() resets the flag explicitly.
        self.goalReached = false
    }

    /// One-shot edge detector for "user hit their goal". Called every
    /// timer tick (`updateElapsedTime`) AND on every GPS distance
    /// update so the celebration sheet fires the SAME second the user
    /// crosses 5K / 30:00 / 350 kcal. Skips:
    ///   • Goal-less / pace-only sessions (`goalValue <= 0`).
    ///   • Already-celebrated sessions (idempotent — flag stays true
    ///     for the rest of the run so the sheet doesn't reopen if the
    ///     user dismisses with "Keep going" and progress oscillates).
    private func checkGoalReached() {
        guard goalValue > 0, !goalReached else { return }
        guard goalType == .distance || goalType == .time || goalType == .calories else { return }
        if goalProgress >= 1.0 {
            goalReached = true
            // Hardware tap — same intensity we use for "workout
            // complete" elsewhere, so the sensation reads as a
            // milestone rather than a generic UI tap.
            HapticManager.notification(.success)
            AppLogger.info(
                "🎯 [\(activityType.rawValue.uppercased())] Goal reached: \(goalType.rawKey) target=\(goalValue) actual=\(formattedGoalActualValue)",
                category: .health
            )
        }
    }

    /// Human-readable "actual value" string at the moment the goal was
    /// hit — used by the AppLogger line above and by debug overlays.
    /// Kept in `RunningManager` because the formatting depends on the
    /// canonical units stored here.
    private var formattedGoalActualValue: String {
        switch goalType {
        case .distance: return String(format: "%.0fm", distance)
        case .time:     return String(format: "%.0fs", elapsedTime)
        case .calories: return String(format: "%.0fkcal", calories)
        case .pace, .none: return "n/a"
        }
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
            AppLogger.warning("⚠️ [\(activityType.rawValue.uppercased())] Live Activities not enabled", category: .health)
            return
        }

        let attributes = RunningActivityAttributes(
            startTime: startTime ?? Date(),
            activityName: activityType.liveActivityName
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
            AppLogger.debug("🟢 [\(activityType.rawValue.uppercased())] Live Activity started: \(activity.id)", category: .health)
        } catch {
            // Low Power Mode + a few other transient conditions reject Live
            // Activity start. Per QP §8 / Bug-Intel invariants, log as
            // warning so the bug-intel pipeline doesn't fingerprint this as
            // a real failure mode.
            AppLogger.warning(
                "⚠️ [\(activityType.rawValue.uppercased())] Live Activity start refused: \(error.localizedDescription)",
                category: .health
            )
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
            guard isRunning else { return }

            for location in locations {
                // GPS accuracy is recorded even when paused so the banner state
                // stays current (Quality §6: visible "GPS searching…" UI).
                updateGPSAccuracy(location.horizontalAccuracy)
                gpsAccuracySamples.append(location.horizontalAccuracy)

                // Filter inaccurate readings unconditionally.
                guard location.horizontalAccuracy < 30 else { continue }

                // While paused (manual or auto), absorb samples for the
                // auto-resume detector but don't append to the route — keeps
                // the polyline tight when the user takes a coffee break.
                if isPaused {
                    if isAutoPaused {
                        evaluateAutoResume(location: location)
                    }
                    lastLocation = location
                    continue
                }

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

                    // Filter out GPS jumps using the activity-specific cap
                    // (run = 50 km/h, walk = 10 km/h, cycle = 80 km/h).
                    let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
                    if timeDelta > 0 {
                        let speed = delta / timeDelta
                        if speed < activityType.maxValidSpeedMps {
                            distance += delta
                            currentSpeed = speed

                            // Current pace (smoothed)
                            if speed > 0.5 {
                                currentPace = 1000 / speed
                                stationaryStartTime = nil
                            } else {
                                // Stationary — start (or extend) the auto-pause
                                // grace window so a long stop pauses the run
                                // automatically (Phase 1 §13 + QP §13).
                                evaluateAutoPause(at: location.timestamp)
                            }

                            // Record pace history
                            recordPaceHistory()

                            checkForSplit()

                            // Distance-goal edge detection — fire as
                            // soon as the GPS sample crosses the goal
                            // line, not on the next 1s timer tick.
                            // Helps the "You hit your 5K!" sheet feel
                            // instantaneous when the user is mid-stride.
                            checkGoalReached()
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
        // CLError.locationUnknown is transient (we just don't have a fix
        // yet — usually clears within a few seconds). Only `denied` /
        // `network` warrant an `.error` log per QP §8 + Bug-Intel
        // invariants. Anything else surfaces as a warning so the bug-intel
        // pipeline doesn't re-fingerprint these on every tunnel.
        //
        // This delegate callback is `nonisolated` so it can't read the
        // MainActor-isolated `@Published var activityType`. The category
        // tag stays generic ("CARDIO") to avoid the actor hop just for
        // a log line.
        let nsError = error as NSError
        if let code = CLError.Code(rawValue: nsError.code) {
            switch code {
            case .denied, .network, .deferredCanceled, .deferredFailed:
                AppLogger.error(
                    "❌ [CARDIO] Location error: \(error.localizedDescription)",
                    category: .health
                )
            default:
                AppLogger.warning(
                    "⚠️ [CARDIO] Transient location error (code=\(code.rawValue)): \(error.localizedDescription)",
                    category: .health
                )
            }
        } else {
            AppLogger.warning(
                "⚠️ [CARDIO] Location error: \(error.localizedDescription)",
                category: .health
            )
        }
    }
}

// MARK: - Auto-Pause + GPS Accuracy + Polyline Simplification
extension RunningManager {

    /// Average horizontal accuracy across the session (meters). Powers the
    /// leaderboard junk-run filter (>30m avg → excluded). Public so the
    /// recap save path can attach it to `cardio_workouts.gps_avg_accuracy_m`.
    var averageGPSAccuracyMeters: Double {
        guard !gpsAccuracySamples.isEmpty else { return 0 }
        let valid = gpsAccuracySamples.filter { $0 >= 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    /// Called when the latest GPS sample shows speed < 0.5 m/s (essentially
    /// stationary). After `activityType.autoPauseGraceSeconds` of consecutive
    /// stationary samples, auto-pauses the run so paused-time doesn't
    /// poison the avg-pace stat.
    fileprivate func evaluateAutoPause(at timestamp: Date) {
        guard !isPaused else { return }
        guard isRunning else { return }

        if stationaryStartTime == nil {
            stationaryStartTime = timestamp
        }

        if let stationary = stationaryStartTime,
           timestamp.timeIntervalSince(stationary) >= activityType.autoPauseGraceSeconds {
            triggerAutoPause()
        }
    }

    /// Called while auto-paused — when the user starts moving again
    /// (speed > 0.8 m/s for one sample), auto-resume.
    fileprivate func evaluateAutoResume(location: CLLocation) {
        guard isAutoPaused else { return }
        guard let last = lastLocation else { return }
        let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
        guard timeDelta > 0 else { return }
        let speed = location.distance(from: last) / timeDelta
        if speed > 0.8 && speed < activityType.maxValidSpeedMps {
            triggerAutoResume()
        }
    }

    private func triggerAutoPause() {
        guard !isPaused else { return }
        isAutoPaused = true
        isPaused = true
        pausedTime = elapsedTime
        timer?.invalidate()
        timer = nil
        // Keep location updates streaming so we can detect resume.
        updateLiveActivity()
        AppLogger.debug("⏸️ [\(activityType.rawValue.uppercased())] Auto-paused (stationary)", category: .health)
    }

    private func triggerAutoResume() {
        guard isAutoPaused else { return }
        isAutoPaused = false
        isPaused = false
        startTime = Date()
        stationaryStartTime = nil
        startTimer()
        updateLiveActivity()
        AppLogger.debug("▶️ [\(activityType.rawValue.uppercased())] Auto-resumed (motion detected)", category: .health)
    }

    /// Ramer-Douglas-Peucker polyline simplification.
    ///
    /// On a 60-min run with 1Hz sampling we accumulate ~3,600 coordinates;
    /// rendering a polyline that long causes scroll jank on iPhone SE
    /// (measured 14-22 FPS in QP §7). The recap snapshot, the share-card
    /// renderer, and the persisted `polyline_native` column all use the
    /// simplified version. ε = 2 meters preserves visual fidelity while
    /// typically cutting point count by 60-80%.
    static func simplifyPolyline(
        _ coordinates: [CLLocationCoordinate2D],
        epsilonMeters: Double = 2.0
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2,
              let start = coordinates.first,
              let end = coordinates.last else { return coordinates }

        // Find the point with the maximum distance from the start-end line.
        var maxDistance: Double = 0
        var maxIndex: Int = 0

        for i in 1..<(coordinates.count - 1) {
            let d = perpendicularDistanceMeters(
                point: coordinates[i],
                lineStart: start,
                lineEnd: end
            )
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }

        if maxDistance > epsilonMeters {
            // Recursively simplify both halves.
            let left = simplifyPolyline(
                Array(coordinates[0...maxIndex]),
                epsilonMeters: epsilonMeters
            )
            let right = simplifyPolyline(
                Array(coordinates[maxIndex..<coordinates.count]),
                epsilonMeters: epsilonMeters
            )
            return left.dropLast() + right
        } else {
            return [start, end]
        }
    }

    private static func perpendicularDistanceMeters(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        // Approximate the distance from `point` to the great-circle segment
        // [lineStart, lineEnd]. For ε=2m / coordinates within tens of meters
        // of each other, the equirectangular approximation is plenty.
        let pLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let aLoc = CLLocation(latitude: lineStart.latitude, longitude: lineStart.longitude)
        let bLoc = CLLocation(latitude: lineEnd.latitude, longitude: lineEnd.longitude)

        let ap = pLoc.distance(from: aLoc)
        let ab = aLoc.distance(from: bLoc)
        let bp = pLoc.distance(from: bLoc)
        guard ab > 0 else { return ap }

        // Heron's formula for the triangle ABP, then h = 2·Area / AB.
        let s = (ap + ab + bp) / 2
        let underRoot = max(0, s * (s - ap) * (s - ab) * (s - bp))
        let area = sqrt(underRoot)
        return (2 * area) / ab
    }
}

// MARK: - Run Goal Type
enum RunGoalType: Equatable {
    case none
    case distance // in meters
    case time // in seconds
    case calories // kcal target — Cardio Redesign Phase 1
    case pace // target pace in sec/km

    /// Stable string key used by `cardio_workouts.goal_type` server-side
    /// (matches the widened CHECK constraint in migration #184).
    var rawKey: String {
        switch self {
        case .none:     return "open"
        case .distance: return "distance"
        case .time:     return "time"
        case .calories: return "calories"
        case .pace:     return "pace"
        }
    }
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
    /// Raw GPS coordinates as captured during the session — passed through
    /// to the recap map so the live route fidelity is preserved on the
    /// confirmation screen.
    let routeCoordinates: [CLLocationCoordinate2D]
    /// RDP-simplified polyline (ε = 2m). What gets persisted to
    /// `cardio_workouts.polyline_native` and rendered on the share-card.
    /// Typically 60-80% smaller than `routeCoordinates`.
    let simplifiedRouteCoordinates: [CLLocationCoordinate2D]
    let splits: [RunSplit]
    let activityType: CardioActivity
    let goalType: RunGoalType
    let goalValue: Double
    let goalAchieved: Bool
    /// Optional — populated when an HK observer attaches HR samples to the
    /// session. Stays `nil` for phone-only runs without a paired Watch.
    let averageHeartRate: Int?
    let elevationGain: Double // meters
    let gpsAvgAccuracyMeters: Double

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

// MARK: - OutdoorCardioManager Alias
/// Forward-compatible alias used by new (Cardio Redesign Phase 1) call
/// sites. Existing call sites continue to use `RunningManager.shared`
/// without change. Once the redesign sprint ships and we have data showing
/// the new code paths are stable, the rename will be promoted to a full
/// file-rename in a follow-up sprint (per Product Engineer §10).
typealias OutdoorCardioManager = RunningManager

