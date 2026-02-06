import Foundation
import UIKit
import UserNotifications

/// Service for managing push notifications and device token registration
@MainActor
class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()
    
    @Published var deviceToken: String?
    @Published var isRegistered = false
    
    private init() {}
    
    // MARK: - Register for Push Notifications
    
    /// Request push notification permissions and register with APNs
    func registerForPushNotifications() async {
        // First, request notification authorization
        let granted = await NotificationManager.shared.requestAuthorization()
        
        if !granted {
            print("⚠️ [PUSH] Notification permission not granted via prompt")
            // Don't return early - check if user enabled in Settings later
        }
        
        // Always check current authorization status (user might have enabled in Settings)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        guard settings.authorizationStatus == .authorized || 
              settings.authorizationStatus == .provisional else {
            print("❌ [PUSH] Notifications not authorized (status: \(settings.authorizationStatus.rawValue))")
            return
        }
        
        // Register with APNs - this will trigger handleDeviceToken on success
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
            print("📱 [PUSH] Registered for remote notifications")
        }
    }
    
    /// Re-check and register if user enabled notifications after initial denial
    /// Call this on app foreground to catch Settings changes
    func recheckAndRegister() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        if settings.authorizationStatus == .authorized || 
           settings.authorizationStatus == .provisional {
            // User has notifications enabled, make sure we're registered
            if deviceToken == nil {
                print("📱 [PUSH] Notifications enabled but no token - registering...")
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    // MARK: - Handle Device Token
    
    /// Called when APNs returns the device token
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        self.isRegistered = true
        
        print("✅ [PUSH] Device token received: \(tokenString.prefix(20))...")
        
        // Store token in Supabase
        Task {
            await saveDeviceTokenToSupabase(tokenString)
        }
    }
    
    /// Called when APNs registration fails
    func handleRegistrationError(_ error: Error) {
        print("❌ [PUSH] Failed to register: \(error.localizedDescription)")
        self.isRegistered = false
    }
    
    // MARK: - Supabase Integration
    
    /// Save device token to Supabase for push notifications
    private func saveDeviceTokenToSupabase(_ token: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [PUSH] No user logged in, skipping token save")
            return
        }
        
        do {
            // Upsert the device token (insert or update if exists)
            struct DeviceTokenRecord: Encodable {
                let user_id: String
                let device_token: String
                let platform: String
                let app_version: String
                let is_valid: Bool
                let apns_environment: String
                let updated_at: String
            }
            
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            
            // Detect APNs environment: TestFlight/App Store = production, Xcode = development
            let apnsEnvironment = Self.detectAPNsEnvironment()
            print("📱 [PUSH] Detected APNs environment: \(apnsEnvironment)")
            
            let record = DeviceTokenRecord(
                user_id: userId.uuidString,
                device_token: token,
                platform: "ios",
                app_version: appVersion,
                is_valid: true,  // Reset to valid when user opens app with fresh token
                apns_environment: apnsEnvironment,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            
            try await SupabaseManager.shared.supabaseClient
                .from("user_push_tokens")
                .upsert(record, onConflict: "user_id")
                .execute()
            
            print("✅ [PUSH] Device token saved to Supabase (env: \(apnsEnvironment))")
            
            // Store locally for reference
            UserDefaults.standard.set(token, forKey: "apns_device_token")
            UserDefaults.standard.set(apnsEnvironment, forKey: "apns_environment")
            
        } catch {
            print("❌ [PUSH] Failed to save token: \(error)")
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
    
    /// Remove device token from Supabase (call on logout)
    func removeDeviceToken() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_push_tokens")
                .delete()
                .eq("user_id", value: userId)
                .execute()
            
            self.deviceToken = nil
            self.isRegistered = false
            UserDefaults.standard.removeObject(forKey: "apns_device_token")
            
            print("✅ [PUSH] Device token removed from Supabase")
        } catch {
            print("❌ [PUSH] Failed to remove token: \(error)")
        }
    }
}
