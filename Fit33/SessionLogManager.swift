import Foundation
import SwiftUI
import UIKit
import CoreData

// MARK: - Session Log Manager
/// Comprehensive session logging for bug reports and troubleshooting
/// - Captures ALL user actions from app startup to close
/// - Logs user profile, workout data, navigation, errors, and performance
/// - Auto-deletes logs on app close unless bug reported
/// - Attaches complete logs to bug reports in Supabase
final class SessionLogManager: ObservableObject {
    static let shared = SessionLogManager()
    
    // MARK: - Properties
    @Published var sessionActive = false
    @Published var bugReportPending = false
    @Published var logCount: Int = 0
    
    private var sessionLog: [LogEntry] = []
    private var sessionStartTime: Date?
    private var sessionId: String = ""
    private let logQueue = DispatchQueue(label: "com.fit33.sessionlog", qos: .utility)
    private let maxLogEntries = 1000
    private let maxLogAge: TimeInterval = 86400 // 24 hours
    
    // User context captured at session start
    private var userContext: UserContext?
    private var userProfileSnapshot: SessionUserProfile?
    
    // Performance tracking
    private var memoryWarningCount = 0
    private var networkRequestCount = 0
    private var networkErrorCount = 0
    private var slowOperationCount = 0
    private var crashCount = 0
    private var uiLagCount = 0
    
    // Performance thresholds (in seconds)
    struct PerformanceThresholds {
        static let screenLoad: TimeInterval = 0.5       // 500ms
        static let networkRequest: TimeInterval = 3.0   // 3s
        static let videoLoad: TimeInterval = 2.0        // 2s
        static let workoutGeneration: TimeInterval = 2.0 // 2s
        static let dataFetch: TimeInterval = 1.0        // 1s
        static let uiAnimation: TimeInterval = 0.3      // 300ms
        static let buttonResponse: TimeInterval = 0.1   // 100ms
        static let critical: TimeInterval = 5.0         // 5s - CRITICAL
    }
    
    // Active timers for tracking operations
    private var activeTimers: [String: Date] = [:]
    
    // Screen tracking - MILLISECOND PRECISION
    private var currentScreenId: String = "S000"
    private var previousScreenId: String = "S000"
    private var screenHistory: [(id: String, name: String, timestamp: Date, transitionMs: Int?)] = []
    private var screenDurationHistory: [(screenId: String, screenName: String, durationMs: Int, timestamp: Date, wasFlash: Bool)] = []
    private var lastTapAction: String = ""
    private var lastTapScreenId: String = "S000"
    private var lastTapTime: Date = Date()
    private var screenAppearTime: Date = Date()
    private var transitionStartTime: Date?
    private var pendingTransitionTo: String?

    // Navigation stacks
    private var navigationStack: [String] = []
    private var modalStack: [String] = []
    private var sheetStack: [String] = []
    
    // COMPACT ACTION TIMELINE - tracks tap→screen→duration in one line
    private var actionTimeline: [ActionTimelineEntry] = []
    
    struct ActionTimelineEntry {
        let timestamp: Date
        let action: String           // "tap:Auto Workout" or "screen:S350" or "leave:S350"
        let fromId: String
        let toId: String
        let loadMs: Int?             // tap to screen appear
        let durationMs: Int?         // time on screen
        let flags: [String]          // ["🐢SLOW", "⚡FLASH", "🚨WRONG"]
    }
    
    // MARK: - 🔧 Developer Tools (DEBUG only)
    // Keeps current + 2 previous sessions for debugging
    #if DEBUG
    private static let cleanShutdownKey = "dev_clean_shutdown"
    @Published var hasCrashLog: Bool = false
    
    private var logsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // Session log files: current, previous-1, previous-2
    private var currentLogURL: URL { logsDirectory.appendingPathComponent("session_current.txt") }
    var previous1LogURL: URL { logsDirectory.appendingPathComponent("session_previous1.txt") }
    var previous2LogURL: URL { logsDirectory.appendingPathComponent("session_previous2.txt") }
    #endif
    
    // MARK: - Device Detection & Screen Dimensions
    
    enum iPhoneModel: String, CaseIterable {
        // iPhone 12 Series
        case iPhone12Mini = "iPhone 12 mini"
        case iPhone12 = "iPhone 12"
        case iPhone12Pro = "iPhone 12 Pro"
        case iPhone12ProMax = "iPhone 12 Pro Max"
        // iPhone 13 Series
        case iPhone13Mini = "iPhone 13 mini"
        case iPhone13 = "iPhone 13"
        case iPhone13Pro = "iPhone 13 Pro"
        case iPhone13ProMax = "iPhone 13 Pro Max"
        // iPhone 14 Series
        case iPhone14 = "iPhone 14"
        case iPhone14Plus = "iPhone 14 Plus"
        case iPhone14Pro = "iPhone 14 Pro"
        case iPhone14ProMax = "iPhone 14 Pro Max"
        // iPhone 15 Series
        case iPhone15 = "iPhone 15"
        case iPhone15Plus = "iPhone 15 Plus"
        case iPhone15Pro = "iPhone 15 Pro"
        case iPhone15ProMax = "iPhone 15 Pro Max"
        // iPhone 16 Series
        case iPhone16 = "iPhone 16"
        case iPhone16Plus = "iPhone 16 Plus"
        case iPhone16Pro = "iPhone 16 Pro"
        case iPhone16ProMax = "iPhone 16 Pro Max"
        // SE
        case iPhoneSE3 = "iPhone SE (3rd gen)"
        // Unknown
        case unknown = "Unknown iPhone"
        
        var screenWidth: CGFloat {
            switch self {
            case .iPhone12Mini, .iPhone13Mini: return 375
            case .iPhone12, .iPhone12Pro, .iPhone13, .iPhone13Pro, .iPhone14: return 390
            case .iPhone14Pro, .iPhone15, .iPhone15Pro, .iPhone16: return 393
            case .iPhone16Pro: return 402
            case .iPhone12ProMax, .iPhone13ProMax, .iPhone14Plus: return 428
            case .iPhone14ProMax, .iPhone15Plus, .iPhone15ProMax, .iPhone16Plus: return 430
            case .iPhone16ProMax: return 440
            case .iPhoneSE3: return 375
            case .unknown: return UIScreen.main.bounds.width
            }
        }
        
        var screenHeight: CGFloat {
            switch self {
            case .iPhone12Mini, .iPhone13Mini: return 812
            case .iPhone12, .iPhone12Pro, .iPhone13, .iPhone13Pro, .iPhone14: return 844
            case .iPhone14Pro, .iPhone15, .iPhone15Pro, .iPhone16: return 852
            case .iPhone16Pro: return 874
            case .iPhone12ProMax, .iPhone13ProMax, .iPhone14Plus: return 926
            case .iPhone14ProMax, .iPhone15Plus, .iPhone15ProMax, .iPhone16Plus: return 932
            case .iPhone16ProMax: return 956
            case .iPhoneSE3: return 667
            case .unknown: return UIScreen.main.bounds.height
            }
        }
        
        var safeAreaTop: CGFloat {
            switch self {
            case .iPhoneSE3: return 20 // No notch
            case .iPhone14Pro, .iPhone14ProMax, .iPhone15, .iPhone15Plus, .iPhone15Pro, .iPhone15ProMax,
                 .iPhone16, .iPhone16Plus, .iPhone16Pro, .iPhone16ProMax:
                return 59 // Dynamic Island
            default:
                return 47 // Notch
            }
        }
        
        var safeAreaBottom: CGFloat {
            switch self {
            case .iPhoneSE3: return 0
            default: return 34
            }
        }
        
        var tabBarHeight: CGFloat { 49 + safeAreaBottom }
    }
    
    struct DeviceInfo {
        let model: iPhoneModel
        let screenWidth: CGFloat
        let screenHeight: CGFloat
        let scale: CGFloat
        let identifier: String
        
        static var current: DeviceInfo {
            let screen = UIScreen.main.bounds
            let scale = UIScreen.main.scale
            let identifier = getDeviceIdentifier()
            let model = detectModel(from: identifier, screenSize: screen.size)
            
            return DeviceInfo(
                model: model,
                screenWidth: screen.width,
                screenHeight: screen.height,
                scale: scale,
                identifier: identifier
            )
        }
        
        private static func getDeviceIdentifier() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let identifier = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            return identifier
        }
        
        private static func detectModel(from identifier: String, screenSize: CGSize) -> iPhoneModel {
            // Device identifiers mapping
            // iPhone 12 series: iPhone13,x
            // iPhone 13 series: iPhone14,x
            // iPhone 14 series: iPhone14,x (14/14+) and iPhone15,x (14 Pro)
            // iPhone 15 series: iPhone15,x (15/15+) and iPhone16,x (15 Pro)
            // iPhone 16 series: iPhone17,x
            
            switch identifier {
            // iPhone 12 Series
            case "iPhone13,1": return .iPhone12Mini
            case "iPhone13,2": return .iPhone12
            case "iPhone13,3": return .iPhone12Pro
            case "iPhone13,4": return .iPhone12ProMax
            // iPhone 13 Series
            case "iPhone14,4": return .iPhone13Mini
            case "iPhone14,5": return .iPhone13
            case "iPhone14,2": return .iPhone13Pro
            case "iPhone14,3": return .iPhone13ProMax
            // iPhone 14 Series
            case "iPhone14,7": return .iPhone14
            case "iPhone14,8": return .iPhone14Plus
            case "iPhone15,2": return .iPhone14Pro
            case "iPhone15,3": return .iPhone14ProMax
            // iPhone 15 Series
            case "iPhone15,4": return .iPhone15
            case "iPhone15,5": return .iPhone15Plus
            case "iPhone16,1": return .iPhone15Pro
            case "iPhone16,2": return .iPhone15ProMax
            // iPhone 16 Series
            case "iPhone17,3": return .iPhone16
            case "iPhone17,4": return .iPhone16Plus
            case "iPhone17,1": return .iPhone16Pro
            case "iPhone17,2": return .iPhone16ProMax
            // iPhone SE
            case "iPhone14,6": return .iPhoneSE3
            default:
                // Fallback: detect by screen size
                return detectByScreenSize(screenSize)
            }
        }
        
        private static func detectByScreenSize(_ size: CGSize) -> iPhoneModel {
            let width = min(size.width, size.height)
            let height = max(size.width, size.height)
            
            // Match known screen dimensions
            if width == 375 && height == 812 { return .iPhone12Mini }
            if width == 390 && height == 844 { return .iPhone14 }
            if width == 393 && height == 852 { return .iPhone15Pro }
            if width == 402 && height == 874 { return .iPhone16Pro }
            if width == 428 && height == 926 { return .iPhone14Plus }
            if width == 430 && height == 932 { return .iPhone15ProMax }
            if width == 440 && height == 956 { return .iPhone16ProMax }
            if width == 375 && height == 667 { return .iPhoneSE3 }
            
            return .unknown
        }
    }
    
    // Current device info - cached
    private(set) var deviceInfo: DeviceInfo = DeviceInfo.current
    
    // MARK: - UI Element Registry (Unique IDs + Relative Positions)
    
    /// Position defined as percentage of screen (0.0 - 1.0)
    struct RelativePosition {
        let xPercent: CGFloat?  // 0.0 = left, 0.5 = center, 1.0 = right
        let yPercent: CGFloat?  // 0.0 = top, 1.0 = bottom
        let widthPercent: CGFloat?
        let heightPoints: CGFloat?  // Some heights are fixed (buttons, etc.)
        
        func absoluteX(for device: DeviceInfo) -> CGFloat? {
            guard let x = xPercent else { return nil }
            return device.screenWidth * x
        }
        
        func absoluteY(for device: DeviceInfo) -> CGFloat? {
            guard let y = yPercent else { return nil }
            return device.screenHeight * y
        }
        
        func absoluteWidth(for device: DeviceInfo) -> CGFloat? {
            guard let w = widthPercent else { return nil }
            return device.screenWidth * w
        }
    }
    
    struct UIElement {
        let id: String
        let name: String
        let screen: Screen
        let position: RelativePosition
        let tolerancePercent: CGFloat  // Acceptable deviation as % of screen width
        
        init(id: String, name: String, screen: Screen, 
             xPct: CGFloat? = nil, yPct: CGFloat? = nil, 
             widthPct: CGFloat? = nil, heightPts: CGFloat? = nil,
             tolerancePct: CGFloat = 0.05) {
            self.id = id
            self.name = name
            self.screen = screen
            self.position = RelativePosition(
                xPercent: xPct,
                yPercent: yPct,
                widthPercent: widthPct,
                heightPoints: heightPts
            )
            self.tolerancePercent = tolerancePct
        }
        
        // Get expected X for current device
        var expectedX: CGFloat? {
            position.absoluteX(for: SessionLogManager.shared.deviceInfo)
        }
        
        // Get expected Y for current device
        var expectedY: CGFloat? {
            position.absoluteY(for: SessionLogManager.shared.deviceInfo)
        }
        
        // Get expected width for current device
        var expectedWidth: CGFloat? {
            position.absoluteWidth(for: SessionLogManager.shared.deviceInfo)
        }
        
        var expectedHeight: CGFloat? {
            position.heightPoints
        }
        
        // Tolerance in points for current device
        var tolerance: CGFloat {
            SessionLogManager.shared.deviceInfo.screenWidth * tolerancePercent
        }
    }
    
    // Element tracking
    private var elementAppearTimes: [String: Date] = [:]
    private var elementPositions: [String: CGRect] = [:]
    private var goButtonShowTime: Date?
    private var goButtonHideTime: Date?
    private var goButtonVisibleDuration: TimeInterval = 0
    private var goButtonShowCount: Int = 0
    
    // ═══════════════════════════════════════════════════════════════════
    // UI ELEMENT DEFINITIONS (ID, Name, Screen, Expected X, Y, W, H)
    // Based on iPhone 15 Pro (393x852 points)
    // ═══════════════════════════════════════════════════════════════════
    
    enum Element: String, CaseIterable {
        // ─────────────────────────────────────────────────────────────
        // DASHBOARD ELEMENTS (E1XX)
        // ─────────────────────────────────────────────────────────────
        case dashboardLogo = "E100"
        case dashboardProfileButton = "E101"
        case dashboardGreeting = "E102"
        case dashboardStartWorkoutButton = "E103"
        case dashboardAutoGenButton = "E104"
        case dashboardCustomButton = "E105"
        case dashboardStepTracker = "E106"
        case dashboardRecentWorkouts = "E107"
        case dashboardProgramWidget = "E108"
        
        // ─────────────────────────────────────────────────────────────
        // GO BUTTON (E2XX) - CRITICAL TRACKING
        // ─────────────────────────────────────────────────────────────
        case goButton = "E200"
        case goButtonPulse = "E201"
        case goButtonLabel = "E202"
        
        // ─────────────────────────────────────────────────────────────
        // WORKOUT TAB ELEMENTS (E3XX)
        // ─────────────────────────────────────────────────────────────
        case workoutTimer = "E300"
        case workoutExerciseList = "E301"
        case workoutProgressBar = "E302"
        case workoutFinishButton = "E303"
        case workoutPauseButton = "E304"
        case workoutAddExerciseButton = "E305"
        
        // ─────────────────────────────────────────────────────────────
        // ACTIVE WORKOUT ELEMENTS (E4XX)
        // ─────────────────────────────────────────────────────────────
        case activeWorkoutHeader = "E400"
        case activeWorkoutTimer = "E401"
        case activeWorkoutDuration = "E402"
        case activeWorkoutExerciseCard = "E403"
        case activeWorkoutSetRow = "E404"
        case activeWorkoutWeightInput = "E405"
        case activeWorkoutRepsInput = "E406"
        case activeWorkoutCheckmark = "E407"
        case activeWorkoutSwapButton = "E408"
        case activeWorkoutFavoriteButton = "E409"
        case activeWorkoutRestTimer = "E410"
        case activeWorkoutFinishButton = "E411"
        
        // ─────────────────────────────────────────────────────────────
        // EXERCISE LIBRARY ELEMENTS (E5XX)
        // ─────────────────────────────────────────────────────────────
        case exerciseSearchBar = "E500"
        case exerciseFilterDropdown = "E501"
        case exerciseListItem = "E502"
        case exerciseDetailButton = "E503"
        case exerciseFavoriteIcon = "E504"
        
        // ─────────────────────────────────────────────────────────────
        // NAVIGATION ELEMENTS (E6XX)
        // ─────────────────────────────────────────────────────────────
        case tabBarHome = "E600"
        case tabBarExercises = "E601"
        case tabBarWorkout = "E602"
        case tabBarMeals = "E603"
        case tabBarStats = "E604"
        case backButton = "E605"
        case closeButton = "E606"
        
        // ─────────────────────────────────────────────────────────────
        // ONBOARDING ELEMENTS (E7XX)
        // ─────────────────────────────────────────────────────────────
        case onboardingContinueButton = "E700"
        case onboardingBackButton = "E701"
        case onboardingProgressBar = "E702"
        case onboardingTitle = "E703"
        case onboardingTextField = "E704"
        case onboardingSelectionCard = "E705"
        
        // ─────────────────────────────────────────────────────────────
        // AUTH ELEMENTS (E8XX)
        // ─────────────────────────────────────────────────────────────
        case authLogo = "E800"
        case authEmailField = "E801"
        case authPasswordField = "E802"
        case authConfirmPasswordField = "E803"
        case authSignInButton = "E804"
        case authSignUpToggle = "E805"
        case authAppleButton = "E806"
        case authGoogleButton = "E807"
        case authTermsCheckbox = "E808"
        
        // ═══════════════════════════════════════════════════════════════════
        // ELEMENT POSITIONS (Relative - adapts to all iPhone 12+)
        // X: 0.0 = left edge, 0.5 = center, 1.0 = right edge
        // Y: 0.0 = top (under safe area), 1.0 = bottom (above safe area)
        // ═══════════════════════════════════════════════════════════════════
        
        var info: UIElement {
            switch self {
            // ─────────────────────────────────────────────────────────────
            // GO! BUTTON - CRITICAL - center bottom
            // ─────────────────────────────────────────────────────────────
            case .goButton:
                return UIElement(id: rawValue, name: "GO! Button", screen: .goButton,
                                xPct: 0.50, yPct: 0.88,  // Center, 88% down
                                widthPct: 0.20, heightPts: 80, tolerancePct: 0.03)
            case .goButtonPulse:
                return UIElement(id: rawValue, name: "GO! Pulse Animation", screen: .goButton,
                                xPct: 0.50, yPct: 0.88,
                                widthPct: 0.25, heightPts: 100)
            case .goButtonLabel:
                return UIElement(id: rawValue, name: "GO! Label", screen: .goButton,
                                xPct: 0.50, yPct: 0.88)
                
            // ─────────────────────────────────────────────────────────────
            // DASHBOARD - Main home screen
            // ─────────────────────────────────────────────────────────────
            case .dashboardLogo:
                return UIElement(id: rawValue, name: "Fit33 Logo", screen: .dashboard,
                                xPct: 0.50, yPct: 0.07,  // Center, near top
                                widthPct: 0.30, heightPts: 40)
            case .dashboardProfileButton:
                return UIElement(id: rawValue, name: "Profile Button", screen: .dashboard,
                                xPct: 0.92, yPct: 0.07,  // Right side
                                widthPct: 0.11, heightPts: 44)
            case .dashboardGreeting:
                return UIElement(id: rawValue, name: "Greeting Text", screen: .dashboard,
                                xPct: 0.50, yPct: 0.14)
            case .dashboardStartWorkoutButton:
                return UIElement(id: rawValue, name: "Start Workout", screen: .dashboard,
                                xPct: 0.50, yPct: 0.47,
                                widthPct: 0.92, heightPts: 60)
            case .dashboardAutoGenButton:
                return UIElement(id: rawValue, name: "Auto-Gen Button", screen: .dashboard,
                                xPct: 0.30, yPct: 0.56,  // Left of center
                                widthPct: 0.43, heightPts: 100)
            case .dashboardCustomButton:
                return UIElement(id: rawValue, name: "Custom Button", screen: .dashboard,
                                xPct: 0.70, yPct: 0.56,  // Right of center
                                widthPct: 0.43, heightPts: 100)
            case .dashboardStepTracker:
                return UIElement(id: rawValue, name: "Step Tracker", screen: .dashboard,
                                xPct: 0.50, yPct: 0.68,
                                widthPct: 0.92, heightPts: 120)
            case .dashboardRecentWorkouts:
                return UIElement(id: rawValue, name: "Recent Workouts", screen: .dashboard,
                                xPct: 0.50, yPct: 0.84)
            case .dashboardProgramWidget:
                return UIElement(id: rawValue, name: "Program Widget", screen: .dashboard,
                                xPct: 0.50, yPct: 0.41,
                                widthPct: 0.92, heightPts: 100)
                
            // ─────────────────────────────────────────────────────────────
            // ACTIVE WORKOUT - During workout
            // ─────────────────────────────────────────────────────────────
            case .activeWorkoutHeader:
                return UIElement(id: rawValue, name: "Workout Header", screen: .activeWorkout,
                                xPct: 0.50, yPct: 0.07)
            case .activeWorkoutTimer:
                return UIElement(id: rawValue, name: "Workout Timer", screen: .activeWorkout,
                                xPct: 0.87, yPct: 0.07,  // Top right
                                widthPct: 0.20, heightPts: 30)
            case .activeWorkoutDuration:
                return UIElement(id: rawValue, name: "Duration Display", screen: .activeWorkout,
                                xPct: 0.87, yPct: 0.07)
            case .activeWorkoutExerciseCard:
                return UIElement(id: rawValue, name: "Exercise Card", screen: .activeWorkout,
                                xPct: 0.50, yPct: nil,
                                widthPct: 0.92, heightPts: 200)
            case .activeWorkoutSetRow:
                return UIElement(id: rawValue, name: "Set Row", screen: .activeWorkout,
                                widthPct: 0.87, heightPts: 50)
            case .activeWorkoutWeightInput:
                return UIElement(id: rawValue, name: "Weight Input", screen: .activeWorkout,
                                widthPct: 0.18, heightPts: 40)
            case .activeWorkoutRepsInput:
                return UIElement(id: rawValue, name: "Reps Input", screen: .activeWorkout,
                                widthPct: 0.18, heightPts: 40)
            case .activeWorkoutCheckmark:
                return UIElement(id: rawValue, name: "Set Checkmark", screen: .activeWorkout,
                                widthPct: 0.11, heightPts: 44)
            case .activeWorkoutSwapButton:
                return UIElement(id: rawValue, name: "Swap Exercise", screen: .activeWorkout)
            case .activeWorkoutFavoriteButton:
                return UIElement(id: rawValue, name: "Favorite Button", screen: .activeWorkout)
            case .activeWorkoutRestTimer:
                return UIElement(id: rawValue, name: "Rest Timer", screen: .restTimer,
                                xPct: 0.50, yPct: 0.50,  // Center of screen
                                widthPct: 0.51, heightPts: 200)
            case .activeWorkoutFinishButton:
                return UIElement(id: rawValue, name: "Finish Workout", screen: .activeWorkout,
                                xPct: 0.50, yPct: 0.92,
                                widthPct: 0.51, heightPts: 50)
                
            // ─────────────────────────────────────────────────────────────
            // WORKOUT TAB
            // ─────────────────────────────────────────────────────────────
            case .workoutTimer:
                return UIElement(id: rawValue, name: "Timer Display", screen: .workoutTab,
                                xPct: 0.87, yPct: 0.07,
                                widthPct: 0.20, heightPts: 30)
            case .workoutExerciseList:
                return UIElement(id: rawValue, name: "Exercise List", screen: .workoutTab,
                                xPct: 0.50, yPct: 0.47)
            case .workoutProgressBar:
                return UIElement(id: rawValue, name: "Progress Bar", screen: .workoutTab,
                                xPct: 0.50, yPct: 0.12,
                                widthPct: 0.92, heightPts: 8)
            case .workoutFinishButton:
                return UIElement(id: rawValue, name: "Finish Button", screen: .workoutTab,
                                xPct: 0.50, yPct: 0.92)
            case .workoutPauseButton:
                return UIElement(id: rawValue, name: "Pause Button", screen: .workoutTab,
                                xPct: 0.13, yPct: 0.07)
            case .workoutAddExerciseButton:
                return UIElement(id: rawValue, name: "Add Exercise", screen: .workoutTab)
                
            // ─────────────────────────────────────────────────────────────
            // EXERCISE LIBRARY
            // ─────────────────────────────────────────────────────────────
            case .exerciseSearchBar:
                return UIElement(id: rawValue, name: "Search Bar", screen: .exerciseLibrary,
                                xPct: 0.50, yPct: 0.14,
                                widthPct: 0.92, heightPts: 44)
            case .exerciseFilterDropdown:
                return UIElement(id: rawValue, name: "Filter Dropdown", screen: .exerciseLibrary,
                                xPct: 0.15, yPct: 0.20)
            case .exerciseListItem:
                return UIElement(id: rawValue, name: "Exercise Row", screen: .exerciseLibrary,
                                widthPct: 0.92, heightPts: 70)
            case .exerciseDetailButton:
                return UIElement(id: rawValue, name: "Detail Button", screen: .exerciseLibrary)
            case .exerciseFavoriteIcon:
                return UIElement(id: rawValue, name: "Favorite Icon", screen: .exerciseLibrary,
                                widthPct: 0.06, heightPts: 24)
                
            // ─────────────────────────────────────────────────────────────
            // TAB BAR - Bottom navigation (5 tabs evenly spaced)
            // ─────────────────────────────────────────────────────────────
            case .tabBarHome:
                return UIElement(id: rawValue, name: "Home Tab", screen: .dashboard,
                                xPct: 0.10, yPct: 0.965,  // 1/5 of width
                                widthPct: 0.20, heightPts: 50)
            case .tabBarExercises:
                return UIElement(id: rawValue, name: "Exercises Tab", screen: .dashboard,
                                xPct: 0.30, yPct: 0.965,  // 2/5 of width
                                widthPct: 0.20, heightPts: 50)
            case .tabBarWorkout:
                return UIElement(id: rawValue, name: "Workout Tab", screen: .dashboard,
                                xPct: 0.50, yPct: 0.965,  // Center
                                widthPct: 0.20, heightPts: 50)
            case .tabBarMeals:
                return UIElement(id: rawValue, name: "Meals Tab", screen: .dashboard,
                                xPct: 0.70, yPct: 0.965,  // 4/5 of width
                                widthPct: 0.20, heightPts: 50)
            case .tabBarStats:
                return UIElement(id: rawValue, name: "Stats Tab", screen: .dashboard,
                                xPct: 0.90, yPct: 0.965,  // Right
                                widthPct: 0.20, heightPts: 50)
            case .backButton:
                return UIElement(id: rawValue, name: "Back Button", screen: .unknown,
                                xPct: 0.08, yPct: 0.07,
                                widthPct: 0.11, heightPts: 44)
            case .closeButton:
                return UIElement(id: rawValue, name: "Close Button", screen: .unknown,
                                xPct: 0.92, yPct: 0.07,
                                widthPct: 0.11, heightPts: 44)
                
            // ─────────────────────────────────────────────────────────────
            // ONBOARDING
            // ─────────────────────────────────────────────────────────────
            case .onboardingContinueButton:
                return UIElement(id: rawValue, name: "Continue Button", screen: .onboardingBasics,
                                xPct: 0.50, yPct: 0.92,
                                widthPct: 0.51, heightPts: 50)
            case .onboardingBackButton:
                return UIElement(id: rawValue, name: "Back Button", screen: .onboardingBasics,
                                xPct: 0.20, yPct: 0.92,
                                widthPct: 0.25, heightPts: 50)
            case .onboardingProgressBar:
                return UIElement(id: rawValue, name: "Progress Bar", screen: .onboardingBasics,
                                xPct: 0.50, yPct: 0.12,
                                widthPct: 0.76, heightPts: 4)
            case .onboardingTitle:
                return UIElement(id: rawValue, name: "Step Title", screen: .onboardingBasics,
                                xPct: 0.50, yPct: 0.16)
            case .onboardingTextField:
                return UIElement(id: rawValue, name: "Text Field", screen: .onboardingBasics,
                                xPct: 0.50, yPct: nil,
                                widthPct: 0.87, heightPts: 50)
            case .onboardingSelectionCard:
                return UIElement(id: rawValue, name: "Selection Card", screen: .onboardingBasics,
                                widthPct: 0.92, heightPts: 70)
                
            // ─────────────────────────────────────────────────────────────
            // AUTH SCREEN
            // ─────────────────────────────────────────────────────────────
            case .authLogo:
                return UIElement(id: rawValue, name: "App Logo", screen: .authScreen,
                                xPct: 0.50, yPct: 0.18,
                                widthPct: 0.25, heightPts: 100)
            case .authEmailField:
                return UIElement(id: rawValue, name: "Email Field", screen: .authScreen,
                                xPct: 0.50, yPct: 0.35,
                                widthPct: 0.87, heightPts: 50)
            case .authPasswordField:
                return UIElement(id: rawValue, name: "Password Field", screen: .authScreen,
                                xPct: 0.50, yPct: 0.43,
                                widthPct: 0.87, heightPts: 50)
            case .authConfirmPasswordField:
                return UIElement(id: rawValue, name: "Confirm Password", screen: .authScreen,
                                xPct: 0.50, yPct: 0.52,
                                widthPct: 0.87, heightPts: 50)
            case .authSignInButton:
                return UIElement(id: rawValue, name: "Sign In Button", screen: .authScreen,
                                xPct: 0.50, yPct: 0.61,
                                widthPct: 0.87, heightPts: 50)
            case .authSignUpToggle:
                return UIElement(id: rawValue, name: "Sign Up Toggle", screen: .authScreen,
                                xPct: 0.50, yPct: 0.68)
            case .authAppleButton:
                return UIElement(id: rawValue, name: "Apple Sign In", screen: .authScreen,
                                xPct: 0.50, yPct: 0.76,
                                widthPct: 0.87, heightPts: 50)
            case .authGoogleButton:
                return UIElement(id: rawValue, name: "Google Sign In", screen: .authScreen,
                                xPct: 0.50, yPct: 0.84,
                                widthPct: 0.87, heightPts: 50)
            case .authTermsCheckbox:
                return UIElement(id: rawValue, name: "Terms Checkbox", screen: .authScreen,
                                xPct: 0.08, yPct: 0.58,
                                widthPct: 0.06, heightPts: 24)
            }
        }
    }
    
    // MARK: - Screen Registry (Unique IDs)
    enum Screen: String, CaseIterable {
        // ═══════════════════════════════════════════════════════════
        // MAIN TABS (S1XX)
        // ═══════════════════════════════════════════════════════════
        case dashboard = "S100"
        case exerciseLibrary = "S101"
        case workoutTab = "S102"
        case mealsTab = "S103"
        case statsTab = "S104"
        
        // ═══════════════════════════════════════════════════════════
        // AUTH & ONBOARDING (S2XX)
        // ═══════════════════════════════════════════════════════════
        case authScreen = "S200"
        case onboardingBasics = "S201"
        case onboardingBody = "S202"
        case onboardingGoal = "S203"
        case onboardingExperience = "S204"
        case onboardingStrength = "S205"
        case onboardingLocation = "S206"
        case onboardingEquipment = "S207"
        case onboardingLimitations = "S208"
        case onboardingSchedule = "S209"
        case onboardingConfirmation = "S210"
        case onboardingComplete = "S211"
        
        // ═══════════════════════════════════════════════════════════
        // WORKOUT FLOW (S3XX)
        // ═══════════════════════════════════════════════════════════
        case workoutGeneratorSelection = "S300"
        case workoutMuscleSelection = "S301"
        case workoutEquipmentSelection = "S302"
        case workoutDurationSelection = "S303"
        case workoutPreview = "S304"
        case activeWorkout = "S305"
        case workoutCompletion = "S306"
        case workoutSummary = "S307"
        case customWorkoutBuilder = "S308"
        case exerciseSwap = "S309"
        case restTimer = "S310"
        
        // ═══════════════════════════════════════════════════════════
        // EXERCISE VIEWS (S4XX)
        // ═══════════════════════════════════════════════════════════
        case exerciseDetail = "S400"
        case exerciseVideo = "S401"
        case exerciseHistory = "S402"
        case exerciseSelection = "S403"
        case exerciseSearch = "S404"
        case exerciseFilter = "S405"
        
        // ═══════════════════════════════════════════════════════════
        // PROGRAMS (S5XX)
        // ═══════════════════════════════════════════════════════════
        case programsList = "S500"
        case programDetail = "S501"
        case programSchedule = "S502"
        case programDayDetail = "S503"
        case programExplorer = "S504"
        case generatedProgramsList = "S505"
        
        // ═══════════════════════════════════════════════════════════
        // PROFILE & SETTINGS (S6XX)
        // ═══════════════════════════════════════════════════════════
        case profile = "S600"
        case settings = "S601"
        case editProfile = "S602"
        case equipment = "S603"
        case limitations = "S604"
        case notifications = "S605"
        case appearance = "S606"
        case premium = "S607"
        case privacyPolicy = "S608"
        case termsOfService = "S609"
        
        // ═══════════════════════════════════════════════════════════
        // MEALS & NUTRITION (S7XX)
        // ═══════════════════════════════════════════════════════════
        case mealPlan = "S700"
        case foodSearch = "S701"
        case foodDetail = "S702"
        case mealLog = "S703"
        case nutritionSummary = "S704"
        
        // ═══════════════════════════════════════════════════════════
        // STATS & PROGRESS (S8XX)
        // ═══════════════════════════════════════════════════════════
        case workoutHistory = "S800"
        case progressCharts = "S801"
        case achievements = "S802"
        case streaks = "S803"
        case bodyMetrics = "S804"
        
        // ═══════════════════════════════════════════════════════════
        // WORKOUT HISTORY (S85X)
        // ═══════════════════════════════════════════════════════════
        case workoutHistoryDetail = "S850"
        case workoutRepeatPreview = "S851"
        
        // ═══════════════════════════════════════════════════════════
        // MODALS & SHEETS (S9XX)
        // ═══════════════════════════════════════════════════════════
        case bugReport = "S900"
        case shareSheet = "S901"
        case imagePicker = "S902"
        case datePicker = "S903"
        case alert = "S904"
        case actionSheet = "S905"
        case goButton = "S906"
        case termsSheet = "S907"
        case logPreview = "S908"
        
        // ═══════════════════════════════════════════════════════════
        // WORKOUT GENERATOR STEPS (S35X)
        // ═══════════════════════════════════════════════════════════
        case workoutGenerator = "S350"
        case workoutGeneratorWelcome = "S351"
        case workoutGeneratorDuration = "S352"
        case workoutGeneratorMuscles = "S353"
        case workoutGeneratorLocation = "S354"
        case workoutGeneratorEquipment = "S355"
        case workoutGeneratorIntensity = "S356"
        case workoutGeneratorGenerating = "S357"
        
        // ═══════════════════════════════════════════════════════════
        // ACTIVE WORKOUT SUB-SCREENS (S32X)
        // ═══════════════════════════════════════════════════════════
        case workoutComplete = "S320"
        case workoutRating = "S321"
        case workoutShare = "S322"
        
        // ═══════════════════════════════════════════════════════════
        // UNKNOWN / FALLBACK
        // ═══════════════════════════════════════════════════════════
        case unknown = "S000"
        
        var displayName: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .exerciseLibrary: return "Exercise Library"
            case .workoutTab: return "Workout Tab"
            case .mealsTab: return "Meals Tab"
            case .statsTab: return "Stats Tab"
            case .authScreen: return "Auth Screen"
            case .onboardingBasics: return "Onboarding: Basics"
            case .onboardingBody: return "Onboarding: Body"
            case .onboardingGoal: return "Onboarding: Goal"
            case .onboardingExperience: return "Onboarding: Experience"
            case .onboardingStrength: return "Onboarding: Strength"
            case .onboardingLocation: return "Onboarding: Location"
            case .onboardingEquipment: return "Onboarding: Equipment"
            case .onboardingLimitations: return "Onboarding: Limitations"
            case .onboardingSchedule: return "Onboarding: Schedule"
            case .onboardingConfirmation: return "Onboarding: Confirmation"
            case .onboardingComplete: return "Onboarding: Complete"
            case .workoutGeneratorSelection: return "Workout Generator"
            case .workoutMuscleSelection: return "Muscle Selection"
            case .workoutEquipmentSelection: return "Equipment Selection"
            case .workoutDurationSelection: return "Duration Selection"
            case .workoutPreview: return "Workout Preview"
            case .activeWorkout: return "Active Workout"
            case .workoutCompletion: return "Workout Completion"
            case .workoutSummary: return "Workout Summary"
            case .customWorkoutBuilder: return "Custom Workout Builder"
            case .exerciseSwap: return "Exercise Swap"
            case .restTimer: return "Rest Timer"
            case .exerciseDetail: return "Exercise Detail"
            case .exerciseVideo: return "Exercise Video"
            case .exerciseHistory: return "Exercise History"
            case .exerciseSelection: return "Exercise Selection"
            case .exerciseSearch: return "Exercise Search"
            case .exerciseFilter: return "Exercise Filter"
            case .programsList: return "Programs List"
            case .programDetail: return "Program Detail"
            case .programSchedule: return "Program Schedule"
            case .programDayDetail: return "Program Day Detail"
            case .programExplorer: return "Program Explorer"
            case .generatedProgramsList: return "Generated Programs"
            case .profile: return "Profile"
            case .settings: return "Settings"
            case .editProfile: return "Edit Profile"
            case .equipment: return "Equipment"
            case .limitations: return "Limitations"
            case .notifications: return "Notifications"
            case .appearance: return "Appearance"
            case .premium: return "Premium"
            case .privacyPolicy: return "Privacy Policy"
            case .termsOfService: return "Terms of Service"
            case .mealPlan: return "Meal Plan"
            case .foodSearch: return "Food Search"
            case .foodDetail: return "Food Detail"
            case .mealLog: return "Meal Log"
            case .nutritionSummary: return "Nutrition Summary"
            case .workoutHistory: return "Workout History"
            case .progressCharts: return "Progress Charts"
            case .achievements: return "Achievements"
            case .streaks: return "Streaks"
            case .bodyMetrics: return "Body Metrics"
            case .workoutHistoryDetail: return "Workout History Detail"
            case .workoutRepeatPreview: return "Workout Repeat Preview"
            case .bugReport: return "Bug Report"
            case .shareSheet: return "Share Sheet"
            case .imagePicker: return "Image Picker"
            case .datePicker: return "Date Picker"
            case .alert: return "Alert"
            case .actionSheet: return "Action Sheet"
            case .goButton: return "GO Button"
            case .termsSheet: return "Terms & Conditions"
            case .logPreview: return "Log Preview"
            case .workoutGenerator: return "Workout Generator"
            case .workoutGeneratorWelcome: return "Generator: Welcome"
            case .workoutGeneratorDuration: return "Generator: Duration"
            case .workoutGeneratorMuscles: return "Generator: Muscles"
            case .workoutGeneratorLocation: return "Generator: Location"
            case .workoutGeneratorEquipment: return "Generator: Equipment"
            case .workoutGeneratorIntensity: return "Generator: Intensity"
            case .workoutGeneratorGenerating: return "Generator: Generating"
            case .workoutComplete: return "Workout Complete"
            case .workoutRating: return "Workout Rating"
            case .workoutShare: return "Workout Share"
            case .unknown: return "Unknown"
            }
        }
    }
    
    // MARK: - Initialization
    private init() {
        setupNotifications()
        setupCrashHandling()
    }
    
    // MARK: - Crash Handling
    private func setupCrashHandling() {
        // Capture uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            SessionLogManager.shared.logCrash(
                type: "UncaughtException",
                name: exception.name.rawValue,
                reason: exception.reason,
                stackTrace: exception.callStackSymbols.joined(separator: "\n")
            )
        }
        
        // Note: For production, integrate with a crash reporting service
        // This captures what we can before the app terminates
    }
    
    func logCrash(type: String, name: String, reason: String?, stackTrace: String?) {
        crashCount += 1
        log(.error, category: .error, message: "🔥🔥🔥 CRASH DETECTED 🔥🔥🔥", metadata: [
            "crash_type": type,
            "exception_name": name,
            "reason": reason ?? "Unknown",
            "crash_number": crashCount,
            "stack_trace": String(stackTrace?.prefix(2000) ?? "No stack trace")
        ])
        
        // Force save logs immediately for crash
        DispatchQueue.main.async { [weak self] in
            self?.bugReportPending = true
        }
    }
    
    deinit {
        sessionLog.removeAll()
        activeTimers.removeAll()
        screenHistory.removeAll()
        screenDurationHistory.removeAll()
        actionTimeline.removeAll()
        navigationStack.removeAll()
        modalStack.removeAll()
        sheetStack.removeAll()
    }
    
    // MARK: - Session Lifecycle
    
    /// Start a new logging session (call on app launch)
    func startSession(userId: String? = nil, userEmail: String? = nil) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.sessionId = UUID().uuidString
            self.sessionStartTime = Date()
            self.sessionLog = []
            self.memoryWarningCount = 0
            self.networkRequestCount = 0
            self.networkErrorCount = 0
            
            // Capture comprehensive device context
            self.userContext = UserContext(
                userId: userId,
                userEmail: userEmail,
                deviceModel: self.getDeviceModelName(),
                deviceIdentifier: self.getDeviceIdentifier(),
                osVersion: UIDevice.current.systemVersion,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
                locale: Locale.current.identifier,
                timezone: TimeZone.current.identifier,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                totalDiskSpace: self.getTotalDiskSpace(),
                freeDiskSpace: self.getFreeDiskSpace(),
                totalMemory: ProcessInfo.processInfo.physicalMemory,
                screenScale: UIScreen.main.scale,
                screenSize: "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))"
            )
            
            DispatchQueue.main.async {
                self.sessionActive = true
            }
            
            // Refresh device info
            self.deviceInfo = DeviceInfo.current
            
            // Log comprehensive session start with device-specific info
            self.log(.info, category: .session, message: "═══ SESSION STARTED ═══", metadata: [
                "session_id": self.sessionId,
                "device": self.userContext?.deviceModel ?? "Unknown",
                "device_id": self.userContext?.deviceIdentifier ?? "Unknown",
                "iphone_model": self.deviceInfo.model.rawValue,
                "screen_points": "\(Int(self.deviceInfo.screenWidth))x\(Int(self.deviceInfo.screenHeight))",
                "screen_scale": "\(Int(self.deviceInfo.scale))x",
                "ios_version": self.userContext?.osVersion ?? "Unknown",
                "app_version": "\(self.userContext?.appVersion ?? "?") (\(self.userContext?.buildNumber ?? "?"))",
                "locale": self.userContext?.locale ?? "Unknown",
                "timezone": self.userContext?.timezone ?? "Unknown",
                "low_power_mode": self.userContext?.isLowPowerMode ?? false,
                "free_disk_mb": (self.userContext?.freeDiskSpace ?? 0) / 1_000_000,
                "total_memory_gb": String(format: "%.1f", Double(self.userContext?.totalMemory ?? 0) / 1_073_741_824)
            ])
            
            // Log element position reference for this device
            self.log(.debug, category: .session, message: "📱 DEVICE LAYOUT REFERENCE", metadata: [
                "model": self.deviceInfo.model.rawValue,
                "width_pts": Int(self.deviceInfo.screenWidth),
                "height_pts": Int(self.deviceInfo.screenHeight),
                "safe_top": Int(self.deviceInfo.model.safeAreaTop),
                "safe_bottom": Int(self.deviceInfo.model.safeAreaBottom),
                "tab_bar_height": Int(self.deviceInfo.model.tabBarHeight),
                "go_button_expected_y": Int(self.deviceInfo.screenHeight * 0.88)
            ])
        }
    }
    
    /// Update session with user info after authentication
    func updateUserContext(userId: String?, email: String?) {
        logQueue.async { [weak self] in
            guard let self = self, let context = self.userContext else { return }
            
            self.userContext = UserContext(
                userId: userId,
                userEmail: email,
                deviceModel: context.deviceModel,
                deviceIdentifier: context.deviceIdentifier,
                osVersion: context.osVersion,
                appVersion: context.appVersion,
                buildNumber: context.buildNumber,
                locale: context.locale,
                timezone: context.timezone,
                isLowPowerMode: context.isLowPowerMode,
                totalDiskSpace: context.totalDiskSpace,
                freeDiskSpace: context.freeDiskSpace,
                totalMemory: context.totalMemory,
                screenScale: context.screenScale,
                screenSize: context.screenSize
            )
            
            self.log(.info, category: .profile, message: "User context updated", metadata: [
                "user_id": userId ?? "anonymous",
                "email": email ?? "none"
            ])
        }
    }
    
    /// Capture user profile snapshot for debugging
    func captureUserProfile(
        name: String?,
        experienceLevel: String?,
        goals: [String]?,
        equipment: [String]?,
        limitations: [String]?,
        workoutCount: Int,
        favoriteExercisesCount: Int,
        isPremium: Bool
    ) {
        logQueue.async { [weak self] in
            self?.userProfileSnapshot = SessionUserProfile(
                name: name,
                experienceLevel: experienceLevel,
                goals: goals,
                equipment: equipment,
                limitations: limitations,
                totalWorkouts: workoutCount,
                favoriteExercises: favoriteExercisesCount,
                isPremium: isPremium,
                capturedAt: Date()
            )
            
            self?.log(.info, category: .profile, message: "User profile captured", metadata: [
                "name": name ?? "Not set",
                "experience": experienceLevel ?? "Not set",
                "goals": goals?.joined(separator: ", ") ?? "None",
                "equipment_count": equipment?.count ?? 0,
                "limitations_count": limitations?.count ?? 0,
                "total_workouts": workoutCount,
                "favorites_count": favoriteExercisesCount,
                "is_premium": isPremium
            ])
        }
    }
    
    /// End the session and cleanup logs (unless bug report pending)
    func endSession() {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Log session summary
            self.log(.info, category: .session, message: "═══ SESSION ENDING ═══", metadata: [
                "duration": self.formatDuration(self.getSessionDuration()),
                "total_logs": self.sessionLog.count,
                "memory_warnings": self.memoryWarningCount,
                "network_requests": self.networkRequestCount,
                "network_errors": self.networkErrorCount
            ])
            
            DispatchQueue.main.async {
                self.sessionActive = false
                
                // Only keep logs if bug report is pending
                if !self.bugReportPending {
                    self.clearLogs()
                    AppLogger.debug("🗑️ [LOG] Session logs cleared (no bug report)", category: .general)
                } else {
                    AppLogger.debug("📋 [LOG] Session logs retained for bug report", category: .general)
                }
            }
        }
    }
    
    /// Clear all session logs
    func clearLogs() {
        logQueue.async { [weak self] in
            self?.sessionLog = []
            DispatchQueue.main.async {
                self?.bugReportPending = false
                self?.logCount = 0
            }
        }
    }
    
    // MARK: - 🔧 Developer Session Logs (DEBUG only)
    // Usage in LLDB console or code:
    //   po SessionLogManager.shared.devLogs()           - print current session
    //   po SessionLogManager.shared.devLogs(session: 1) - print previous session
    //   po SessionLogManager.shared.devLogs(session: 2) - print 2 sessions ago
    //   po SessionLogManager.shared.devHelp()           - show all commands
    #if DEBUG
    
    /// Show available developer commands
    func devHelp() {
        AppLogger.debug("""
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        🔧 DEVELOPER LOG COMMANDS (use in LLDB: po SessionLogManager.shared.XXX)
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        
        📋 VIEW LOGS:
           devLogs()              → Print CURRENT session logs
           devLogs(session: 1)    → Print PREVIOUS session logs  
           devLogs(session: 2)    → Print 2 sessions ago
        
        🔥 CRASH DETECTION:
           hasCrashLog            → Check if crash was detected
           devLogs(session: 1)    → View crash logs (if crashed)
        
        💾 MANUAL SAVE:
           devSaveNow()           → Force save current logs to disk
        
        🗑️ CLEANUP:
           devClearAll()          → Delete all saved session logs
        
        📁 FILE LOCATIONS:
           devShowPaths()         → Print log file paths
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """, category: .general)
    }
    
    /// Print logs for a session (0=current, 1=previous, 2=two ago)
    func devLogs(session: Int = 0) {
        let url: URL
        let label: String
        
        switch session {
        case 0:
            // Current session - export live
            let content = exportLogsAsText()
            AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .general)
            AppLogger.debug("📋 CURRENT SESSION LOGS (\(sessionLog.count) entries)", category: .general)
            AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .general)
            AppLogger.debug("\(content)", category: .general)
            return
        case 1:
            url = previous1LogURL
            label = "PREVIOUS SESSION"
        case 2:
            url = previous2LogURL
            label = "2 SESSIONS AGO"
        default:
            AppLogger.error("❌ Invalid session number. Use 0 (current), 1 (previous), or 2 (two ago)", category: .general)
            return
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLogger.debug("📋 No logs found for \(label)", category: .general)
            return
        }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .general)
            AppLogger.debug("📋 \(label) LOGS\(hasCrashLog && session == 1 ? " 🔥 CRASH" : "")", category: .general)
            AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .general)
            AppLogger.debug("\(content)", category: .general)
        } catch {
            AppLogger.error("❌ Failed to read logs: \(error)", category: .general)
        }
    }
    
    /// Force save current session logs to disk
    func devSaveNow() {
        persistLogsForCrashRecovery()
    }
    
    /// Show log file paths
    func devShowPaths() {
        AppLogger.debug("""
        📁 Log file locations:
           Current:    \(currentLogURL.path)
           Previous 1: \(previous1LogURL.path)
           Previous 2: \(previous2LogURL.path)
        """, category: .general)
    }
    
    /// Clear all saved logs
    func devClearAll() {
        try? FileManager.default.removeItem(at: currentLogURL)
        try? FileManager.default.removeItem(at: previous1LogURL)
        try? FileManager.default.removeItem(at: previous2LogURL)
        hasCrashLog = false
        AppLogger.debug("🗑️ All session logs cleared", category: .general)
    }
    
    /// Call on app launch to rotate logs and check for crash
    func checkForCrashLog() {
        // Rotate logs: previous2 ← previous1 ← current
        try? FileManager.default.removeItem(at: previous2LogURL)
        if FileManager.default.fileExists(atPath: previous1LogURL.path) {
            try? FileManager.default.moveItem(at: previous1LogURL, to: previous2LogURL)
        }
        if FileManager.default.fileExists(atPath: currentLogURL.path) {
            try? FileManager.default.moveItem(at: currentLogURL, to: previous1LogURL)
        }
        
        // Check if previous session ended cleanly
        let wasCleanShutdown = UserDefaults.standard.bool(forKey: Self.cleanShutdownKey)
        
        if !wasCleanShutdown && FileManager.default.fileExists(atPath: previous1LogURL.path) {
            hasCrashLog = true
            AppLogger.debug("🔥🔥🔥 [DEV] CRASH DETECTED FROM PREVIOUS SESSION 🔥🔥🔥", category: .general)
            AppLogger.debug("📋 [DEV] View with: po SessionLogManager.shared.devLogs(session: 1)", category: .general)
            AppLogger.debug("📋 [DEV] All commands: po SessionLogManager.shared.devHelp()", category: .general)
        }
        
        // Mark this session as not clean (will be set to true on clean shutdown)
        UserDefaults.standard.set(false, forKey: Self.cleanShutdownKey)
    }
    
    /// Call when app is terminating cleanly
    func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: Self.cleanShutdownKey)
        hasCrashLog = false
        AppLogger.info("✅ [DEV] Clean shutdown marked", category: .general)
    }
    
    /// Persist current logs to disk (call periodically or on major events)
    func persistLogsForCrashRecovery() {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            let logText = self.exportLogsAsText()
            do {
                try logText.write(to: self.currentLogURL, atomically: true, encoding: .utf8)
                AppLogger.debug("💾 [DEV] Logs saved (\(self.sessionLog.count) entries)", category: .general)
            } catch {
                AppLogger.error("❌ [DEV] Failed to persist logs: \(error)", category: .general)
            }
        }
    }
    
    #endif
    
    // MARK: - Core Logging Method
    
    /// Log a message with category and optional metadata
    func log(_ level: LogLevel, category: LogCategory, message: String, metadata: [String: Any]? = nil) {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Circular buffer: drop oldest when full
            if self.sessionLog.count >= self.maxLogEntries {
                let dropCount = self.maxLogEntries / 4
                self.sessionLog.removeFirst(dropCount)
            }
            // Time-based pruning: discard entries older than 24h
            let cutoff = Date().addingTimeInterval(-self.maxLogAge)
            self.sessionLog.removeAll { $0.timestamp < cutoff }
            
            let entry = LogEntry(
                timestamp: Date(),
                level: level,
                category: category,
                message: message,
                metadata: metadata
            )
            
            self.sessionLog.append(entry)
            
            DispatchQueue.main.async {
                self.logCount = self.sessionLog.count
            }
            
            #if DEBUG
            let emoji = level.emoji
            let cat = category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            AppLogger.debug("\(emoji) [\(cat)] \(message)", category: .general)
            if let metadata = metadata, !metadata.isEmpty {
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    AppLogger.debug("   └─ \(key): \(value)", category: .general)
                }
            }
            #endif
        }
    }
    
    // MARK: - Comprehensive Logging Methods
    
    // ─────────────────────────────────────────────────────────────
    // UI ELEMENT TRACKING
    // ─────────────────────────────────────────────────────────────
    
    /// Log when a UI element appears on screen with its position
    func logElementAppear(_ element: Element, frame: CGRect? = nil) {
        let info = element.info
        elementAppearTimes[element.rawValue] = Date()
        
        if let frame = frame {
            elementPositions[element.rawValue] = frame
        }
        
        var meta: [String: Any] = [
            "element_id": element.rawValue,
            "element_name": info.name,
            "screen_id": info.screen.rawValue,
            "device": deviceInfo.model.rawValue,
            "screen_size": "\(Int(deviceInfo.screenWidth))x\(Int(deviceInfo.screenHeight))"
        ]
        
        // Log actual position if provided
        if let frame = frame {
            meta["actual_x"] = Int(frame.midX)
            meta["actual_y"] = Int(frame.midY)
            meta["actual_width"] = Int(frame.width)
            meta["actual_height"] = Int(frame.height)
            
            // Check if position matches expected (now device-aware)
            if let expectedX = info.expectedX {
                let deviation = abs(frame.midX - expectedX)
                meta["expected_x"] = Int(expectedX)
                if deviation > info.tolerance {
                    meta["⚠️_X_DEVIATION"] = Int(deviation)
                    meta["move_left_by"] = frame.midX > expectedX ? Int(deviation) : 0
                    meta["move_right_by"] = frame.midX < expectedX ? Int(deviation) : 0
                }
            }
            if let expectedY = info.expectedY {
                let deviation = abs(frame.midY - expectedY)
                meta["expected_y"] = Int(expectedY)
                if deviation > info.tolerance {
                    meta["⚠️_Y_DEVIATION"] = Int(deviation)
                    meta["move_up_by"] = frame.midY > expectedY ? Int(deviation) : 0
                    meta["move_down_by"] = frame.midY < expectedY ? Int(deviation) : 0
                }
            }
        }
        
        log(.debug, category: .userAction, message: "📍 ELEMENT: [\(element.rawValue)] \(info.name) appeared", metadata: meta)
    }
    
    /// Log when a UI element disappears
    func logElementDisappear(_ element: Element) {
        let info = element.info
        var duration: TimeInterval = 0
        
        if let appearTime = elementAppearTimes[element.rawValue] {
            duration = Date().timeIntervalSince(appearTime)
            elementAppearTimes.removeValue(forKey: element.rawValue)
        }
        
        log(.debug, category: .userAction, message: "📍 ELEMENT: [\(element.rawValue)] \(info.name) hidden", metadata: [
            "element_id": element.rawValue,
            "visible_duration_ms": Int(duration * 1000)
        ])
    }
    
    /// Log element tap with position verification
    func logElementTap(_ element: Element, screen: Screen, tapPoint: CGPoint? = nil) {
        let info = element.info
        lastTapAction = "Tap: \(info.name)"
        lastTapScreenId = screen.rawValue
        lastTapTime = Date()
        
        var meta: [String: Any] = [
            "element_id": element.rawValue,
            "element_name": info.name,
            "screen_id": screen.rawValue
        ]
        
        if let tap = tapPoint {
            meta["tap_x"] = Int(tap.x)
            meta["tap_y"] = Int(tap.y)
        }
        
        // Include expected position for reference
        if let x = info.expectedX { meta["expected_x"] = Int(x) }
        if let y = info.expectedY { meta["expected_y"] = Int(y) }
        
        log(.info, category: .userAction, message: "👆 TAP: [\(element.rawValue)] \(info.name)", metadata: meta)
    }
    
    /// Check element position against expected and log deviation with fix instructions
    func verifyElementPosition(_ element: Element, actualFrame: CGRect) -> Bool {
        let info = element.info
        var isCorrect = true
        var deviations: [String: Any] = [
            "element_id": element.rawValue,
            "element_name": info.name,
            "device": deviceInfo.model.rawValue,
            "screen_size": "\(Int(deviceInfo.screenWidth))x\(Int(deviceInfo.screenHeight))"
        ]
        
        // Log actual position
        deviations["actual_x"] = Int(actualFrame.midX)
        deviations["actual_y"] = Int(actualFrame.midY)
        deviations["actual_width"] = Int(actualFrame.width)
        deviations["actual_height"] = Int(actualFrame.height)
        
        if let expectedX = info.expectedX {
            let xDev = actualFrame.midX - expectedX  // Signed for direction
            deviations["expected_x"] = Int(expectedX)
            if abs(xDev) > info.tolerance {
                deviations["x_deviation_pts"] = Int(abs(xDev))
                if xDev > 0 {
                    deviations["🔧_FIX"] = "Move LEFT by \(Int(xDev)) pts"
                } else {
                    deviations["🔧_FIX"] = "Move RIGHT by \(Int(abs(xDev))) pts"
                }
                isCorrect = false
            }
        }
        
        if let expectedY = info.expectedY {
            let yDev = actualFrame.midY - expectedY  // Signed for direction
            deviations["expected_y"] = Int(expectedY)
            if abs(yDev) > info.tolerance {
                deviations["y_deviation_pts"] = Int(abs(yDev))
                if yDev > 0 {
                    deviations["🔧_FIX_Y"] = "Move UP by \(Int(yDev)) pts"
                } else {
                    deviations["🔧_FIX_Y"] = "Move DOWN by \(Int(abs(yDev))) pts"
                }
                isCorrect = false
            }
        }
        
        if !isCorrect {
            log(.warning, category: .userAction, message: "⚠️ ELEMENT MISPOSITIONED: [\(element.rawValue)] \(info.name)", metadata: deviations)
        }
        
        return isCorrect
    }
    
    /// Get expected position for any element on current device
    func getExpectedPosition(for element: Element) -> (x: CGFloat?, y: CGFloat?, width: CGFloat?, height: CGFloat?) {
        let info = element.info
        return (
            x: info.expectedX,
            y: info.expectedY,
            width: info.expectedWidth,
            height: info.expectedHeight
        )
    }
    
    /// Get all element positions for current device (for debugging)
    func getAllExpectedPositions() -> [String: [String: Any]] {
        var positions: [String: [String: Any]] = [:]
        
        for element in Element.allCases {
            let info = element.info
            var pos: [String: Any] = [
                "name": info.name,
                "screen": info.screen.displayName
            ]
            if let x = info.expectedX { pos["x"] = Int(x) }
            if let y = info.expectedY { pos["y"] = Int(y) }
            if let w = info.expectedWidth { pos["width"] = Int(w) }
            if let h = info.expectedHeight { pos["height"] = Int(h) }
            pos["tolerance"] = Int(info.tolerance)
            
            positions[element.rawValue] = pos
        }
        
        return positions
    }
    
    // ─────────────────────────────────────────────────────────────
    // GO! BUTTON TRACKING (Special - Critical Element)
    // ─────────────────────────────────────────────────────────────
    
    /// Call when GO! button appears
    func logGoButtonShow(frame: CGRect? = nil) {
        goButtonShowTime = Date()
        goButtonShowCount += 1
        
        var meta: [String: Any] = [
            "element_id": Element.goButton.rawValue,
            "show_count": goButtonShowCount
        ]
        
        if let frame = frame {
            meta["x"] = Int(frame.midX)
            meta["y"] = Int(frame.midY)
            meta["width"] = Int(frame.width)
            meta["height"] = Int(frame.height)
            
            // Verify position
            let info = Element.goButton.info
            if let expectedX = info.expectedX, abs(frame.midX - expectedX) > info.tolerance {
                meta["⚠️_X_OFF"] = Int(frame.midX - expectedX)
            }
            if let expectedY = info.expectedY, abs(frame.midY - expectedY) > info.tolerance {
                meta["⚠️_Y_OFF"] = Int(frame.midY - expectedY)
            }
        }
        
        log(.info, category: .userAction, message: "🟢 GO! BUTTON SHOWN", metadata: meta)
    }
    
    /// Call when GO! button hides
    func logGoButtonHide(reason: String = "auto") {
        goButtonHideTime = Date()
        
        var visibleTime: TimeInterval = 0
        if let showTime = goButtonShowTime {
            visibleTime = Date().timeIntervalSince(showTime)
            goButtonVisibleDuration += visibleTime
        }
        
        var meta: [String: Any] = [
            "element_id": Element.goButton.rawValue,
            "visible_ms": Int(visibleTime * 1000),
            "reason": reason,
            "total_visible_ms": Int(goButtonVisibleDuration * 1000)
        ]
        
        // Flag if shown too briefly (user might miss it)
        if visibleTime < 1.0 {
            meta["⚠️_TOO_BRIEF"] = true
        }
        
        // Flag if shown too long (annoying)
        if visibleTime > 10.0 {
            meta["⚠️_TOO_LONG"] = true
        }
        
        log(.info, category: .userAction, message: "🔴 GO! BUTTON HIDDEN", metadata: meta)
    }
    
    /// Call when GO! button is tapped
    func logGoButtonTap(tapPoint: CGPoint? = nil) {
        var responseTime: TimeInterval = 0
        if let showTime = goButtonShowTime {
            responseTime = Date().timeIntervalSince(showTime)
        }
        
        var meta: [String: Any] = [
            "element_id": Element.goButton.rawValue,
            "response_time_ms": Int(responseTime * 1000),
            "tap_count_this_session": goButtonShowCount
        ]
        
        if let tap = tapPoint {
            meta["tap_x"] = Int(tap.x)
            meta["tap_y"] = Int(tap.y)
        }
        
        // Flag quick response (good UX)
        if responseTime < 2.0 {
            meta["quick_response"] = true
        }
        
        log(.info, category: .userAction, message: "👆 GO! BUTTON TAPPED", metadata: meta)
    }
    
    /// Get GO! button stats for debugging
    func getGoButtonStats() -> [String: Any] {
        return [
            "show_count": goButtonShowCount,
            "total_visible_seconds": Int(goButtonVisibleDuration),
            "last_show_time": goButtonShowTime?.description ?? "never"
        ]
    }
    
    // ─────────────────────────────────────────────────────────────
    // USER ACTIONS
    // ─────────────────────────────────────────────────────────────
    
    func logUserAction(_ action: String, screen: String? = nil, element: String? = nil, metadata: [String: Any]? = nil) {
        var meta = metadata ?? [:]
        if let screen = screen { meta["screen"] = screen }
        if let element = element { meta["element"] = element }
        log(.info, category: .userAction, message: action, metadata: meta.isEmpty ? nil : meta)
    }
    
    func logButtonTap(_ buttonName: String, screen: String) {
        log(.info, category: .userAction, message: "Button tapped: \(buttonName)", metadata: [
            "screen": screen,
            "button": buttonName
        ])
    }
    
    func logSwipe(_ direction: String, screen: String, context: String? = nil) {
        var meta: [String: Any] = ["screen": screen, "direction": direction]
        if let context = context { meta["context"] = context }
        log(.info, category: .userAction, message: "Swipe \(direction)", metadata: meta)
    }
    
    func logScroll(screen: String, direction: String, position: String? = nil) {
        var meta: [String: Any] = ["screen": screen, "direction": direction]
        if let position = position { meta["position"] = position }
        log(.debug, category: .userAction, message: "Scroll \(direction)", metadata: meta)
    }
    
    func logSelection(_ item: String, screen: String, metadata: [String: Any]? = nil) {
        var meta = metadata ?? [:]
        meta["screen"] = screen
        meta["selected"] = item
        log(.info, category: .userAction, message: "Selected: \(item)", metadata: meta)
    }
    
    func logToggle(_ name: String, newValue: Bool, screen: String) {
        log(.info, category: .userAction, message: "Toggle: \(name) → \(newValue)", metadata: [
            "screen": screen,
            "toggle": name,
            "value": newValue
        ])
    }
    
    func logTextInput(field: String, screen: String, characterCount: Int) {
        log(.debug, category: .userAction, message: "Text input: \(field)", metadata: [
            "screen": screen,
            "field": field,
            "length": characterCount
        ])
    }
    
    // ═══════════════════════════════════════════════════════════════════
    // SCREEN TRACKING - MILLISECOND PRECISION
    // Call these on EVERY screen transition!
    // ═══════════════════════════════════════════════════════════════════
    
    /// Start a screen transition - call when user taps to navigate
    func beginTransition(to screen: Screen, from element: Element? = nil, action: String? = nil) {
        transitionStartTime = Date()
        pendingTransitionTo = screen.rawValue
        // No log needed - will be captured in logScreen with timing
    }
    
    /// Log screen appearance with unique ID - CALL ON EVERY SCREEN'S onAppear
    func logScreen(_ screen: Screen, metadata: [String: Any]? = nil) {
        let appearTime = Date()
        
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate all timing
            let transitionMs = self.transitionStartTime.map { Int(appearTime.timeIntervalSince($0) * 1000) }
            let tapToScreenMs = Int(appearTime.timeIntervalSince(self.lastTapTime) * 1000)
            let timeOnPrevScreen = Int(appearTime.timeIntervalSince(self.screenAppearTime) * 1000)
            
            // Build flags
            var flags: [String] = []
            if let t = transitionMs {
                if t > 1000 { flags.append("🔴VERY_SLOW") }
                else if t > 500 { flags.append("🐢SLOW") }
                else if t < 16 { flags.append("⚡INSTANT") }
            }
            if tapToScreenMs < 3000 && tapToScreenMs > 800 { flags.append("🐢NAV") }
            
            // Check wrong screen
            let wasWrongScreen = self.pendingTransitionTo != nil && self.pendingTransitionTo != screen.rawValue
            if wasWrongScreen {
                flags.append("🚨WRONG:\(self.pendingTransitionTo ?? "?")")
            }
            
            // Update tracking
            self.previousScreenId = self.currentScreenId
            self.currentScreenId = screen.rawValue
            self.screenAppearTime = appearTime
            
            // Add to history
            self.screenHistory.append((id: screen.rawValue, name: screen.displayName, timestamp: appearTime, transitionMs: transitionMs))
            if self.screenHistory.count > 100 { self.screenHistory.removeFirst() }
            
            // Forward to advanced logger when active
            let screenName = screen.displayName
            let transMs = transitionMs
            Task { @MainActor in
                guard AdvancedSessionLogger.isActive else { return }
                AdvancedSessionLogger.shared.logScreenView(screenName)
                if let t = transMs {
                    AdvancedSessionLogger.shared.logPerformance("screen_transition:\(screenName)", durationMs: t, screen: screenName)
                }
            }
            
            // Add to compact timeline
            let entry = ActionTimelineEntry(
                timestamp: appearTime,
                action: "→\(screen.rawValue)",
                fromId: self.previousScreenId,
                toId: screen.rawValue,
                loadMs: transitionMs ?? tapToScreenMs,
                durationMs: nil,
                flags: flags
            )
            self.actionTimeline.append(entry)
            if self.actionTimeline.count > 300 { self.actionTimeline.removeFirst() }
            
            // Clear transition tracking
            self.transitionStartTime = nil
            self.pendingTransitionTo = nil
            
            // COMPACT LOG: emoji [ID] name loadMs flags
            let speedEmoji: String
            if let t = transitionMs {
                if t < 100 { speedEmoji = "⚡" }
                else if t < 300 { speedEmoji = "✅" }
                else if t < 500 { speedEmoji = "🟡" }
                else if t < 1000 { speedEmoji = "🐢" }
                else { speedEmoji = "🔴" }
            } else { speedEmoji = "📱" }
            
            let loadStr = transitionMs.map { "\($0)ms" } ?? ""
            let flagStr = flags.isEmpty ? "" : " " + flags.joined(separator: " ")
            
            // Single compact line for normal navigation
            self.log(.info, category: .navigation, message: "\(speedEmoji) [\(screen.rawValue)] \(screen.displayName) \(loadStr)\(flagStr)", metadata: metadata)
            
            // Separate warning if wrong screen
            if wasWrongScreen {
                self.log(.warning, category: .navigation, message: "🚨 WRONG! Expected [\(self.pendingTransitionTo ?? "?")] got [\(screen.rawValue)]")
            }
        }
    }
    
    /// Log screen disappearance with duration tracking
    func logScreenDisappear(_ screen: Screen) {
        let disappearTime = Date()
        let timeOnScreen = Int(disappearTime.timeIntervalSince(screenAppearTime) * 1000)
        let wasFlash = timeOnScreen < 100
        
        // Build flags
        var flags: [String] = []
        if timeOnScreen < 50 { flags.append("🚨FLASH") }
        else if timeOnScreen < 100 { flags.append("⚡BRIEF") }
        
        // Add to compact timeline
        let entry = ActionTimelineEntry(
            timestamp: disappearTime,
            action: "←\(screen.rawValue)",
            fromId: screen.rawValue,
            toId: "?",
            loadMs: nil,
            durationMs: timeOnScreen,
            flags: flags
        )
        actionTimeline.append(entry)
        if actionTimeline.count > 300 { actionTimeline.removeFirst() }
        
        // Store in duration history
        screenDurationHistory.append((
            screenId: screen.rawValue,
            screenName: screen.displayName,
            durationMs: timeOnScreen,
            timestamp: disappearTime,
            wasFlash: wasFlash
        ))
        if screenDurationHistory.count > 200 { screenDurationHistory.removeFirst() }
        
        // COMPACT LOG - only log warnings for flashes, debug for normal
        if timeOnScreen < 50 {
            log(.warning, category: .navigation, message: "🚨 FLASH [\(screen.rawValue)] \(timeOnScreen)ms!")
        } else if timeOnScreen < 100 {
            log(.warning, category: .navigation, message: "⚡ BRIEF [\(screen.rawValue)] \(timeOnScreen)ms")
        } else {
            log(.debug, category: .navigation, message: "← [\(screen.rawValue)] \(timeOnScreen)ms")
        }
    }
    
    
    /// Log a tap action that may trigger navigation
    func logTap(_ action: String, screen: Screen, element: Element? = nil) {
        lastTapAction = action
        lastTapScreenId = screen.rawValue
        lastTapTime = Date()

        // Add to compact timeline
        let entry = ActionTimelineEntry(
            timestamp: Date(),
            action: "tap:\(action)",
            fromId: screen.rawValue,
            toId: pendingTransitionTo ?? "?",
            loadMs: nil,
            durationMs: nil,
            flags: []
        )
        actionTimeline.append(entry)
        if actionTimeline.count > 300 { actionTimeline.removeFirst() }

        // Compact log - just one line
        let elemStr = element.map { " [\($0.rawValue)]" } ?? ""
        log(.info, category: .userAction, message: "👆 \(action)\(elemStr) @\(screen.rawValue)", metadata: nil)
        
        // 🛡️ Breadcrumb for crash reporting
        CrashReportingService.shared.addBreadcrumb("tap: \(action)", screen: screen.displayName)
    }
    
    /// Log navigation push (NavigationLink, etc.)
    func logNavigationPush(to screen: Screen, from: Screen? = nil) {
        let fromScreen = from ?? (Screen.allCases.first { $0.rawValue == currentScreenId } ?? .unknown)
        navigationStack.append(screen.rawValue)
        
        beginTransition(to: screen)
        
        log(.info, category: .navigation, message: "➡️ NAV PUSH: [\(fromScreen.rawValue)] → [\(screen.rawValue)]", metadata: [
            "from": fromScreen.rawValue,
            "to": screen.rawValue,
            "stack_depth": navigationStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
        
        // 🛡️ Breadcrumb for crash reporting
        CrashReportingService.shared.addBreadcrumb("navigate: \(fromScreen.displayName) → \(screen.displayName)", screen: screen.displayName)
    }
    
    /// Log navigation pop (back button)
    func logNavigationPop(to screen: Screen? = nil) {
        let poppedScreen = navigationStack.popLast() ?? currentScreenId
        let destination = screen?.rawValue ?? navigationStack.last ?? "S100"
        
        log(.info, category: .navigation, message: "⬅️ NAV POP: [\(poppedScreen)] → [\(destination)]", metadata: [
            "popped": poppedScreen,
            "destination": destination,
            "stack_depth": navigationStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    /// Log modal/fullscreen presentation
    func logModalPresent(_ screen: Screen, style: String = "fullscreen") {
        modalStack.append(screen.rawValue)
        beginTransition(to: screen)
        
        log(.info, category: .navigation, message: "📤 MODAL PRESENT: [\(screen.rawValue)] \(screen.displayName)", metadata: [
            "screen_id": screen.rawValue,
            "style": style,
            "modal_depth": modalStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    /// Log modal dismiss
    func logModalDismiss(_ screen: Screen? = nil) {
        let dismissed = screen?.rawValue ?? modalStack.popLast() ?? currentScreenId
        
        log(.info, category: .navigation, message: "📥 MODAL DISMISS: [\(dismissed)]", metadata: [
            "dismissed": dismissed,
            "modal_depth": modalStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    /// Log sheet presentation
    func logSheetPresent(_ screen: Screen) {
        sheetStack.append(screen.rawValue)
        beginTransition(to: screen)
        
        log(.info, category: .navigation, message: "📋 SHEET PRESENT: [\(screen.rawValue)] \(screen.displayName)", metadata: [
            "screen_id": screen.rawValue,
            "sheet_depth": sheetStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    /// Log sheet dismiss
    func logSheetDismiss(_ screen: Screen? = nil) {
        let dismissed = screen?.rawValue ?? sheetStack.popLast() ?? currentScreenId
        
        log(.info, category: .navigation, message: "📋 SHEET DISMISS: [\(dismissed)]", metadata: [
            "dismissed": dismissed,
            "sheet_depth": sheetStack.count,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
        ])
    }
    
    /// Verify user landed on expected screen after tap
    func verifyNavigation(expected: Screen, actual: Screen) {
        if expected != actual {
            log(.warning, category: .navigation, message: "⚠️ WRONG SCREEN!", metadata: [
                "expected_id": expected.rawValue,
                "expected_name": expected.displayName,
                "actual_id": actual.rawValue,
                "actual_name": actual.displayName,
                "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
            ])
        }
    }
    
    // Legacy support - still works
    func logNavigation(from: String, to: String, trigger: String? = nil) {
        var meta: [String: Any] = ["from": from, "to": to]
        if let trigger = trigger { meta["trigger"] = trigger }
        log(.info, category: .navigation, message: "Navigate: \(from) → \(to)", metadata: meta)
    }
    
    // Legacy support - convert string to screen ID if possible
    func logScreenAppear(_ screenName: String, metadata: [String: Any]? = nil) {
        // Try to find matching screen
        let screen = Screen.allCases.first { $0.displayName.lowercased() == screenName.lowercased() } ?? .unknown
        logScreen(screen, metadata: metadata)
    }
    
    func logTabSwitch(from: String, to: String) {
        // Map tab names to screen IDs (support both short and display names)
        let tabToScreen: [String: Screen] = [
            "Home": .dashboard, "Exercises": .exerciseLibrary, "Workout": .workoutTab,
            "Meals": .mealsTab, "Stats": .statsTab, "Dashboard": .dashboard,
            "Exercise Library": .exerciseLibrary, "Workout Tab": .workoutTab,
            "Meals Tab": .mealsTab, "Stats Tab": .statsTab
        ]

        let fromScreen = tabToScreen[from] ?? .unknown
        let toScreen = tabToScreen[to] ?? .unknown

        lastTapAction = "Tab:\(to)"
        lastTapScreenId = fromScreen.rawValue
        lastTapTime = Date()
        
        // Add to timeline
        let entry = ActionTimelineEntry(
            timestamp: Date(),
            action: "tab:\(fromScreen.rawValue)→\(toScreen.rawValue)",
            fromId: fromScreen.rawValue,
            toId: toScreen.rawValue,
            loadMs: nil,
            durationMs: nil,
            flags: []
        )
        actionTimeline.append(entry)
        if actionTimeline.count > 300 { actionTimeline.removeFirst() }

        // Compact log
        log(.info, category: .navigation, message: "📑 [\(fromScreen.rawValue)]→[\(toScreen.rawValue)]")
        
        // 🛡️ Breadcrumb for crash reporting
        CrashReportingService.shared.addBreadcrumb("tab: \(from) → \(to)", screen: toScreen.displayName)
    }
    
    func logAlertPresent(_ alertTitle: String, screen: Screen) {
        log(.info, category: .navigation, message: "🚨 ALERT: \(alertTitle)", metadata: [
            "screen_id": screen.rawValue,
            "alert": alertTitle
        ])
    }
    
    /// Get current screen info for debugging
    func getCurrentScreenInfo() -> (id: String, name: String) {
        let screen = Screen.allCases.first { $0.rawValue == currentScreenId } ?? .unknown
        return (currentScreenId, screen.displayName)
    }
    
    /// Get navigation history as string (for logs)
    func getNavigationPath() -> String {
        return screenHistory.suffix(10).map { "[\($0.id)]" }.joined(separator: " → ")
    }
    
    // ─────────────────────────────────────────────────────────────
    // WORKOUT TRACKING
    // ─────────────────────────────────────────────────────────────
    
    func logWorkoutStart(workoutId: String, type: String, exerciseCount: Int, source: String) {
        log(.info, category: .workout, message: "🏋️ WORKOUT STARTED", metadata: [
            "workout_id": workoutId,
            "type": type,
            "exercise_count": exerciseCount,
            "source": source
        ])
        
        // 🔧 DEV: Persist logs after workout start (important checkpoint)
        #if DEBUG
        persistLogsForCrashRecovery()
        #endif
    }
    
    func logWorkoutEnd(workoutId: String, duration: TimeInterval, exercisesCompleted: Int, totalSets: Int, caloriesBurned: Int?) {
        var meta: [String: Any] = [
            "workout_id": workoutId,
            "duration_minutes": Int(duration / 60),
            "exercises_completed": exercisesCompleted,
            "total_sets": totalSets
        ]
        if let calories = caloriesBurned { meta["calories"] = calories }
        log(.info, category: .workout, message: "🏋️ WORKOUT COMPLETED", metadata: meta)
    }
    
    func logWorkoutCancel(workoutId: String, reason: String?, exercisesCompleted: Int, duration: TimeInterval) {
        log(.warning, category: .workout, message: "⚠️ Workout cancelled", metadata: [
            "workout_id": workoutId,
            "reason": reason ?? "User cancelled",
            "exercises_completed": exercisesCompleted,
            "duration_minutes": Int(duration / 60)
        ])
    }
    
    func logExerciseStart(exerciseName: String, workoutId: String, position: Int) {
        log(.info, category: .exercise, message: "Exercise started: \(exerciseName)", metadata: [
            "exercise": exerciseName,
            "workout_id": workoutId,
            "position": position
        ])
    }
    
    func logExerciseComplete(exerciseName: String, setsCompleted: Int, totalReps: Int, totalWeight: Double?) {
        var meta: [String: Any] = [
            "exercise": exerciseName,
            "sets": setsCompleted,
            "total_reps": totalReps
        ]
        if let weight = totalWeight { meta["total_weight_lbs"] = Int(weight) }
        log(.info, category: .exercise, message: "Exercise done: \(exerciseName)", metadata: meta)
    }
    
    func logExerciseSkip(exerciseName: String, reason: String?) {
        log(.warning, category: .exercise, message: "Exercise skipped: \(exerciseName)", metadata: [
            "exercise": exerciseName,
            "reason": reason ?? "User skipped"
        ])
    }
    
    func logExerciseSwap(from: String, to: String, reason: String?) {
        log(.info, category: .exercise, message: "Exercise swapped: \(from) → \(to)", metadata: [
            "from_exercise": from,
            "to_exercise": to,
            "reason": reason ?? "User preference"
        ])
    }
    
    func logSetComplete(exerciseName: String, setNumber: Int, reps: Int, weight: Double?, rpe: Int?) {
        var meta: [String: Any] = [
            "exercise": exerciseName,
            "set": setNumber,
            "reps": reps
        ]
        if let weight = weight { meta["weight_lbs"] = weight }
        if let rpe = rpe { meta["rpe"] = rpe }
        log(.info, category: .exercise, message: "Set \(setNumber): \(reps) reps", metadata: meta)
    }
    
    func logRestTimerStart(duration: Int, afterExercise: String) {
        log(.debug, category: .workout, message: "Rest timer: \(duration)s", metadata: [
            "duration_sec": duration,
            "after_exercise": afterExercise
        ])
    }
    
    func logRestTimerSkip(remainingTime: Int) {
        log(.debug, category: .workout, message: "Rest skipped (\(remainingTime)s remaining)")
    }
    
    func logFavoriteExercise(_ exerciseName: String, isFavorite: Bool) {
        log(.info, category: .exercise, message: isFavorite ? "⭐️ Favorited: \(exerciseName)" : "Unfavorited: \(exerciseName)", metadata: [
            "exercise": exerciseName,
            "favorited": isFavorite
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // WORKOUT GENERATION
    // ─────────────────────────────────────────────────────────────
    
    func logWorkoutGeneration(type: String, muscleGroups: [String], equipment: [String], duration: Int) {
        log(.info, category: .workout, message: "🎯 Generating workout", metadata: [
            "type": type,
            "muscle_groups": muscleGroups.joined(separator: ", "),
            "equipment": equipment.joined(separator: ", "),
            "target_duration": duration
        ])
    }
    
    func logWorkoutGenerationComplete(exerciseCount: Int, duration: TimeInterval) {
        log(.info, category: .workout, message: "✅ Workout generated", metadata: [
            "exercises": exerciseCount,
            "generation_time_ms": Int(duration * 1000)
        ])
    }
    
    func logWorkoutGenerationError(_ error: Error) {
        log(.error, category: .workout, message: "❌ Workout generation failed", metadata: [
            "error": error.localizedDescription
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // PROFILE & SETTINGS
    // ─────────────────────────────────────────────────────────────
    
    func logProfileUpdate(field: String, oldValue: String?, newValue: String?) {
        log(.info, category: .profile, message: "Profile updated: \(field)", metadata: [
            "field": field,
            "old_value": oldValue ?? "empty",
            "new_value": newValue ?? "empty"
        ])
    }
    
    func logSettingsChange(setting: String, oldValue: Any?, newValue: Any?) {
        log(.info, category: .profile, message: "Setting changed: \(setting)", metadata: [
            "setting": setting,
            "old_value": String(describing: oldValue ?? "nil"),
            "new_value": String(describing: newValue ?? "nil")
        ])
    }
    
    func logEquipmentUpdate(added: [String]?, removed: [String]?) {
        var meta: [String: Any] = [:]
        if let added = added, !added.isEmpty { meta["added"] = added.joined(separator: ", ") }
        if let removed = removed, !removed.isEmpty { meta["removed"] = removed.joined(separator: ", ") }
        log(.info, category: .profile, message: "Equipment updated", metadata: meta.isEmpty ? nil : meta)
    }
    
    func logGoalsUpdate(goals: [String]) {
        log(.info, category: .profile, message: "Goals updated", metadata: [
            "goals": goals.joined(separator: ", ")
        ])
    }
    
    func logLimitationsUpdate(limitations: [String]) {
        log(.info, category: .profile, message: "Limitations updated", metadata: [
            "limitations": limitations.joined(separator: ", ")
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // ONBOARDING
    // ─────────────────────────────────────────────────────────────
    
    func logOnboardingStart() {
        log(.info, category: .onboarding, message: "📝 Onboarding started")
    }
    
    func logOnboardingStep(step: Int, stepName: String, action: String, metadata: [String: Any]? = nil) {
        var meta = metadata ?? [:]
        meta["step_number"] = step
        meta["step_name"] = stepName
        log(.info, category: .onboarding, message: "Step \(step): \(action)", metadata: meta)
    }
    
    func logOnboardingComplete(totalSteps: Int, duration: TimeInterval) {
        log(.info, category: .onboarding, message: "✅ Onboarding complete", metadata: [
            "total_steps": totalSteps,
            "duration_seconds": Int(duration)
        ])
    }
    
    func logOnboardingSkip(atStep: Int, stepName: String) {
        log(.warning, category: .onboarding, message: "⚠️ Onboarding skipped", metadata: [
            "at_step": atStep,
            "step_name": stepName
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // AUTHENTICATION
    // ─────────────────────────────────────────────────────────────
    
    func logAuthAttempt(method: String) {
        log(.info, category: .profile, message: "🔐 Auth attempt: \(method)", metadata: [
            "method": method
        ])
    }
    
    func logAuthSuccess(method: String, userId: String) {
        log(.info, category: .profile, message: "✅ Auth success", metadata: [
            "method": method,
            "user_id": userId
        ])
    }
    
    func logAuthFailure(method: String, error: String) {
        log(.error, category: .profile, message: "❌ Auth failed", metadata: [
            "method": method,
            "error": error
        ])
    }
    
    func logLogout() {
        log(.info, category: .profile, message: "👋 User logged out")
    }
    
    // ─────────────────────────────────────────────────────────────
    // NETWORK & DATA
    // ─────────────────────────────────────────────────────────────
    
    func logNetworkRequest(endpoint: String, method: String) {
        networkRequestCount += 1
        log(.debug, category: .network, message: "\(method) \(endpoint)", metadata: [
            "method": method,
            "endpoint": endpoint
        ])
    }
    
    func logNetworkResponse(endpoint: String, statusCode: Int, duration: TimeInterval) {
        let level: LogLevel = statusCode >= 400 ? .error : .debug
        if statusCode >= 400 { networkErrorCount += 1 }
        log(level, category: .network, message: "Response: \(statusCode)", metadata: [
            "endpoint": endpoint,
            "status": statusCode,
            "duration_ms": Int(duration * 1000)
        ])
    }
    
    func logNetworkError(endpoint: String, error: Error) {
        networkErrorCount += 1
        log(.error, category: .network, message: "❌ Network error", metadata: [
            "endpoint": endpoint,
            "error": error.localizedDescription
        ])
        
        // 🛡️ Breadcrumb for crash reporting
        CrashReportingService.shared.addBreadcrumb("network error: \(endpoint) — \(error.localizedDescription)")
    }
    
    func logDataSync(type: String, itemCount: Int, direction: String) {
        log(.info, category: .data, message: "Sync: \(type)", metadata: [
            "type": type,
            "items": itemCount,
            "direction": direction
        ])
    }
    
    func logCoreDataOperation(operation: String, entity: String, count: Int? = nil) {
        var meta: [String: Any] = ["operation": operation, "entity": entity]
        if let count = count { meta["count"] = count }
        log(.debug, category: .data, message: "\(operation): \(entity)", metadata: meta)
    }
    
    func logCoreDataError(_ error: Error, operation: String) {
        log(.error, category: .data, message: "❌ CoreData error", metadata: [
            "operation": operation,
            "error": error.localizedDescription
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // HEALTH KIT
    // ─────────────────────────────────────────────────────────────
    
    func logHealthKitAuth(granted: Bool) {
        log(.info, category: .health, message: granted ? "✅ HealthKit authorized" : "❌ HealthKit denied")
    }
    
    func logHealthKitWrite(type: String, success: Bool, error: Error? = nil) {
        if success {
            log(.info, category: .health, message: "HealthKit write: \(type)")
        } else {
            log(.error, category: .health, message: "❌ HealthKit write failed", metadata: [
                "type": type,
                "error": error?.localizedDescription ?? "Unknown"
            ])
        }
    }
    
    func logHealthKitRead(type: String, valueCount: Int) {
        log(.debug, category: .health, message: "HealthKit read: \(type)", metadata: [
            "type": type,
            "values": valueCount
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // ERRORS & PERFORMANCE
    // ─────────────────────────────────────────────────────────────
    
    func logError(_ error: Error, context: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        var meta: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error": error.localizedDescription,
            "file": fileName,
            "function": function,
            "line": line
        ]
        if let context = context { meta["context"] = context }
        log(.error, category: .error, message: "❌ \(error.localizedDescription)", metadata: meta)
    }
    
    func logWarning(_ message: String, context: String? = nil) {
        var meta: [String: Any]? = nil
        if let context = context { meta = ["context": context] }
        log(.warning, category: .error, message: "⚠️ \(message)", metadata: meta)
    }
    
    func logCrashRecovery(crashType: String, details: String?) {
        log(.error, category: .error, message: "🔥 Crash recovered", metadata: [
            "type": crashType,
            "details": details ?? "No details"
        ])
    }
    
    func logMemoryWarning() {
        memoryWarningCount += 1
        log(.warning, category: .session, message: "⚠️ Memory warning #\(memoryWarningCount)", metadata: [
            "warning_count": memoryWarningCount
        ])
    }
    
    func logPerformance(operation: String, duration: TimeInterval) {
        let level: LogLevel = duration > 1.0 ? .warning : .debug
        log(level, category: .session, message: "⏱️ \(operation): \(Int(duration * 1000))ms", metadata: [
            "operation": operation,
            "duration_ms": Int(duration * 1000)
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // PREMIUM & PURCHASES
    // ─────────────────────────────────────────────────────────────
    
    func logPremiumCheck(isPremium: Bool) {
        log(.info, category: .profile, message: "Premium status: \(isPremium ? "Active" : "Free")")
    }
    
    func logPurchaseAttempt(productId: String) {
        log(.info, category: .profile, message: "💳 Purchase attempt", metadata: [
            "product_id": productId
        ])
    }
    
    func logPurchaseSuccess(productId: String) {
        log(.info, category: .profile, message: "✅ Purchase success", metadata: [
            "product_id": productId
        ])
    }
    
    func logPurchaseFailure(productId: String, error: String) {
        log(.error, category: .profile, message: "❌ Purchase failed", metadata: [
            "product_id": productId,
            "error": error
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // ADS
    // ─────────────────────────────────────────────────────────────
    
    func logAdSDKInitialized(durationMs: Int) {
        log(.info, category: .session, message: "📺 Ad SDK initialized", metadata: [
            "duration_ms": durationMs
        ])
    }
    
    func logAdLoad(success: Bool, adUnitId: String, loadTimeMs: Int, error: String? = nil) {
        if success {
            log(.info, category: .session, message: "📺 Ad loaded", metadata: [
                "ad_unit_id": adUnitId,
                "load_time_ms": loadTimeMs
            ])
        } else {
            log(.warning, category: .session, message: "📺 Ad load failed", metadata: [
                "ad_unit_id": adUnitId,
                "load_time_ms": loadTimeMs,
                "error": error ?? "Unknown"
            ])
        }
    }
    
    func logAdShow(adUnitId: String, placement: String) {
        log(.info, category: .session, message: "📺 Ad shown", metadata: [
            "ad_unit_id": adUnitId,
            "placement": placement
        ])
    }
    
    func logAdDismissed(adUnitId: String, watchedDurationMs: Int) {
        log(.info, category: .session, message: "📺 Ad dismissed", metadata: [
            "ad_unit_id": adUnitId,
            "watched_duration_ms": watchedDurationMs
        ])
    }
    
    func logAdClicked(adUnitId: String) {
        log(.info, category: .session, message: "📺 Ad clicked", metadata: [
            "ad_unit_id": adUnitId
        ])
    }
    
    func logAdError(adUnitId: String, error: String, context: String) {
        log(.error, category: .session, message: "📺 Ad error", metadata: [
            "ad_unit_id": adUnitId,
            "error": error,
            "context": context
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // PUSH NOTIFICATIONS
    // ─────────────────────────────────────────────────────────────
    
    func logNotificationPermissionRequested() {
        log(.info, category: .session, message: "🔔 Notification permission requested")
    }
    
    func logNotificationPermissionResult(granted: Bool, status: String) {
        log(.info, category: .session, message: granted ? "🔔 Notifications enabled" : "🔔 Notifications denied", metadata: [
            "granted": granted,
            "status": status
        ])
    }
    
    func logNotificationScheduled(type: String, scheduledFor: Date, identifier: String) {
        log(.info, category: .session, message: "🔔 Notification scheduled", metadata: [
            "type": type,
            "scheduled_for": formatDate(scheduledFor),
            "identifier": identifier
        ])
    }
    
    func logNotificationCancelled(type: String, identifier: String) {
        log(.debug, category: .session, message: "🔔 Notification cancelled", metadata: [
            "type": type,
            "identifier": identifier
        ])
    }
    
    func logNotificationReceived(type: String, identifier: String, appState: String) {
        log(.info, category: .session, message: "🔔 Notification received", metadata: [
            "type": type,
            "identifier": identifier,
            "app_state": appState
        ])
    }
    
    func logNotificationOpened(type: String, identifier: String, responseAction: String?) {
        log(.info, category: .session, message: "🔔 Notification opened", metadata: [
            "type": type,
            "identifier": identifier,
            "response_action": responseAction ?? "default"
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // NETWORK CONNECTIVITY
    // ─────────────────────────────────────────────────────────────
    
    func logConnectivityChange(isOnline: Bool, connectionType: String) {
        log(isOnline ? .info : .warning, category: .network, message: isOnline ? "🌐 Online" : "📵 Offline", metadata: [
            "is_online": isOnline,
            "connection_type": connectionType
        ])
    }
    
    func logOfflineAttempt(feature: String, action: String) {
        log(.warning, category: .network, message: "📵 Offline action attempted", metadata: [
            "feature": feature,
            "action": action
        ])
    }
    
    func logReconnected(offlineDurationSeconds: Int) {
        log(.info, category: .network, message: "🌐 Reconnected", metadata: [
            "offline_duration_seconds": offlineDurationSeconds
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // EXERCISE SEARCH
    // ─────────────────────────────────────────────────────────────
    
    func logExerciseSearch(query: String, resultCount: Int, filters: [String]? = nil) {
        var meta: [String: Any] = [
            "query": query,
            "result_count": resultCount
        ]
        if let filters = filters, !filters.isEmpty {
            meta["filters"] = filters.joined(separator: ", ")
        }
        log(.debug, category: .userAction, message: "🔍 Exercise search", metadata: meta)
    }
    
    func logExerciseSearchSelection(query: String, selectedExercise: String, selectedIndex: Int, totalResults: Int) {
        log(.info, category: .userAction, message: "🔍 Search selection", metadata: [
            "query": query,
            "selected": selectedExercise,
            "selected_index": selectedIndex,
            "total_results": totalResults
        ])
    }
    
    func logExerciseSearchNoResults(query: String, filters: [String]?) {
        log(.info, category: .userAction, message: "🔍 Search no results", metadata: [
            "query": query,
            "filters": filters?.joined(separator: ", ") ?? "none"
        ])
    }
    
    func logExerciseSearchAbandoned(query: String, resultCount: Int, timeSpentMs: Int) {
        log(.debug, category: .userAction, message: "🔍 Search abandoned", metadata: [
            "query": query,
            "result_count": resultCount,
            "time_spent_ms": timeSpentMs
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // VIDEO PLAYBACK
    // ─────────────────────────────────────────────────────────────
    
    func logVideoLoadStarted(exerciseName: String, source: String) {
        log(.debug, category: .data, message: "🎬 Video loading", metadata: [
            "exercise": exerciseName,
            "source": source
        ])
    }
    
    func logVideoLoadComplete(exerciseName: String, loadTimeMs: Int, source: String, fileSize: Int? = nil) {
        var meta: [String: Any] = [
            "exercise": exerciseName,
            "load_time_ms": loadTimeMs,
            "source": source
        ]
        if let size = fileSize { meta["file_size_kb"] = size / 1024 }
        log(.debug, category: .data, message: "🎬 Video loaded", metadata: meta)
    }
    
    func logVideoPlaybackError(exerciseName: String, error: String, source: String, attemptedUrl: String? = nil) {
        var meta: [String: Any] = [
            "exercise": exerciseName,
            "error": error,
            "source": source
        ]
        if let url = attemptedUrl { meta["url"] = url }
        log(.error, category: .data, message: "🎬 Video playback error", metadata: meta)
    }
    
    func logVideoStalled(exerciseName: String, stalledAtSecond: Double, bufferEmpty: Bool) {
        log(.warning, category: .data, message: "🎬 Video stalled", metadata: [
            "exercise": exerciseName,
            "stalled_at_second": stalledAtSecond,
            "buffer_empty": bufferEmpty
        ])
    }
    
    func logVideoFallbackUsed(exerciseName: String, originalGender: String, fallbackGender: String) {
        log(.info, category: .data, message: "🎬 Video fallback used", metadata: [
            "exercise": exerciseName,
            "original_gender": originalGender,
            "fallback_gender": fallbackGender
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // APP UPDATE & MIGRATION
    // ─────────────────────────────────────────────────────────────
    
    func logAppFirstLaunch(version: String, build: String) {
        log(.info, category: .session, message: "🎉 First app launch", metadata: [
            "version": version,
            "build": build
        ])
    }
    
    func logAppUpdated(previousVersion: String, newVersion: String, previousBuild: String, newBuild: String) {
        log(.info, category: .session, message: "⬆️ App updated", metadata: [
            "previous_version": previousVersion,
            "new_version": newVersion,
            "previous_build": previousBuild,
            "new_build": newBuild
        ])
    }
    
    func logMigrationStarted(type: String, fromVersion: String) {
        log(.info, category: .session, message: "🔄 Migration started", metadata: [
            "type": type,
            "from_version": fromVersion
        ])
    }
    
    func logMigrationCompleted(type: String, itemsMigrated: Int, durationMs: Int) {
        log(.info, category: .session, message: "✅ Migration completed", metadata: [
            "type": type,
            "items_migrated": itemsMigrated,
            "duration_ms": durationMs
        ])
    }
    
    func logMigrationFailed(type: String, error: String) {
        log(.error, category: .session, message: "❌ Migration failed", metadata: [
            "type": type,
            "error": error
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // RETENTION METRICS
    // ─────────────────────────────────────────────────────────────
    
    private var sessionNumber: Int = 0
    private var lastSessionDate: Date?
    
    func logSessionStart(sessionNumber: Int, daysSinceLastSession: Int?, totalWorkoutsCompleted: Int) {
        self.sessionNumber = sessionNumber
        
        var meta: [String: Any] = [
            "session_number": sessionNumber,
            "total_workouts": totalWorkoutsCompleted
        ]
        
        if let days = daysSinceLastSession {
            meta["days_since_last"] = days
            meta["user_type"] = categorizeReturnUser(daysSince: days)
        } else {
            meta["user_type"] = "new"
        }
        
        log(.info, category: .session, message: "📊 Session #\(sessionNumber)", metadata: meta)
    }
    
    private func categorizeReturnUser(daysSince: Int) -> String {
        switch daysSince {
        case 0: return "same_day"
        case 1: return "daily"
        case 2...7: return "weekly"
        case 8...30: return "monthly"
        default: return "returning_churned"
        }
    }
    
    func logUserMilestone(type: String, value: Int, previousValue: Int? = nil) {
        var meta: [String: Any] = [
            "type": type,
            "value": value
        ]
        if let prev = previousValue { meta["previous_value"] = prev }
        log(.info, category: .session, message: "🏆 Milestone: \(type)", metadata: meta)
    }
    
    func logFeatureFirstUse(feature: String) {
        log(.info, category: .userAction, message: "✨ First use: \(feature)", metadata: [
            "feature": feature,
            "session_number": sessionNumber
        ])
    }
    
    // ─────────────────────────────────────────────────────────────
    // PERSONAL RECORDS & ACHIEVEMENTS
    // ─────────────────────────────────────────────────────────────
    
    func logPersonalRecord(exerciseName: String, metric: String, oldValue: Double, newValue: Double, improvement: Double) {
        log(.info, category: .workout, message: "🏅 PR: \(exerciseName)", metadata: [
            "exercise": exerciseName,
            "metric": metric,
            "old_value": oldValue,
            "new_value": newValue,
            "improvement": improvement,
            "improvement_percent": oldValue > 0 ? ((newValue - oldValue) / oldValue * 100).rounded() : 0
        ])
    }
    
    func logAchievementUnlocked(achievementId: String, achievementName: String, category: String) {
        log(.info, category: .session, message: "🏆 Achievement: \(achievementName)", metadata: [
            "achievement_id": achievementId,
            "achievement_name": achievementName,
            "category": category
        ])
    }
    
    func logAchievementProgress(achievementId: String, achievementName: String, currentProgress: Int, targetProgress: Int) {
        log(.debug, category: .session, message: "📈 Achievement progress", metadata: [
            "achievement_id": achievementId,
            "achievement_name": achievementName,
            "current": currentProgress,
            "target": targetProgress,
            "percent": Int((Double(currentProgress) / Double(targetProgress)) * 100)
        ])
    }
    
    func logStreakMilestone(streakDays: Int, streakType: String) {
        log(.info, category: .session, message: "🔥 Streak milestone: \(streakDays) days", metadata: [
            "streak_days": streakDays,
            "streak_type": streakType
        ])
    }
    
    func logStreakBroken(previousStreak: Int, streakType: String, daysMissed: Int) {
        log(.warning, category: .session, message: "💔 Streak broken", metadata: [
            "previous_streak": previousStreak,
            "streak_type": streakType,
            "days_missed": daysMissed
        ])
    }
    
    func logStreakSaved(streakDays: Int, saveMethod: String) {
        log(.info, category: .session, message: "🛡️ Streak saved", metadata: [
            "streak_days": streakDays,
            "save_method": saveMethod
        ])
    }
    
    // MARK: - Bug Report Generation
    
    /// Generate a bug report with all session logs
    func generateBugReport(userDescription: String, category: BugCategory) -> SessionBugReport {
        if Thread.isMainThread {
            bugReportPending = true
        } else {
            DispatchQueue.main.async { [weak self] in self?.bugReportPending = true }
        }
        
        let report = SessionBugReport(
            id: UUID().uuidString,
            sessionId: sessionId,
            timestamp: Date(),
            userDescription: userDescription,
            category: category,
            userContext: userContext,
            userProfile: userProfileSnapshot,
            logs: sessionLog,
            sessionDuration: getSessionDuration(),
            memoryWarnings: memoryWarningCount,
            networkRequests: networkRequestCount,
            networkErrors: networkErrorCount
        )
        
        log(.info, category: .session, message: "📋 Bug report generated", metadata: [
            "report_id": report.id,
            "category": category.rawValue,
            "log_count": sessionLog.count
        ])
        
        return report
    }
    
    /// Export logs as a comprehensive text file for attachment
    func exportLogsAsText() -> String {
        var output = """
        ╔═══════════════════════════════════════════════════════════════════╗
        ║                     FIT33 BUG REPORT LOG                         ║
        ╚═══════════════════════════════════════════════════════════════════╝
        
        ┌─────────────────────────────────────────────────────────────────────┐
        │ SESSION INFO                                                        │
        └─────────────────────────────────────────────────────────────────────┘
        Session ID:      \(sessionId)
        Started:         \(formatDate(sessionStartTime))
        Duration:        \(formatDuration(getSessionDuration()))
        Total Logs:      \(sessionLog.count)
        Memory Warnings: \(memoryWarningCount)
        Network Requests:\(networkRequestCount)
        Network Errors:  \(networkErrorCount)
        
        """
        
        if let context = userContext {
            output += """
        ┌─────────────────────────────────────────────────────────────────────┐
        │ DEVICE INFO                                                         │
        └─────────────────────────────────────────────────────────────────────┘
        Device:          \(context.deviceModel)
        iPhone Model:    \(deviceInfo.model.rawValue)
        Screen (points): \(Int(deviceInfo.screenWidth))x\(Int(deviceInfo.screenHeight))
        Safe Area Top:   \(Int(deviceInfo.model.safeAreaTop)) pts
        Safe Area Bottom:\(Int(deviceInfo.model.safeAreaBottom)) pts
        Tab Bar Height:  \(Int(deviceInfo.model.tabBarHeight)) pts
        Device ID:       \(context.deviceIdentifier)
        iOS Version:     \(context.osVersion)
        App Version:     \(context.appVersion) (\(context.buildNumber))
        Locale:          \(context.locale)
        Timezone:        \(context.timezone)
        Low Power Mode:  \(context.isLowPowerMode ? "Yes" : "No")
        Free Disk:       \(context.freeDiskSpace / 1_000_000) MB
        Screen Scale:    \(context.screenScale)x
        
        """
            
            if let userId = context.userId {
                output += "User ID:         \(userId)\n"
            }
            if let email = context.userEmail {
                output += "Email:           \(email)\n"
            }
        }
        
        if let profile = userProfileSnapshot {
            output += """
        
        ┌─────────────────────────────────────────────────────────────────────┐
        │ USER PROFILE                                                        │
        └─────────────────────────────────────────────────────────────────────┘
        Name:            \(profile.name ?? "Not set")
        Experience:      \(profile.experienceLevel ?? "Not set")
        Goals:           \(profile.goals?.joined(separator: ", ") ?? "None")
        Equipment:       \(profile.equipment?.joined(separator: ", ") ?? "None")
        Limitations:     \(profile.limitations?.joined(separator: ", ") ?? "None")
        Total Workouts:  \(profile.totalWorkouts)
        Favorites:       \(profile.favoriteExercises)
        Premium:         \(profile.isPremium ? "Yes" : "No")
        
        """
        }
        
        // Log statistics
        var categoryCount: [String: Int] = [:]
        var errorCount = 0
        var warningCount = 0
        
        for entry in sessionLog {
            categoryCount[entry.category.rawValue, default: 0] += 1
            if entry.level == .error { errorCount += 1 }
            if entry.level == .warning { warningCount += 1 }
        }
        
        output += """
        
        ┌─────────────────────────────────────────────────────────────────────┐
        │ LOG STATISTICS                                                      │
        └─────────────────────────────────────────────────────────────────────┘
        Total Entries:   \(sessionLog.count)
        Errors:          \(errorCount)
        Warnings:        \(warningCount)
        
        By Category:
        """
        
        for (category, count) in categoryCount.sorted(by: { $0.value > $1.value }) {
            output += "\n  • \(category.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)"
        }
        
        // COMPACT ACTION TIMELINE - shows full flow
        output += """


        ┌─────────────────────────────────────────────────────────────────────┐
        │ ACTION TIMELINE (tap → screen → duration)                           │
        └─────────────────────────────────────────────────────────────────────┘
        Format: TIME | ACTION | LOAD/DURATION | FLAGS
        """

        let recentActions = actionTimeline.suffix(50)
        for entry in recentActions {
            let time = formatTime(entry.timestamp)
            let timing: String
            if let load = entry.loadMs {
                timing = "\(load)ms load"
            } else if let dur = entry.durationMs {
                timing = "\(dur)ms on screen"
            } else {
                timing = ""
            }
            let flags = entry.flags.isEmpty ? "" : " " + entry.flags.joined(separator: " ")
            output += "\n  \(time) \(entry.action.padding(toLength: 20, withPad: " ", startingAt: 0)) \(timing.padding(toLength: 15, withPad: " ", startingAt: 0))\(flags)"
        }

        if actionTimeline.isEmpty {
            output += "\n  No actions recorded"
        }

        // Quick stats
        let taps = actionTimeline.filter { $0.action.hasPrefix("tap:") }.count
        let screens = actionTimeline.filter { $0.action.hasPrefix("→") }.count
        let flashes = actionTimeline.filter { $0.flags.contains { $0.contains("FLASH") || $0.contains("BRIEF") } }.count
        let slowLoads = actionTimeline.filter { ($0.loadMs ?? 0) > 500 }.count
        let wrongScreens = actionTimeline.filter { $0.flags.contains { $0.contains("WRONG") } }.count

        output += """


        Quick Stats: \(taps) taps → \(screens) screens | \(flashes) flashes | \(slowLoads) slow | \(wrongScreens) wrong
        """
        
        // Add screen transition statistics
        let transitionTimes = screenHistory.compactMap { $0.transitionMs }
        if !transitionTimes.isEmpty {
            let avgTransition = transitionTimes.reduce(0, +) / transitionTimes.count
            let maxTransition = transitionTimes.max() ?? 0
            let slowTransitions = transitionTimes.filter { $0 > 500 }.count

            output += """

            Load Times: avg \(avgTransition)ms | max \(maxTransition)ms | slow(>500ms) \(slowTransitions)/\(transitionTimes.count)
            """
        }
        
        // Duration stats
        let durations = screenDurationHistory.map { $0.durationMs }
        if !durations.isEmpty {
            let avgDuration = durations.reduce(0, +) / durations.count
            output += """

            Screen Durations: avg \(avgDuration)ms | flashes(<100ms) \(flashes)/\(durations.count)
            """
        }
        
        // Flash warnings summary (if any)
        let flashScreens = screenDurationHistory.filter { $0.wasFlash }
        if !flashScreens.isEmpty {
            output += """


            ⚠️ FLASH WARNINGS (\(flashScreens.count) screens appeared < 100ms):
            """
            for flash in flashScreens.suffix(10) {
                output += "\n  🚨 [\(flash.screenId)] \(flash.screenName) - \(flash.durationMs)ms"
            }
        }

        output += """


        ┌─────────────────────────────────────────────────────────────────────┐
        │ DETAILED SESSION LOG                                                │
        └─────────────────────────────────────────────────────────────────────┘

        """
        
        let sortedLogs = sessionLog.sorted { $0.timestamp < $1.timestamp }
        
        for entry in sortedLogs {
            let time = formatTime(entry.timestamp)
            let level = entry.level.emoji
            let category = entry.category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            
            output += "\(time) \(level) [\(category)] \(entry.message)\n"
            
            if let metadata = entry.metadata, !metadata.isEmpty {
                let sortedMeta = metadata.sorted { $0.key < $1.key }
                for (key, value) in sortedMeta {
                    output += "                └─ \(key): \(value)\n"
                }
            }
        }
        
        output += """
        
        ╔═══════════════════════════════════════════════════════════════════╗
        ║              END OF LOG • \(sessionLog.count) entries                          ║
        ╚═══════════════════════════════════════════════════════════════════╝
        """
        
        return output
    }
    
    /// Get log file URL for sharing
    func getLogFileURL() -> URL? {
        let logText = exportLogsAsText()
        let dateStr = formatFileDate(Date())
        let fileName = "fit33_bugreport_\(sessionId.prefix(8))_\(dateStr).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try logText.write(to: tempURL, atomically: true, encoding: .utf8)
            log(.info, category: .session, message: "Log file created", metadata: ["file": fileName])
            return tempURL
        } catch {
            log(.error, category: .error, message: "Failed to write log file", metadata: ["error": error.localizedDescription])
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func appWillTerminate() {
        endSession()
    }
    
    @objc private func appDidEnterBackground() {
        log(.info, category: .session, message: "📱 App → Background")
    }
    
    @objc private func appWillEnterForeground() {
        log(.info, category: .session, message: "📱 App → Foreground")
    }
    
    @objc private func didReceiveMemoryWarning() {
        logMemoryWarning()
    }
    
    private func getDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return modelCode
    }
    
    private func getDeviceModelName() -> String {
        let identifier = getDeviceIdentifier()
        
        // Map common identifiers to names
        let deviceMap: [String: String] = [
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "x86_64": "iPhone Simulator",
            "arm64": "iPhone Simulator"
        ]
        
        return deviceMap[identifier] ?? identifier
    }
    
    private func getTotalDiskSpace() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemSize] as? Int64 else { return 0 }
        return space
    }
    
    private func getFreeDiskSpace() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let space = attrs[.systemFreeSize] as? Int64 else { return 0 }
        return space
    }
    
    private func getSessionDuration() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    private func formatFileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

// MARK: - Supporting Types

struct LogEntry: Codable {
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let metadata: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case timestamp, level, category, message, metadata
    }
    
    init(timestamp: Date, level: LogLevel, category: LogCategory, message: String, metadata: [String: Any]?) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LogLevel.self, forKey: .level)
        category = try container.decode(LogCategory.self, forKey: .category)
        message = try container.decode(String.self, forKey: .message)
        metadata = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(category, forKey: .category)
        try container.encode(message, forKey: .message)
    }
}

enum LogLevel: String, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

enum LogCategory: String, Codable {
    case session = "SESSION"
    case userAction = "USER"
    case navigation = "NAV"
    case workout = "WORKOUT"
    case exercise = "EXERCISE"
    case network = "NETWORK"
    case error = "ERROR"
    case profile = "PROFILE"
    case onboarding = "ONBOARD"
    case data = "DATA"
    case health = "HEALTH"
    case challenge = "CHALLENGE"
    case pushNotification = "PUSH"
    case social = "SOCIAL"
    case auth = "AUTH"
    case sync = "SYNC"
}

struct UserContext: Codable {
    let userId: String?
    let userEmail: String?
    let deviceModel: String
    let deviceIdentifier: String
    let osVersion: String
    let appVersion: String
    let buildNumber: String
    let locale: String
    let timezone: String
    let isLowPowerMode: Bool
    let totalDiskSpace: Int64
    let freeDiskSpace: Int64
    let totalMemory: UInt64
    let screenScale: CGFloat
    let screenSize: String
}

struct SessionUserProfile: Codable {
    let name: String?
    let experienceLevel: String?
    let goals: [String]?
    let equipment: [String]?
    let limitations: [String]?
    let totalWorkouts: Int
    let favoriteExercises: Int
    let isPremium: Bool
    let capturedAt: Date
}

enum BugCategory: String, CaseIterable, Codable {
    case crash = "App Crash"
    case uiBug = "UI/Display Issue"
    case workoutIssue = "Workout Problem"
    case dataLoss = "Data Loss"
    case performance = "Performance Issue"
    case featureNotWorking = "Feature Not Working"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .crash: return "xmark.octagon.fill"
        case .uiBug: return "rectangle.on.rectangle"
        case .workoutIssue: return "figure.strengthtraining.traditional"
        case .dataLoss: return "externaldrive.badge.xmark"
        case .performance: return "speedometer"
        case .featureNotWorking: return "wrench.and.screwdriver"
        case .other: return "questionmark.circle"
        }
    }
}

struct SessionBugReport: Codable {
    let id: String
    let sessionId: String
    let timestamp: Date
    let userDescription: String
    let category: BugCategory
    let userContext: UserContext?
    let userProfile: SessionUserProfile?
    let logs: [LogEntry]
    let sessionDuration: TimeInterval
    let memoryWarnings: Int
    let networkRequests: Int
    let networkErrors: Int
}

// MARK: - Convenience Extensions

extension View {
    /// Log screen with unique ID - PREFERRED METHOD
    func trackScreen(_ screen: SessionLogManager.Screen, metadata: [String: Any]? = nil) -> some View {
        self.onAppear {
            SessionLogManager.shared.logScreen(screen, metadata: metadata)
        }
        .onDisappear {
            SessionLogManager.shared.logScreenDisappear(screen)
        }
    }
    
    /// Legacy: Log when this view appears (string-based)
    func logAppearance(_ screenName: String) -> some View {
        self.onAppear {
            SessionLogManager.shared.logScreenAppear(screenName)
        }
        .onDisappear {
            // Try to find matching screen for disappear log
            let screen = SessionLogManager.Screen.allCases.first { 
                $0.displayName.lowercased() == screenName.lowercased() 
            } ?? .unknown
            SessionLogManager.shared.logScreenDisappear(screen)
        }
    }
}
