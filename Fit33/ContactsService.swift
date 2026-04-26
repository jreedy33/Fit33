import Foundation
import Contacts
import SwiftUI
import Supabase
import CommonCrypto

// MARK: - Contacts Service
/// Manages contact access and finds friends from user's contact list

@MainActor
class ContactsService: ObservableObject {
    static let shared = ContactsService()
    
    @Published var authorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var contactEmails: [String] = []
    @Published var contactPhoneNumbers: [String] = []
    @Published var suggestedFriends: [SuggestedFriend] = []
    @Published var peopleYouMayKnow: [SuggestedFriend] = [] // Friends-of-friends
    @Published var isLoading = false
    @Published var hasCheckedContacts = false
    
    private let store = CNContactStore()
    private var lastRefreshDate: Date?
    private static let refreshThrottleInterval: TimeInterval = 300
    
    private static let suggestedFriendsCacheKey = "cached_suggested_friends_v1"
    private static let pymkCacheKey = "cached_pymk_v1"
    
    /// Prevents redundant network fetches within a single app session.
    /// Reset only by pull-to-refresh (force).
    private(set) var hasRefreshedSuggestionsThisSession = false
    
    /// Cross-session TTL for contact-match refresh. Hashing 2000+ phone numbers
    /// + RPC match + DB upsert is expensive (~2-3s wall clock, observed 10fps
    /// sustained scroll drop in 1.38 (53) session logs). Contact membership
    /// doesn't change hour-to-hour, so we only need to re-run the heavy path
    /// every 6 hours. Pull-to-refresh still bypasses this via `refreshSuggestions(force: true)`.
    private static let suggestionsRefreshTTL: TimeInterval = 6 * 60 * 60
    private static let lastSuggestionsRefreshKey = "contacts.last_suggestions_refresh_v1"
    
    private init() {
        checkAuthorizationStatus()
        // ⚡️ Cold-start Phase 4: prefer pre-decoded caches from
        // StartupCachePreloader (decoded on bg before init runs on main).
        let pre = StartupCachePreloader.consumeContactsSuggestions()
        if let cachedContacts = pre.contacts {
            suggestedFriends = cachedContacts
            if !cachedContacts.isEmpty { hasCheckedContacts = true }
        }
        if let cachedPYMK = pre.pymk {
            peopleYouMayKnow = cachedPYMK
        }
        if pre.contacts == nil && pre.pymk == nil {
            loadCachedSuggestions()
        } else {
            AppLogger.debug("Loaded cached suggestions: \(suggestedFriends.count) contacts, \(peopleYouMayKnow.count) PYMK (pre-decoded)", category: .social)
        }
    }
    
    // MARK: - Persistent Cache
    
    private func loadCachedSuggestions() {
        if let data = UserDefaults.standard.data(forKey: Self.suggestedFriendsCacheKey),
           let cached = try? JSONDecoder().decode([SuggestedFriend].self, from: data) {
            suggestedFriends = cached
            if !cached.isEmpty { hasCheckedContacts = true }
        }
        if let data = UserDefaults.standard.data(forKey: Self.pymkCacheKey),
           let cached = try? JSONDecoder().decode([SuggestedFriend].self, from: data) {
            peopleYouMayKnow = cached
        }
        AppLogger.debug("Loaded cached suggestions: \(suggestedFriends.count) contacts, \(peopleYouMayKnow.count) PYMK", category: .social)
    }
    
    private func saveSuggestedFriendsToCache() {
        if let data = try? JSONEncoder().encode(suggestedFriends) {
            UserDefaults.standard.set(data, forKey: Self.suggestedFriendsCacheKey)
        }
    }
    
    private func savePYMKToCache() {
        if let data = try? JSONEncoder().encode(peopleYouMayKnow) {
            UserDefaults.standard.set(data, forKey: Self.pymkCacheKey)
        }
    }
    
    /// Refresh contacts + PYMK in the background. Gated by:
    ///   (a) In-session flag — prevents repeat calls within the same app launch
    ///   (b) Cross-session TTL (6h) — skips the heavy contact-hash path even on
    ///       cold start when we refreshed recently. PYMK still runs (lightweight
    ///       RPC) because friends-of-friends DOES change hour-to-hour.
    ///
    /// Pull-to-refresh bypasses both gates via `refreshSuggestions(force: true)`
    /// elsewhere, or via the force path on Friends tab batch-3.
    func refreshSuggestionsIfNeeded() async {
        guard !hasRefreshedSuggestionsThisSession else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }
        hasRefreshedSuggestionsThisSession = true
        
        // Cross-session TTL gate for the heavy contact-hash path.
        let lastRefresh = UserDefaults.standard.double(forKey: Self.lastSuggestionsRefreshKey)
        let secondsSinceLastRefresh = Date().timeIntervalSince1970 - lastRefresh
        let contactsPathFresh = lastRefresh > 0 && secondsSinceLastRefresh < Self.suggestionsRefreshTTL
        
        async let pymk: () = fetchPeopleYouMayKnow()
        if canAccessContacts && !contactsPathFresh {
            async let contacts: () = fetchContactsAndFindFriends()
            _ = await (pymk, contacts)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSuggestionsRefreshKey)
        } else {
            if contactsPathFresh {
                AppLogger.debug("Skipping contact refresh — last ran \(Int(secondsSinceLastRefresh))s ago (TTL 6h)", category: .social)
            }
            _ = await pymk
        }
    }
    
    // MARK: - Authorization
    
    func checkAuthorizationStatus() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }
    
    var canAccessContacts: Bool {
        authorizationStatus == .authorized
    }
    
    var shouldShowPermissionPrompt: Bool {
        authorizationStatus == .notDetermined
    }
    
    var permissionDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }
    
    /// Request contact access permission
    func requestAccess() async -> Bool {
        AppLogger.debug("requestAccess() called", category: .social)
        do {
            let granted = try await store.requestAccess(for: .contacts)
            checkAuthorizationStatus()
            AppLogger.debug("Authorization status after request: \(authorizationStatus.rawValue)", category: .social)
            
            if granted {
                AppLogger.info("Access granted - now fetching contacts and finding friends...", category: .social)
                await fetchContactsAndFindFriends()
                AppLogger.info("Fetch complete - suggestedFriends: \(suggestedFriends.count)", category: .social)
            } else {
                AppLogger.error("Access denied by user", category: .social)
            }
            
            return granted
        } catch {
            AppLogger.error("Error requesting access: \(error.localizedDescription)", category: .social)
            checkAuthorizationStatus()
            return false
        }
    }
    
    // MARK: - Fetch Contacts
    
    /// Fetch contacts and find matching app users
    func fetchContactsAndFindFriends() async {
        AppLogger.debug("Starting fetchContactsAndFindFriends...", category: .social)
        
        guard canAccessContacts else {
            AppLogger.warning("No access to contacts - aborting", category: .social)
            return
        }
        
        isLoading = true
        defer { 
            isLoading = false
        }
        
        // Step 1: Fetch contact emails and phone numbers from device
        AppLogger.debug("Step 1: Fetching contact info from device...", category: .social)
        await fetchContactInfo()
        AppLogger.debug("Fetched \(contactPhoneNumbers.count) phones, \(contactEmails.count) emails", category: .social)
        
        // Step 2: Find matching users in the app database
        AppLogger.debug("Step 2: Finding matching Fit33 users...", category: .social)
        await findMatchingUsers()
        AppLogger.debug("Found \(suggestedFriends.count) Fit33 users in contacts", category: .social)
        
        // Step 3: Sync contacts to database for "contact joined" notifications
        AppLogger.debug("Step 3: Syncing contacts to database...", category: .social)
        await syncContactsToDatabase()
        AppLogger.debug("Contacts synced for future notifications", category: .social)
        
        hasCheckedContacts = true
        AppLogger.info("fetchContactsAndFindFriends complete!", category: .social)
    }
    
    private func fetchContactInfo() async {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        let contactStore = self.store // Capture on main thread — CNContactStore is thread-safe
        
        // ⚡️ FIX: enumerateContacts() is a SYNCHRONOUS blocking call.
        // Because ContactsService is @MainActor, it was running on the main thread
        // and blocking the UI for the entire contact scan (30+ seconds on large lists).
        // Moving it to a background queue prevents the deadlock / freeze.
        let result: (emails: [String], phones: [String]) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var emails: Set<String> = []
                var phones: Set<String> = []
                
                do {
                    try contactStore.enumerateContacts(with: request) { contact, _ in
                        // Collect emails (lowercase for matching)
                        for email in contact.emailAddresses {
                            let emailString = (email.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                            if !emailString.isEmpty {
                                emails.insert(emailString)
                            }
                        }
                        
                        // Collect phone numbers (E.164-aware normalization)
                        for phone in contact.phoneNumbers {
                            let raw = phone.value.stringValue
                            let hasPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
                            let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                            guard !digits.isEmpty else { continue }
                            
                            if hasPlus {
                                phones.insert("+\(digits)")
                            } else if digits.count > 10 {
                                phones.insert("+\(digits)")
                            } else if digits.count == 10 {
                                phones.insert("+1\(digits)")
                                phones.insert(digits)
                            } else {
                                phones.insert(digits)
                            }
                        }
                    }
                } catch {
                    AppLogger.error("Error fetching contacts: \(error.localizedDescription)", category: .social)
                }
                
                continuation.resume(returning: (emails: Array(emails), phones: Array(phones)))
            }
        }
        
        // Back on @MainActor — safe to update @Published properties
        contactEmails = result.emails
        contactPhoneNumbers = result.phones
        AppLogger.debug("Found \(result.emails.count) emails and \(result.phones.count) phone numbers", category: .social)
    }
    
    /// Normalize phone number to E.164 format where possible
    nonisolated private func normalizePhoneNumber(_ phone: String) -> String {
        let raw = phone.trimmingCharacters(in: .whitespaces)
        let hasPlus = raw.hasPrefix("+")
        let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        if hasPlus {
            return "+\(digits)"
        } else if digits.count > 10 {
            return "+\(digits)"
        } else if digits.count == 10 {
            return "+1\(digits)"
        }
        return digits
    }
    
    // MARK: - Find Matching Users
    
    private func findMatchingUsers() async {
        guard !contactEmails.isEmpty || !contactPhoneNumbers.isEmpty else {
            AppLogger.warning("No contact emails or phone numbers to search", category: .social)
            return
        }
        
        // Log sample emails for debugging (first 5, truncated)
        let sampleEmails = contactEmails.prefix(5).map { email in
            let parts = email.split(separator: "@")
            if parts.count == 2 {
                return "\(parts[0].prefix(3))...@\(parts[1])"
            }
            return "\(email.prefix(6))..."
        }
        
        // Log sample phones for debugging (first 5, partially hidden)
        let samplePhones = contactPhoneNumbers.prefix(5).map { phone in
            if phone.count >= 6 {
                return "***\(phone.suffix(4))"
            }
            return "***"
        }
        
        AppLogger.debug("Searching for matching Fit33 users... Emails: \(contactEmails.count) (sample: \(sampleEmails.joined(separator: ", "))), Phone numbers: \(contactPhoneNumbers.count) (sample: \(samplePhones.joined(separator: ", ")))", category: .social)
        AppLogger.debug("First 10 full normalized phones: \(Array(contactPhoneNumbers.prefix(10)))", category: .social)
        
        // Use direct database query method - more reliable than RPC
        AppLogger.debug("Using direct database query for maximum reliability...", category: .social)
        await findMatchingUsersDirect()
    }
    
    private nonisolated func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_MD5(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func findMatchingUsersDirect() async {
        AppLogger.debug("Querying via RPC with hashed phones...", category: .social)
        
        do {
            guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
                AppLogger.warning("No current user ID", category: .social)
                return
            }
            
            var matchedUsers: [SuggestedFriend] = []
            
            if !contactEmails.isEmpty {
                struct EmailMatch: Decodable {
                    let id: UUID
                    let name: String?
                    let email: String?
                    let username: String?
                    let profile_photo_url: String?
                }
                
                let emailResults: [EmailMatch] = try await SupabaseManager.shared.supabaseClient
                    .from("user_profiles")
                    .select("id, name, email, username, profile_photo_url")
                    .in("email", values: contactEmails)
                    .neq("id", value: currentUserId.uuidString)
                    .execute()
                    .value
                
                for match in emailResults {
                    let friend = SuggestedFriend(
                        userId: match.id,
                        name: match.name,
                        email: match.email,
                        username: match.username,
                        profilePhotoUrl: match.profile_photo_url,
                        phoneNumber: nil,
                        fitnessGoal: nil,
                        isFriend: false,
                        hasOutgoingRequest: false,
                        hasIncomingRequest: false
                    )
                    matchedUsers.append(friend)
                }
                
                AppLogger.debug("Found \(emailResults.count) matches by email", category: .social)
            }
            
            if !contactPhoneNumbers.isEmpty {
                AppLogger.debug("Hashing \(contactPhoneNumbers.count) phone numbers for server-side matching...", category: .social)
                
                let phones = contactPhoneNumbers
                let hashedPhones = await Task.detached(priority: .utility) { [self] in
                    phones.map { self.md5Hash($0) }
                }.value
                
                struct PhoneMatch: Decodable {
                    let id: UUID
                    let name: String?
                    let username: String?
                    let profile_photo_url: String?
                }
                
                let phoneResults: [PhoneMatch] = try await SupabaseManager.shared.supabaseClient
                    .rpc("match_contacts_by_phone", params: ["phone_hashes": hashedPhones])
                    .execute()
                    .value
                
                for match in phoneResults {
                    if match.id == currentUserId { continue }
                    if matchedUsers.contains(where: { $0.userId == match.id }) { continue }
                    
                    let friend = SuggestedFriend(
                        userId: match.id,
                        name: match.name,
                        email: nil,
                        username: match.username,
                        profilePhotoUrl: match.profile_photo_url,
                        phoneNumber: nil,
                        fitnessGoal: nil,
                        isFriend: false,
                        hasOutgoingRequest: false,
                        hasIncomingRequest: false
                    )
                    matchedUsers.append(friend)
                }
                
                AppLogger.debug("Found \(phoneResults.count) matches by phone hash", category: .social)
            }
            
            suggestedFriends = matchedUsers
            saveSuggestedFriendsToCache()
            AppLogger.info("Total unique matches: \(matchedUsers.count)", category: .social)
            
            for friend in matchedUsers {
                AppLogger.debug("\(friend.displayName) (@\(friend.username ?? "no username"))", category: .social)
            }
        } catch {
            AppLogger.error("Query failed: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Refresh suggestions (call after adding a friend, or from dashboard)
    func refreshSuggestions(force: Bool = false) async {
        guard canAccessContacts && hasCheckedContacts else { return }
        if !force, let lastRefresh = lastRefreshDate,
           Date().timeIntervalSince(lastRefresh) < Self.refreshThrottleInterval {
            return
        }
        lastRefreshDate = Date()
        await findMatchingUsers()
    }
    
    // MARK: - People You May Know (Friends-of-Friends)
    
    /// Fetch friends-of-friends with mutual friend counts
    func fetchPeopleYouMayKnow() async {
        AppLogger.debug("Fetching people you may know...", category: .social)
        
        do {
            struct PYMKResult: Decodable {
                let user_id: UUID
                let name: String?
                let email: String?
                let username: String?
                let profile_photo_url: String?
                let phone_number: String?
                let fitness_goal: String?
                let is_friend: Bool
                let has_outgoing_request: Bool
                let has_incoming_request: Bool
                let mutual_friend_count: Int
            }
            
            let results: [PYMKResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_people_you_may_know", params: ["result_limit": 20])
                .execute()
                .value
            
            // Convert to SuggestedFriend with isMutual flag
            peopleYouMayKnow = results.map { r in
                SuggestedFriend(
                    userId: r.user_id,
                    name: r.name,
                    email: r.email,
                    username: r.username,
                    profilePhotoUrl: r.profile_photo_url,
                    phoneNumber: r.phone_number,
                    fitnessGoal: r.fitness_goal,
                    isFriend: r.is_friend,
                    hasOutgoingRequest: r.has_outgoing_request,
                    hasIncomingRequest: r.has_incoming_request,
                    mutualFriendCount: r.mutual_friend_count,
                    isMutual: true
                )
            }
            
            savePYMKToCache()
            AppLogger.info("Found \(peopleYouMayKnow.count) people you may know", category: .social)
            
            // Preload photos
            let photoEntries = peopleYouMayKnow.compactMap { friend -> (id: String, url: String?)? in
                return (id: friend.userId.uuidString, url: friend.profilePhotoUrl)
            }
            FriendPhotoCache.shared.preloadPhotos(for: photoEntries)
            
        } catch {
            AppLogger.warning("Error fetching people you may know: \(error.localizedDescription)", category: .social)
            // Non-fatal - just use contact suggestions
        }
    }
    
    /// Contact-only suggestions, enriched with mutual friend data for sorting.
    /// Only people in the user's contacts are shown — no random strangers.
    /// Contacts who are also mutual friends (friends-of-friends) get boosted to the top.
    func allSuggestions(excludingFriendIds friendIds: Set<UUID>, excludingSentIds sentIds: Set<UUID>) -> [SuggestedFriend] {
        let excludeIds = friendIds.union(sentIds)
        let blockedIds = FriendService.shared.blockedUserIds
        
        // Build a lookup of mutual friend counts from the friends-of-friends query
        let mutualCountByUserId = Dictionary(
            uniqueKeysWithValues: peopleYouMayKnow.map { ($0.userId, $0.mutualFriendCount ?? 0) }
        )
        
        let contacts = suggestedFriends.filter { suggestion in
            guard !excludeIds.contains(suggestion.userId) else { return false }
            guard !suggestion.isFriend else { return false }
            guard !blockedIds.contains(suggestion.userId) else { return false }
            return true
        }
        
        // Enrich each contact with mutual friend data
        let enriched: [SuggestedFriend] = contacts.map { contact in
            let mutualCount = mutualCountByUserId[contact.userId] ?? 0
            if mutualCount > 0 {
                // This contact is also a friend-of-a-friend — mark as mutual
                return SuggestedFriend(
                    userId: contact.userId,
                    name: contact.name,
                    email: contact.email,
                    username: contact.username,
                    profilePhotoUrl: contact.profilePhotoUrl,
                    phoneNumber: contact.phoneNumber,
                    fitnessGoal: contact.fitnessGoal,
                    isFriend: contact.isFriend,
                    hasOutgoingRequest: contact.hasOutgoingRequest,
                    hasIncomingRequest: contact.hasIncomingRequest,
                    mutualFriendCount: mutualCount,
                    isMutual: true
                )
            }
            return contact
        }
        
        // Sort: mutual contacts with photos → mutual contacts without photos → contacts with photos → contacts without
        return enriched.sorted { a, b in
            let aMutual = a.isMutual
            let bMutual = b.isMutual
            // Mutuals first
            if aMutual != bMutual { return aMutual }
            // Within same mutual tier: photos first
            if a.hasPhoto != b.hasPhoto { return a.hasPhoto }
            // Within same photo tier: higher mutual count first
            let aCount = a.mutualFriendCount ?? 0
            let bCount = b.mutualFriendCount ?? 0
            if aCount != bCount { return aCount > bCount }
            // Alphabetical fallback
            return (a.name ?? "") < (b.name ?? "")
        }
    }
    
    // MARK: - Sync Contacts to Database
    
    /// Sync contact emails to database for "contact joined" notifications
    func syncContactsToDatabase() async {
        guard !PrivacySettingsManager.shared.hideFromContactSync else {
            AppLogger.debug("[PRIVACY] Skipping contact sync — user has contact discoverability hidden", category: .social)
            return
        }
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("Cannot sync contacts - not authenticated", category: .social)
            return
        }
        guard canAccessContacts, !contactEmails.isEmpty else {
            AppLogger.warning("Cannot sync - no access or no emails", category: .social)
            return
        }
        
        do {
            struct SyncParams: Encodable {
                let p_contact_emails: [String]
            }
            
            let params = SyncParams(p_contact_emails: contactEmails)
            
            let _: Int = try await SupabaseManager.shared.supabaseClient
                .rpc("sync_user_contacts", params: params)
                .execute()
                .value
            
            AppLogger.info("Synced \(contactEmails.count) contacts to database", category: .social)
            
            // Check for any pending "contact joined" notifications
            await checkForContactJoinedNotifications()
        } catch {
            AppLogger.error("Error syncing contacts: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Check and send notifications for contacts who recently joined
    func checkForContactJoinedNotifications() async {
        do {
            let notifications: [ContactJoinedNotification] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_pending_contact_notifications")
                .execute()
                .value
            
            AppLogger.debug("Found \(notifications.count) pending contact joined notifications", category: .social)
            
            // Send push notification for each
            for notification in notifications {
                await sendContactJoinedPushNotification(notification)
            }
        } catch {
            AppLogger.error("Error checking contact notifications: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Send push notification that a contact joined
    private func sendContactJoinedPushNotification(_ notification: ContactJoinedNotification) async {
        let displayName = notification.newUserName ?? notification.newUserUsername ?? "Someone"
        
        // Send via NotificationManager
        await MainActor.run {
            NotificationManager.shared.sendContactJoinedNotification(
                contactName: displayName,
                newUserId: notification.newUserId.uuidString
            )
        }
        
        // Mark as sent in database
        do {
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("mark_contact_notification_sent", params: ["p_notification_id": notification.notificationId.uuidString])
                .execute()
                .value
            
            AppLogger.info("Marked notification sent for \(displayName)", category: .social)
        } catch {
            AppLogger.error("Error marking notification sent: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Trigger notification check when app becomes active (for testing - every instance)
    func triggerContactJoinedCheck() async {
        guard canAccessContacts else { return }
        
        // First ensure contacts are synced
        if contactEmails.isEmpty {
            await fetchContactInfo()
        }
        
        // Sync to database
        await syncContactsToDatabase()
    }
    
    // MARK: - Notify Existing Users When New User Joins
    
    /// Call this after a new user completes onboarding (phone verified, contacts synced, account created)
    /// This notifies existing Fit33 users who have the new user in their contacts.
    ///
    /// Bug-intelligence fingerprints b242269c / 65f3c668: this endpoint can return
    /// 403 "Forbidden: new_user_id must match caller" during the brief window
    /// between `auth.signUp` and the new JWT propagating to PostgREST. The daily
    /// `check_pending_join_notifications` cron catches up the missed contacts, so
    /// the failure is recoverable; we route through `NetworkErrorClassifier` and
    /// downgrade to `.debug` instead of fingerprinting it as a bug every signup.
    func notifyExistingUsersOfNewJoin() async {
        guard SupabaseManager.shared.isAuthenticated,
              let newUserId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.debug("[CONTACTS] Skipping join-notify — not authenticated yet (cron will catch up)", category: .social)
            return
        }

        AppLogger.debug("Notifying existing users that \(newUserId) joined Fit33...", category: .social)

        do {
            // Call the edge function to queue push notifications
            struct NotifyResponse: Decodable {
                let message: String
                let notifications_queued: Int
                let new_user_name: String?
            }

            let response: NotifyResponse = try await SupabaseManager.shared.supabaseClient
                .functions
                .invoke(
                    "notify-contacts-user-joined",
                    options: FunctionInvokeOptions(
                        body: ["new_user_id": newUserId.uuidString]
                    )
                )

            AppLogger.info("Notified \(response.notifications_queued) existing users. Message: \(response.message)", category: .social)

        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "[CONTACTS] notify-contacts-user-joined invoke",
                category: .social,
                transientLevel: .debug,
                endpoint: "functions/notify-contacts-user-joined",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
}

// MARK: - Suggested Friend Model

struct SuggestedFriend: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let email: String?
    let username: String?
    let profilePhotoUrl: String?
    let phoneNumber: String?  // Add phone number for direct query
    let fitnessGoal: String?
    let isFriend: Bool
    let hasOutgoingRequest: Bool
    let hasIncomingRequest: Bool
    let mutualFriendCount: Int?
    var isMutual: Bool
    let isVerified: Bool?
    let isGoldVerified: Bool?

    var id: UUID { userId }
    
    var hasPhoto: Bool {
        profilePhotoUrl != nil && !(profilePhotoUrl?.isEmpty ?? true)
    }
    
    var displayName: String {
        if let username = username, !username.isEmpty {
            return "@\(username)"
        }
        return name ?? "Unknown"
    }
    
    var initials: String {
        if let name = name, !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        if let username = username, !username.isEmpty {
            return String(username.prefix(2)).uppercased()
        }
        return "?"
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case email
        case username
        case profilePhotoUrl = "profile_photo_url"
        case phoneNumber = "phone_number"
        case fitnessGoal = "fitness_goal"
        case isFriend = "is_friend"
        case hasOutgoingRequest = "has_outgoing_request"
        case hasIncomingRequest = "has_incoming_request"
        case mutualFriendCount = "mutual_friend_count"
        case isMutual = "is_mutual"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        profilePhotoUrl = try container.decodeIfPresent(String.self, forKey: .profilePhotoUrl)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        fitnessGoal = try container.decodeIfPresent(String.self, forKey: .fitnessGoal)
        isFriend = try container.decodeIfPresent(Bool.self, forKey: .isFriend) ?? false
        hasOutgoingRequest = try container.decodeIfPresent(Bool.self, forKey: .hasOutgoingRequest) ?? false
        hasIncomingRequest = try container.decodeIfPresent(Bool.self, forKey: .hasIncomingRequest) ?? false
        mutualFriendCount = try container.decodeIfPresent(Int.self, forKey: .mutualFriendCount)
        isMutual = try container.decodeIfPresent(Bool.self, forKey: .isMutual) ?? false
        isVerified = try container.decodeIfPresent(Bool.self, forKey: .isVerified)
        isGoldVerified = try container.decodeIfPresent(Bool.self, forKey: .isGoldVerified)
    }
    
    init(userId: UUID, name: String?, email: String?, username: String?, profilePhotoUrl: String?, phoneNumber: String?, fitnessGoal: String?, isFriend: Bool, hasOutgoingRequest: Bool, hasIncomingRequest: Bool, mutualFriendCount: Int? = nil, isMutual: Bool = false, isVerified: Bool? = nil, isGoldVerified: Bool? = nil) {
        self.userId = userId
        self.name = name
        self.email = email
        self.username = username
        self.profilePhotoUrl = profilePhotoUrl
        self.phoneNumber = phoneNumber
        self.fitnessGoal = fitnessGoal
        self.isFriend = isFriend
        self.hasOutgoingRequest = hasOutgoingRequest
        self.hasIncomingRequest = hasIncomingRequest
        self.mutualFriendCount = mutualFriendCount
        self.isMutual = isMutual
        self.isVerified = isVerified
        self.isGoldVerified = isGoldVerified
    }
}

// MARK: - Contact Joined Notification Model

struct ContactJoinedNotification: Codable, Identifiable {
    let notificationId: UUID
    let newUserId: UUID
    let newUserName: String?
    let newUserEmail: String?
    let newUserUsername: String?
    let newUserPhotoUrl: String?
    let createdAt: Date
    
    var id: UUID { notificationId }
    
    var displayName: String {
        if let name = newUserName, !name.isEmpty {
            return name
        }
        if let username = newUserUsername, !username.isEmpty {
            return "@\(username)"
        }
        return "Someone"
    }
    
    enum CodingKeys: String, CodingKey {
        case notificationId = "notification_id"
        case newUserId = "new_user_id"
        case newUserName = "new_user_name"
        case newUserEmail = "new_user_email"
        case newUserUsername = "new_user_username"
        case newUserPhotoUrl = "new_user_photo_url"
        case createdAt = "created_at"
    }
}
