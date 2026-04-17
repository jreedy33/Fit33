import SwiftUI
import Foundation

/// Manages user privacy preferences with UserDefaults-first storage and Supabase cloud sync.
/// Pattern mirrors UnitSettingsManager: local reads are instant, cloud sync is debounced.
class PrivacySettingsManager: ObservableObject {
    static let shared = PrivacySettingsManager()
    
    // MARK: - UserDefaults Keys
    
    private enum Keys {
        static let hideProfilePhoto = "privacy_hide_profile_photo"
        static let hideFriendActivity = "privacy_hide_friend_activity"
        static let hideFromWeeklyLeague = "privacy_hide_from_weekly_league"
        static let hideFromContactSync = "privacy_hide_from_contact_sync"
        static let hideFromSearch = "privacy_hide_from_search"
        static let hideActiveStatus = "privacy_hide_active_status"
    }
    
    // MARK: - Published Properties
    
    @Published var hideProfilePhoto: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideProfilePhoto, forKey: Keys.hideProfilePhoto)
            syncToCloud()
        }
    }
    
    @Published var hideFriendActivity: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideFriendActivity, forKey: Keys.hideFriendActivity)
            syncToCloud()
        }
    }
    
    @Published var hideFromWeeklyLeague: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideFromWeeklyLeague, forKey: Keys.hideFromWeeklyLeague)
            syncToCloud()
        }
    }
    
    @Published var hideFromContactSync: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideFromContactSync, forKey: Keys.hideFromContactSync)
            syncToCloud()
        }
    }
    
    @Published var hideFromSearch: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideFromSearch, forKey: Keys.hideFromSearch)
            syncToCloud()
        }
    }
    
    @Published var hideActiveStatus: Bool {
        didSet {
            guard !isSyncingFromCloud else { return }
            UserDefaults.standard.set(hideActiveStatus, forKey: Keys.hideActiveStatus)
            syncToCloud()
        }
    }
    
    private var isSyncingFromCloud = false
    
    // MARK: - Initialization
    
    private init() {
        self.hideProfilePhoto = UserDefaults.standard.bool(forKey: Keys.hideProfilePhoto)
        self.hideFriendActivity = UserDefaults.standard.bool(forKey: Keys.hideFriendActivity)
        self.hideFromWeeklyLeague = UserDefaults.standard.bool(forKey: Keys.hideFromWeeklyLeague)
        self.hideFromContactSync = UserDefaults.standard.bool(forKey: Keys.hideFromContactSync)
        self.hideFromSearch = UserDefaults.standard.bool(forKey: Keys.hideFromSearch)
        self.hideActiveStatus = UserDefaults.standard.bool(forKey: Keys.hideActiveStatus)
    }
    
    // MARK: - Cloud Sync
    
    private func syncToCloud() {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await performCloudSync()
        }
    }
    
    private func performCloudSync() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        struct PrivacyUpdate: Encodable {
            let privacy_hide_photo: Bool
            let privacy_hide_activity: Bool
            let privacy_hide_league: Bool
            let privacy_hide_contact_sync: Bool
            let privacy_hide_search: Bool
            let privacy_hide_active_status: Bool
            let updated_at: String
        }
        
        let update = PrivacyUpdate(
            privacy_hide_photo: hideProfilePhoto,
            privacy_hide_activity: hideFriendActivity,
            privacy_hide_league: hideFromWeeklyLeague,
            privacy_hide_contact_sync: hideFromContactSync,
            privacy_hide_search: hideFromSearch,
            privacy_hide_active_status: hideActiveStatus,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()
            AppLogger.debug("[PRIVACY] Synced privacy settings to cloud", category: .general)
        } catch {
            AppLogger.warning("[PRIVACY] Failed to sync to cloud: \(error.localizedDescription)", category: .general)
        }
    }
    
    /// Load privacy preferences from cloud profile (called during login sync)
    func loadFromCloud(
        hidePhoto: Bool?,
        hideActivity: Bool?,
        hideLeague: Bool?,
        hideContactSync: Bool?,
        hideSearch: Bool?,
        hideActiveStatus: Bool?
    ) {
        isSyncingFromCloud = true
        defer { isSyncingFromCloud = false }
        
        if let val = hidePhoto {
            self.hideProfilePhoto = val
            UserDefaults.standard.set(val, forKey: Keys.hideProfilePhoto)
        }
        if let val = hideActivity {
            self.hideFriendActivity = val
            UserDefaults.standard.set(val, forKey: Keys.hideFriendActivity)
        }
        if let val = hideLeague {
            self.hideFromWeeklyLeague = val
            UserDefaults.standard.set(val, forKey: Keys.hideFromWeeklyLeague)
        }
        if let val = hideContactSync {
            self.hideFromContactSync = val
            UserDefaults.standard.set(val, forKey: Keys.hideFromContactSync)
        }
        if let val = hideSearch {
            self.hideFromSearch = val
            UserDefaults.standard.set(val, forKey: Keys.hideFromSearch)
        }
        if let val = hideActiveStatus {
            self.hideActiveStatus = val
            UserDefaults.standard.set(val, forKey: Keys.hideActiveStatus)
        }
    }
    
    /// Reset all privacy settings to defaults (everything visible)
    func resetToDefaults() {
        hideProfilePhoto = false
        hideFriendActivity = false
        hideFromWeeklyLeague = false
        hideFromContactSync = false
        hideFromSearch = false
        hideActiveStatus = false
    }
}
