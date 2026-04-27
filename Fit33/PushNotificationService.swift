import Foundation
import UIKit
import UserNotifications
import Supabase

/// Service for managing push notifications and device token registration
@MainActor
class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var deviceToken: String?
    @Published var isRegistered = false
    private let logger = SessionLogManager.shared
    
    private struct FlushResponse: Decodable {
        let message: String?
        let processed: Int?
        let success: Int?
        let failed: Int?
    }
    
    private init() {}
    
    // MARK: - Flush Push Notification Queue
    
    /// Triggers the send-push-notification edge function to process pending notifications.
    /// Call after any RPC that inserts into push_notification_queue.
    /// Fire-and-forget — failures are logged but don't block the caller.
    func flushPushNotificationQueue(triggeredBy source: String) {
        Task {
            await _flushQueue(source: source)
        }
    }
    
    func _flushQueue(source: String) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.log(.info, category: .pushNotification, message: "Flushing push queue", metadata: [
            "trigger": source
        ])
        AppLogger.debug("[PUSH] Flushing notification queue (trigger: \(source))", category: .network)
        
        do {
            let response: FlushResponse = try await SupabaseManager.shared.supabaseClient
                .functions
                .invoke(
                    "send-push-notification",
                    options: FunctionInvokeOptions(
                        body: ["batch": true]
                    )
                )
            
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            logFlushSuccess(response, source: source, elapsedMs: elapsedMs)
        } catch {
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let errorString = String(describing: error)
            let is401 = errorString.contains("401")
                || errorString.contains("non-2xx")
                || error.localizedDescription.contains("401")
            
            if is401 {
                AppLogger.warning("[PUSH] Auth expired after \(elapsedMs)ms, refreshing session and retrying (trigger: \(source))", category: .network)
                do {
                    try await SupabaseManager.shared.supabaseClient.auth.refreshSession()
                    let retryStart = CFAbsoluteTimeGetCurrent()
                    let retryResponse: FlushResponse = try await SupabaseManager.shared.supabaseClient
                        .functions
                        .invoke(
                            "send-push-notification",
                            options: FunctionInvokeOptions(body: ["batch": true])
                        )
                    let retryMs = Int((CFAbsoluteTimeGetCurrent() - retryStart) * 1000)
                    logFlushSuccess(retryResponse, source: "\(source)_retry", elapsedMs: retryMs)
                    return
                } catch let retryError {
                    let retryErrorFull = String(describing: retryError)
                    logger.log(.error, category: .pushNotification, message: "Push queue flush RETRY FAILED", metadata: [
                        "trigger": source,
                        "error": retryError.localizedDescription,
                        "error_full": String(retryErrorFull.prefix(500))
                    ])
                    AppLogger.error("[PUSH] Retry failed (trigger: \(source)): \(retryError.localizedDescription)", category: .network)
                }
            }
            
            logger.log(.error, category: .pushNotification, message: "Push queue flush FAILED", metadata: [
                "trigger": source,
                "elapsed_ms": "\(elapsedMs)",
                "error": error.localizedDescription,
                "error_type": String(describing: type(of: error)),
                "error_full": String(errorString.prefix(500))
            ])
            // Bug-intel ecca580f (2026-04-27): replace bare AppLogger.error with
            // NetworkErrorClassifier so transient 5xx (especially 503 from
            // process_push_notification_queue edge function) classify as
            // .warning instead of crash-fingerprinting at error level.
            // See QUALITY_PERFORMANCE_AGENT invariant 25a.
            _ = NetworkErrorClassifier.log(
                error,
                context: "[PUSH] Queue flush failed after \(elapsedMs)ms (trigger: \(source))",
                category: .network,
                transientLevel: .warning,
                op: "push.queue_flush",
                endpoint: "functions/send-push-notification"
            )
        }
    }
    
    private func logFlushSuccess(_ response: FlushResponse, source: String, elapsedMs: Int = 0) {
        let processed = response.processed ?? 0
        let succeeded = response.success ?? 0
        let failed = response.failed ?? 0
        
        logger.log(.info, category: .pushNotification, message: "Push queue flushed", metadata: [
            "trigger": source,
            "processed": "\(processed)",
            "succeeded": "\(succeeded)",
            "failed": "\(failed)",
            "elapsed_ms": "\(elapsedMs)"
        ])
        AppLogger.info("[PUSH] Queue flushed in \(elapsedMs)ms: \(processed) processed, \(succeeded) sent, \(failed) failed (trigger: \(source))", category: .network)
    }
    
    // MARK: - Register for Push Notifications
    
    /// Request push notification permissions and register with APNs
    func registerForPushNotifications() async {
        // First, request notification authorization
        let granted = await NotificationManager.shared.requestAuthorization()
        
        if !granted {
            AppLogger.warning("⚠️ [PUSH] Notification permission not granted via prompt", category: .network)
            // Don't return early - check if user enabled in Settings later
        }
        
        // Always check current authorization status (user might have enabled in Settings)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        guard settings.authorizationStatus == .authorized || 
              settings.authorizationStatus == .provisional else {
            AppLogger.info("[PUSH] Notifications not authorized (status: \(settings.authorizationStatus.rawValue))", category: .network)
            return
        }
        
        // Register with APNs - this will trigger handleDeviceToken on success
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
            AppLogger.debug("📱 [PUSH] Registered for remote notifications", category: .network)
        }
    }
    
    /// Re-check and ALWAYS re-register on app foreground
    /// APNs can rotate tokens at any time — calling registerForRemoteNotifications()
    /// either returns the same token (no-op) or a fresh one that gets saved to Supabase
    func recheckAndRegister() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        if settings.authorizationStatus == .authorized || 
           settings.authorizationStatus == .provisional {
            // ALWAYS re-register — APNs will return current valid token
            // This ensures stale/rotated tokens get refreshed automatically
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            if deviceToken == nil {
                AppLogger.debug("📱 [PUSH] Notifications enabled but no token yet - waiting for APNs callback...", category: .network)
            }
        }
    }
    
    // MARK: - Handle Device Token
    
    /// Called when APNs returns the device token
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        let isNewToken = self.deviceToken != tokenString
        self.deviceToken = tokenString
        self.isRegistered = true
        
        if isNewToken {
            AppLogger.info("✅ [PUSH] Device token received: \(tokenString.prefix(20))...", category: .network)
            Task {
                await saveDeviceTokenToSupabase(tokenString)
            }
        }
    }
    
    /// Called when APNs registration fails
    func handleRegistrationError(_ error: Error) {
        AppLogger.error("❌ [PUSH] Failed to register: \(error.localizedDescription)", category: .network)
        self.isRegistered = false
    }
    
    // MARK: - Supabase Integration
    
    /// Save device token to Supabase for push notifications
    private func saveDeviceTokenToSupabase(_ token: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [PUSH] No user logged in, skipping token save", category: .network)
            return
        }
        
        struct DeviceTokenRecord: Encodable {
            let user_id: UUID
            let device_token: String
            let platform: String
            let app_version: String
            let is_valid: Bool
            let apns_environment: String
            let updated_at: String
        }
        
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let apnsEnvironment = Self.detectAPNsEnvironment()
        AppLogger.debug("📱 [PUSH] Detected APNs environment: \(apnsEnvironment)", category: .network)
        
        let record = DeviceTokenRecord(
            user_id: userId,
            device_token: token,
            platform: "ios",
            app_version: appVersion,
            is_valid: true,
            apns_environment: apnsEnvironment,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("user_push_tokens")
                    .upsert(record, onConflict: "user_id, device_token")
                    .execute()
                
                AppLogger.info("✅ [PUSH] Device token saved to Supabase (env: \(apnsEnvironment))", category: .network)
                
                UserDefaults.standard.set(token, forKey: "apns_device_token")
                UserDefaults.standard.set(apnsEnvironment, forKey: "apns_environment")
                return
            } catch {
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                if isTimeout && attempt < maxAttempts {
                    AppLogger.warning("❌ [PUSH] Token save timeout (attempt \(attempt)/\(maxAttempts)), retrying...", category: .network)
                    try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                } else if isTimeout {
                    AppLogger.warning("❌ [PUSH] Failed to save token: \(error)", category: .network)
                } else {
                    AppLogger.error("❌ [PUSH] Failed to save token: \(error)", category: .network)
                }
            }
        }
    }
    
    // MARK: - APNs Environment Detection
    
    /// Detect whether app is running with sandbox (development) or production APNs
    /// - TestFlight and App Store builds use production APNs
    /// - Xcode/Debug builds use sandbox APNs
    private static func detectAPNsEnvironment() -> String {
        #if DEBUG
        // Debug builds always use sandbox
        return "development"
        #else
        // Release builds: check if it's TestFlight or App Store
        // TestFlight receipts are in a different location than App Store
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            // TestFlight receipts contain "sandboxReceipt" in the path
            // But both TestFlight and App Store use PRODUCTION APNs
            if receiptURL.lastPathComponent == "sandboxReceipt" {
                // This is TestFlight - uses PRODUCTION APNs (not sandbox!)
                return "production"
            } else {
                // App Store
                return "production"
            }
        }
        // Fallback to production for release builds
        return "production"
        #endif
    }
    
    // MARK: - Foreground Health Check
    
    /// Call on app foreground after a delay. Logs a warning if we still have no device token.
    func performTokenHealthCheck() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard deviceToken == nil else { return }
            
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authStatus: String
            switch settings.authorizationStatus {
            case .authorized: authStatus = "authorized"
            case .denied: authStatus = "denied"
            case .notDetermined: authStatus = "not_determined"
            case .provisional: authStatus = "provisional"
            case .ephemeral: authStatus = "ephemeral"
            @unknown default: authStatus = "unknown(\(settings.authorizationStatus.rawValue))"
            }
            
            logger.log(.warning, category: .pushNotification, message: "No device token 10s after foreground", metadata: [
                "auth_status": authStatus,
                "is_registered": "\(isRegistered)",
                "has_saved_token": "\(UserDefaults.standard.string(forKey: "apns_device_token") != nil)"
            ])
            AppLogger.warning("[PUSH] Health check: no device token after 10s (auth=\(authStatus), registered=\(isRegistered))", category: .network)
        }
    }
    
    // MARK: - Diagnostics RPC
    
    struct DiagnosticReport: Decodable {
        let user_id: String?
        let diagnosed_at: String?
        let tokens: [[String: AnyCodable]]?
        let preferences: [String: AnyCodable]?
        let queue_stats: [String: AnyCodable]?
        let recent_queue: [[String: AnyCodable]]?
        let recent_delivery_logs: [[String: AnyCodable]]?
        let error: String?
    }
    
    /// Calls the server-side diagnose_push_notifications() RPC for a full health report.
    func runDiagnostics() async -> DiagnosticReport? {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[PUSH] Cannot run diagnostics - not authenticated", category: .network)
            return nil
        }
        
        do {
            let report: DiagnosticReport = try await SupabaseManager.shared.supabaseClient
                .rpc("diagnose_push_notifications")
                .execute()
                .value
            
            AppLogger.info("[PUSH] Diagnostics report received", category: .network)
            return report
        } catch {
            AppLogger.error("[PUSH] Diagnostics RPC failed: \(error.localizedDescription)", category: .network)
            return nil
        }
    }
    
    /// Remove device token from Supabase (call on logout)
    func removeDeviceToken() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        guard let token = deviceToken ?? UserDefaults.standard.string(forKey: "apns_device_token") else { return }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_push_tokens")
                .delete()
                .eq("user_id", value: userId)
                .eq("device_token", value: token)
                .execute()
            
            self.deviceToken = nil
            self.isRegistered = false
            UserDefaults.standard.removeObject(forKey: "apns_device_token")
            
            logger.log(.info, category: .pushNotification, message: "Device token removed (sign-out)")
            AppLogger.info("[PUSH] Device token removed from Supabase", category: .network)
        } catch {
            logger.log(.error, category: .pushNotification, message: "Failed to remove device token", metadata: ["error": error.localizedDescription])
            AppLogger.error("[PUSH] Failed to remove token: \(error)", category: .network)
        }
    }
}
