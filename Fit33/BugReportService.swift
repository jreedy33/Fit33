import SwiftUI
import UIKit
import Combine

// MARK: - Bug Report Model
struct BugReport: Codable, Identifiable {
    let id: UUID
    let userId: UUID?
    let userName: String?
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
    let status: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userName = "user_name"
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
        case status
        case createdAt = "created_at"
    }
    
    // Provide defaults for display
    var displayDeviceModel: String { deviceModel ?? "Unknown" }
    var displayOsVersion: String { osVersion ?? "Unknown" }
    var displayAppVersion: String { appVersion ?? "Unknown" }
    var displayExpectedBehavior: String { expectedBehavior ?? "" }
}

struct BugReportInsert: Codable {
    let id: UUID
    let userId: UUID?
    let userName: String?
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
        
        // Show bug report sheet after a brief delay to ensure screenshot is captured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.showBugReportSheet = true
        }
    }
    
    private func captureScreenshot() {
        // Get all windows and find the key window
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            print("⚠️ Could not find window scene for screenshot")
            return
        }
        
        guard let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
            print("⚠️ Could not find window for screenshot")
            return
        }
        
        // Capture the screenshot
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        
        capturedScreenshot = image
        print("📸 Screenshot captured: \(image.size)")
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
        
        print("🔄 Fetching all bug reports...")
        
        // Check authentication first
        let isAuthenticated = SupabaseManager.shared.currentUser != nil
        print("🔐 Authentication status: \(isAuthenticated ? "✅ Authenticated" : "❌ Not authenticated")")
        
        if !isAuthenticated {
            let errorMessage = "Not authenticated. Please sign in to view bug reports."
            print("❌ \(errorMessage)")
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
            print("🐛 Loaded \(reports.count) bug reports")
            
            if reports.isEmpty {
                print("ℹ️ No bug reports found in database")
            }
            
            for report in reports {
                print("  - Bug ID: \(report.id), Status: \(report.status), Created: \(report.createdAt)")
            }
        } catch {
            let errorMessage = "Error fetching bug reports: \(error.localizedDescription)"
            print("❌ \(errorMessage)")
            print("❌ Error details: \(String(describing: error))")
            
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
                        print("📸 Screenshot size: \(base64.count) chars")
                    } else {
                        print("⚠️ Screenshot too large (\(base64.count) chars), skipping")
                    }
                }
            }
            
            // Get device info
            let device = UIDevice.current
            let deviceModel = getDeviceModel()
            let osVersion = "\(device.systemName) \(device.systemVersion)"
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            
            // Get user ID and name
            let userIdString: String
            let userName: String?
            if let userId = SupabaseManager.shared.currentUser?.id {
                userIdString = userId.uuidString
                // Get user name from UserManager
                userName = UserManager.shared.currentUser?.name
            } else {
                userIdString = "anonymous"
                userName = nil
            }
            
            // Create the report using the Codable struct
            let report = BugReportInsert(
                id: UUID(),
                userId: SupabaseManager.shared.currentUser?.id,
                userName: userName,
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
            
            print("📤 Submitting bug report to Supabase...")
            print("  - Description: \(description.prefix(50))...")
            print("  - Has screenshot: \(screenshotBase64 != nil)")
            print("  - User ID: \(userIdString)")
            print("  - User Name: \(userName ?? "anonymous")")
            
            // Insert using Codable struct
            let response = try await SupabaseManager.shared.supabaseClient
                .from("bug_reports")
                .insert(report)
                .execute()
            
            print("✅ Bug report submitted successfully!")
            print("  - Response status: \(response.status)")
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            return true
        } catch {
            print("❌ Error submitting bug report: \(error)")
            print("❌ Error type: \(type(of: error))")
            if let localizedError = error as? LocalizedError {
                print("❌ Error description: \(localizedError.errorDescription ?? "none")")
                print("❌ Failure reason: \(localizedError.failureReason ?? "none")")
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
            print("🗑️ Bug report deleted: \(id)")
            return true
        } catch {
            print("❌ Error deleting bug report: \(error)")
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
            print("✅ Bug status updated to: \(status)")
            return true
        } catch {
            print("❌ Error updating bug status: \(error)")
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
            print("📳 Shake detected in window!")
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
            print("📳 Shake detected via UIWindow extension!")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.becomeFirstResponder()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.becomeFirstResponder()
        }
    }
    
    override func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionBegan(motion, with: event)
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            print("📳 Shake detected!")
            Task { @MainActor in
                ShakeDetectionManager.shared.handleShake()
            }
        }
        super.motionEnded(motion, with: event)
    }
}

