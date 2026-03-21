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

struct BugReportInsert: Codable {
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
        
        // Check authentication first
        let isAuthenticated = SupabaseManager.shared.currentUser != nil
        AppLogger.error("🔐 Authentication status: \(isAuthenticated ? "✅ Authenticated" : "❌ Not authenticated")", category: .general)
        
        if !isAuthenticated {
            let errorMessage = "Not authenticated. Please sign in to view bug reports."
            AppLogger.error("❌ \(errorMessage)", category: .general)
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
            AppLogger.error("❌ \(errorMessage)", category: .general)
            AppLogger.error("❌ Error details: \(String(describing: error))", category: .general)
            
            await MainActor.run {
                lastError = errorMessage
            }
        }
    }
    
    // MARK: - Submit Bug Report
    func submitBugReport(
        description: String,
        expectedBehavior: String,
        reproducesEveryTime: Bool,
        screenshot: UIImage?,
        screenName: String? = nil,
        additionalInfo: String? = nil,
        sessionLog: String? = nil
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
                screenName: screenName,
                additionalInfo: additionalInfo,
                sessionLog: sessionLog,
                status: "new"
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
            AppLogger.error("❌ Error submitting bug report: \(error)", category: .general)
            AppLogger.error("❌ Error type: \(type(of: error))", category: .general)
            if let localizedError = error as? LocalizedError {
                AppLogger.error("❌ Error description: \(localizedError.errorDescription ?? "none")", category: .general)
                AppLogger.error("❌ Failure reason: \(localizedError.failureReason ?? "none")", category: .general)
            }
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
            AppLogger.error("❌ Error deleting bug report: \(error)", category: .general)
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
            AppLogger.error("❌ Error updating bug status: \(error)", category: .general)
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

