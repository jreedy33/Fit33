import SwiftUI
import UIKit
import Combine

// MARK: - Bug Report Model
struct BugReport: Codable, Identifiable {
    let id: UUID
    let userId: UUID?
    let userName: String?
    let userEmail: String?
    let description: String
    let expectedBehavior: String?
    let reproducesEveryTime: Bool
    let screenshotUrl: String?
    let screenshotBase64: String?
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let screenName: String?
    let additionalInfo: String?
    let sessionLog: String?
    let status: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userName = "user_name"
        case userEmail = "user_email"
        case description
        case expectedBehavior = "expected_behavior"
        case reproducesEveryTime = "reproduces_every_time"
        case screenshotUrl = "screenshot_url"
        case screenshotBase64 = "screenshot_base64"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case screenName = "screen_name"
        case additionalInfo = "additional_info"
        case sessionLog = "session_log"
        case status
        case createdAt = "created_at"
    }
    
    // Provide defaults for display
    var displayDeviceModel: String { deviceModel ?? "Unknown" }
    var displayOsVersion: String { osVersion ?? "Unknown" }
    var displayAppVersion: String { appVersion ?? "Unknown" }
    var displayExpectedBehavior: String { expectedBehavior ?? "" }
    var displayUserName: String { userName ?? "Anonymous" }
    var displayUserEmail: String { userEmail ?? "No email" }
    var hasSessionLog: Bool { !(sessionLog ?? "").isEmpty }
}

/// `BugReportInsert` writes to the `bug_reports` Supabase table. See
/// `supabase/20260502_rage_shake_v2.sql` for the column list. The shake
/// flow populates `severity`, `bugCategory`, `likelySourceFiles`,
/// `screenName` automatically so Claude has enough context to produce a
/// real `bug_intelligence_report` (file_path + code_diff) via the
/// `triage-shake-reports` edge function.
struct BugReportInsert: Encodable {
    let id: UUID
    let userId: UUID?
    let userName: String?
    let userEmail: String?
    let description: String
    let expectedBehavior: String
    let reproducesEveryTime: Bool
    let screenshotBase64: String?
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let screenName: String?
    let additionalInfo: String?
    let sessionLog: String?
    let status: String
    // v2 fields — rage shake
    let severity: String           // low | medium | high | critical
    let bugCategory: String?       // ui | data | performance | crash | auth | workout | nutrition | social | health | other
    let likelySourceFiles: [String]
    let triageStatus: String       // pending (client always sets pending; trigger fires)
    // Phase 7 / Cheat Code — runtime state snapshot. Opaque JSON dict
    // built by BugReportSnapshotter.buildSnapshot() at shake time.
    // Encoded via encodeRawJSON(...) so PostgREST lands it as JSONB.
    let stateSnapshot: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userName = "user_name"
        case userEmail = "user_email"
        case description
        case expectedBehavior = "expected_behavior"
        case reproducesEveryTime = "reproduces_every_time"
        case screenshotBase64 = "screenshot_base64"
        case sessionLog = "session_log"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case screenName = "screen_name"
        case additionalInfo = "additional_info"
        case status
        case severity
        case bugCategory = "bug_category"
        case likelySourceFiles = "likely_source_files"
        case triageStatus = "triage_status"
        case stateSnapshot = "state_snapshot"
    }

    // Custom encoder — all fields trivial except stateSnapshot which is
    // `[String: Any]` (not Codable). We route it through JSONSerialization
    // and then re-decode as an opaque AnyCodable value for the Supabase
    // Swift client.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(userName, forKey: .userName)
        try c.encodeIfPresent(userEmail, forKey: .userEmail)
        try c.encode(description, forKey: .description)
        try c.encode(expectedBehavior, forKey: .expectedBehavior)
        try c.encode(reproducesEveryTime, forKey: .reproducesEveryTime)
        try c.encodeIfPresent(screenshotBase64, forKey: .screenshotBase64)
        try c.encode(deviceModel, forKey: .deviceModel)
        try c.encode(osVersion, forKey: .osVersion)
        try c.encode(appVersion, forKey: .appVersion)
        try c.encodeIfPresent(screenName, forKey: .screenName)
        try c.encodeIfPresent(additionalInfo, forKey: .additionalInfo)
        try c.encodeIfPresent(sessionLog, forKey: .sessionLog)
        try c.encode(status, forKey: .status)
        try c.encode(severity, forKey: .severity)
        try c.encodeIfPresent(bugCategory, forKey: .bugCategory)
        try c.encode(likelySourceFiles, forKey: .likelySourceFiles)
        try c.encode(triageStatus, forKey: .triageStatus)
        if let snap = stateSnapshot, !snap.isEmpty {
            // Serialize via Foundation → decode as AnyCodableJSON so the
            // Supabase client encodes it as a JSONB object (not a string).
            let data = try JSONSerialization.data(withJSONObject: snap, options: [])
            let decoded = try JSONDecoder().decode(AnyCodableJSON.self, from: data)
            try c.encode(decoded, forKey: .stateSnapshot)
        }
    }
}

/// Helper that can both decode and encode arbitrary JSON so we can round-trip
/// `[String: Any]` through `BugReportInsert`'s Codable path without losing
/// structure. Kept tiny and local to the bug report module — if we need an
/// app-wide AnyCodable later, promote it then.
private struct AnyCodableJSON: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let arr = try? c.decode([AnyCodableJSON].self) { value = arr.map { $0.value } }
        else if let obj = try? c.decode([String: AnyCodableJSON].self) {
            var out: [String: Any] = [:]
            for (k, v) in obj { out[k] = v.value }
            value = out
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let arr as [Any]: try c.encode(arr.map { AnyCodableJSON($0) })
        case let obj as [String: Any]:
            var out: [String: AnyCodableJSON] = [:]
            for (k, v) in obj { out[k] = AnyCodableJSON(v) }
            try c.encode(out)
        default: try c.encodeNil()
        }
    }
}

/// User-chosen severity for rage-shake reports. Maps 1:1 to the
/// `bug_reports.severity` CHECK constraint.
enum BugSeverity: String, CaseIterable, Identifiable {
    case low, medium, high, critical
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    var detail: String {
        switch self {
        case .low: return "Minor inconvenience"
        case .medium: return "Feature doesn’t work as expected"
        case .high: return "Blocks me from using a core feature"
        case .critical: return "Crashes / data loss / can’t continue"
        }
    }
}

// MARK: - Shake Detection Manager
@MainActor
class ShakeDetectionManager: ObservableObject {
    static let shared = ShakeDetectionManager()
    
    @Published var showBugReportSheet = false
    @Published var capturedScreenshot: UIImage?
    @Published var isEnabled = true
    
    private var lastShakeTime: Date?
    private let shakeCooldown: TimeInterval = 2.0 // Prevent multiple triggers
    private var shakeObserver: NSObjectProtocol?
    
    private init() {
        // Listen for shake notifications as backup
        shakeObserver = NotificationCenter.default.addObserver(
            forName: .deviceDidShake,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleShake()
            }
        }
    }
    
    deinit {
        if let observer = shakeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func handleShake() {
        guard isEnabled else { return }
        
        // Prevent multiple triggers in quick succession
        if let lastShake = lastShakeTime, Date().timeIntervalSince(lastShake) < shakeCooldown {
            return
        }
        
        lastShakeTime = Date()
        
        // Haptic feedback first
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // Capture screenshot immediately (before any UI changes)
        captureScreenshot()
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            self.showBugReportSheet = true
        }
    }
    
    private func captureScreenshot() {
        // Get all windows and find the key window
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            AppLogger.warning("⚠️ Could not find window scene for screenshot", category: .general)
            return
        }
        
        guard let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            AppLogger.warning("⚠️ Could not find window for screenshot", category: .general)
            return
        }
        
        // Capture the screenshot
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        
        capturedScreenshot = image
        AppLogger.debug("📸 Screenshot captured: \(image.size)", category: .general)
    }
    
    func clearScreenshot() {
        capturedScreenshot = nil
    }
}

// MARK: - Bug Report Service
@MainActor
class BugReportService: ObservableObject {
    static let shared = BugReportService()
    
    @Published var bugReports: [BugReport] = []
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var lastError: String?
    
    private init() {}
    
    // MARK: - Fetch All Bug Reports (Admin)
    func fetchAllBugReports() async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        AppLogger.debug("🔄 Fetching all bug reports...", category: .general)
        
        // Check authentication first — NOT an error if the user is signed
        // out; the admin UI handles the empty state.
        let isAuthenticated = SupabaseManager.shared.currentUser != nil
        AppLogger.debug("🔐 Authentication status: \(isAuthenticated ? "authenticated" : "not authenticated")", category: .general)

        if !isAuthenticated {
            let errorMessage = "Not authenticated. Please sign in to view bug reports."
            AppLogger.info(errorMessage, category: .general)
            await MainActor.run {
                lastError = errorMessage
            }
            return
        }
        
        do {
            let reports: [BugReport] = try await SupabaseManager.shared.supabaseClient
                .from("bug_reports")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            
            await MainActor.run {
                bugReports = reports
            }
            AppLogger.debug("🐛 Loaded \(reports.count) bug reports", category: .general)
            
            if reports.isEmpty {
                AppLogger.debug("ℹ️ No bug reports found in database", category: .general)
            }
            
            for report in reports {
                AppLogger.debug("  - Bug ID: \(report.id), Status: \(report.status), Created: \(report.createdAt)", category: .general)
            }
        } catch {
            let errorMessage = "Error fetching bug reports: \(error.localizedDescription)"
            NetworkErrorClassifier.log(error, context: "Fetching bug reports", category: .general)
            await MainActor.run {
                lastError = errorMessage
            }
        }
    }
    
    // MARK: - Submit Bug Report
    //
    // When `screenName` is nil the service auto-detects the current screen
    // via `SessionLogManager.shared.getCurrentScreenInfo()`. It also
    // computes `likelySourceFiles` via `ScreenCodeMap.filesForScreen(...)`
    // so the CMS triage edge function has a real file path to hand Claude.
    // Rage shake passes a non-nil `screenName`; the manual `ManualBugReportView`
    // relies on the auto-detect.
    func submitBugReport(
        description: String,
        expectedBehavior: String,
        reproducesEveryTime: Bool,
        screenshot: UIImage?,
        screenName: String? = nil,
        additionalInfo: String? = nil,
        sessionLog: String? = nil,
        severity: BugSeverity = .medium,
        bugCategory: String? = nil,
        likelySourceFiles: [String]? = nil,
        // Phase 7 / Cheat Code — pre-captured runtime state. Pass nil
        // and the service will capture one just-in-time. Passing an
        // explicit snapshot lets the view snapshot at `onAppear` so
        // nav-churn during the report-writing session doesn't
        // invalidate the state the user was complaining about.
        stateSnapshot: [String: Any]? = nil
    ) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        
        do {
            // Compress and encode screenshot - use lower quality to stay under Supabase limits
            var screenshotBase64: String? = nil
            if let image = screenshot {
                // Compress to JPEG with quality 0.3 to keep size under database limits
                if let imageData = image.jpegData(compressionQuality: 0.3) {
                    // Only include if under 500KB base64 encoded
                    let base64 = imageData.base64EncodedString()
                    if base64.count < 500_000 {
                        screenshotBase64 = base64
                        AppLogger.debug("📸 Screenshot size: \(base64.count) chars", category: .general)
                    } else {
                        AppLogger.warning("⚠️ Screenshot too large (\(base64.count) chars), skipping", category: .general)
                    }
                }
            }
            
            // Get device info
            let device = UIDevice.current
            let deviceModel = getDeviceModel()
            let osVersion = "\(device.systemName) \(device.systemVersion)"
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            
            // Get user ID, name, and email
            let userIdString: String
            let userName: String?
            let userEmail: String?
            if let userId = SupabaseManager.shared.currentUser?.id {
                userIdString = userId.uuidString
                // Get user name from UserManager
                userName = UserManager.shared.currentUser?.name
                // Get email from SupabaseManager auth user
                userEmail = SupabaseManager.shared.currentUser?.email
            } else {
                userIdString = "anonymous"
                userName = nil
                userEmail = nil
            }
            
            // Auto-detect screen + likely source files if caller didn't
            // provide them. SessionLogManager.getCurrentScreenInfo() returns
            // ("S100", "Dashboard")-style; we pass the human name to
            // ScreenCodeMap so Claude gets file paths like
            // ["Fit33/DashboardView.swift", ...].
            let detectedScreen: String? = {
                if let s = screenName, !s.isEmpty { return s }
                let info = SessionLogManager.shared.getCurrentScreenInfo()
                return info.name.isEmpty ? nil : info.name
            }()
            let detectedFiles: [String] = {
                if let f = likelySourceFiles, !f.isEmpty { return f }
                return ScreenCodeMap.filesForScreen(detectedScreen)
            }()

            // Phase 7: capture runtime state at SUBMIT time if caller
            // didn't snapshot earlier. View-level snapshot is preferred
            // (caught at the moment the user shook, before they typed
            // their description + navigated).
            let capturedSnapshot: [String: Any]? = {
                if let pre = stateSnapshot { return pre }
                return BugReportSnapshotter.shared.buildSnapshot()
            }()

            // Create the report using the Codable struct
            let report = BugReportInsert(
                id: UUID(),
                userId: SupabaseManager.shared.currentUser?.id,
                userName: userName,
                userEmail: userEmail,
                description: description,
                expectedBehavior: expectedBehavior,
                reproducesEveryTime: reproducesEveryTime,
                screenshotBase64: screenshotBase64,
                deviceModel: deviceModel,
                osVersion: osVersion,
                appVersion: appVersion,
                screenName: detectedScreen,
                additionalInfo: additionalInfo,
                sessionLog: sessionLog,
                status: "new",
                severity: severity.rawValue,
                bugCategory: bugCategory,
                likelySourceFiles: detectedFiles,
                triageStatus: "pending",
                stateSnapshot: capturedSnapshot
            )
            
            AppLogger.debug("📤 Submitting bug report to Supabase...", category: .network)
            AppLogger.debug("  - Description: \(description.prefix(50))...", category: .general)
            AppLogger.debug("  - Has screenshot: \(screenshotBase64 != nil)", category: .general)
            AppLogger.debug("  - User ID: \(userIdString)", category: .general)
            AppLogger.debug("  - User Name: \(userName ?? "anonymous")", category: .general)
            AppLogger.debug("  - User Email: \(userEmail ?? "none")", category: .general)
            
            // Insert using Codable struct
            let response = try await SupabaseManager.shared.supabaseClient
                .from("bug_reports")
                .insert(report)
                .execute()
            
            AppLogger.info("✅ Bug report submitted successfully!", category: .general)
            AppLogger.debug("  - Response status: \(response.status)", category: .general)
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            return true
        } catch {
            NetworkErrorClassifier.log(error, context: "Submitting bug report", category: .general)
            return false
        }
    }
    
    // MARK: - Delete Bug Report (Admin)
    func deleteBugReport(id: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("bug_reports")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            
            // Remove from local list
            bugReports.removeAll { $0.id == id }
            AppLogger.debug("🗑️ Bug report deleted: \(id)", category: .general)
            return true
        } catch {
            NetworkErrorClassifier.log(error, context: "Deleting bug report", category: .general)
            return false
        }
    }
    
    // MARK: - Update Bug Status (Admin)
    func updateBugStatus(id: UUID, status: String) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("bug_reports")
                .update(["status": status])
                .eq("id", value: id.uuidString)
                .execute()
            
            // Refresh the list to get updated data
            if bugReports.firstIndex(where: { $0.id == id }) != nil {
                await fetchAllBugReports()
            }
            AppLogger.info("✅ Bug status updated to: \(status)", category: .general)
            return true
        } catch {
            NetworkErrorClassifier.log(error, context: "Updating bug status", category: .general)
            return false
        }
    }
    
    // MARK: - Helper: Get Device Model
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - Shake Detecting Window
class ShakeDetectingWindow: UIWindow {
    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionBegan(motion, with: event)
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            AppLogger.debug("📳 Shake detected in window!", category: .general)
            Task { @MainActor in
                ShakeDetectionManager.shared.handleShake()
            }
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - App Delegate Extension for Shake (Backup method)
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            AppLogger.debug("📳 Shake detected via UIWindow extension!", category: .general)
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

// MARK: - Window Scene Delegate for Shake Detection
class ShakeDetectingSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        window = ShakeDetectingWindow(windowScene: windowScene)
        window?.makeKeyAndVisible()
    }
}

// MARK: - Shake Detecting View Wrapper
struct ShakeDetectingView<Content: View>: View {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .background(
                ShakeDetectingViewRepresentable()
                    .frame(width: 0, height: 0)
            )
    }
}

// MARK: - UIViewRepresentable for Shake Detection
struct ShakeDetectingViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ShakeDetectingUIView {
        return ShakeDetectingUIView()
    }
    
    func updateUIView(_ uiView: ShakeDetectingUIView, context: Context) {}
}

class ShakeDetectingUIView: UIView {
    override var canBecomeFirstResponder: Bool { true }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Become first responder to receive motion events
        // Try multiple times to ensure it becomes first responder
        becomeFirstResponder()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            self.becomeFirstResponder()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            self.becomeFirstResponder()
        }
    }
    
    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionBegan(motion, with: event)
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            AppLogger.debug("📳 Shake detected!", category: .general)
            Task { @MainActor in
                ShakeDetectionManager.shared.handleShake()
            }
        }
        super.motionEnded(motion, with: event)
    }
}

