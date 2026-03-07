import Foundation
import Contacts
import SwiftUI
import Supabase

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
    
    private init() {
        checkAuthorizationStatus()
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
        print("📇 [CONTACTS] requestAccess() called")
        do {
            let granted = try await store.requestAccess(for: .contacts)
            checkAuthorizationStatus()
            print("📇 [CONTACTS] Authorization status after request: \(authorizationStatus.rawValue)")
            
            if granted {
                print("✅ [CONTACTS] Access granted - now fetching contacts and finding friends...")
                await fetchContactsAndFindFriends()
                print("✅ [CONTACTS] Fetch complete - suggestedFriends: \(suggestedFriends.count)")
            } else {
                print("❌ [CONTACTS] Access denied by user")
            }
            
            return granted
        } catch {
            print("❌ [CONTACTS] Error requesting access: \(error)")
            checkAuthorizationStatus()
            return false
        }
    }
    
    // MARK: - Fetch Contacts
    
    /// Fetch contacts and find matching app users
    func fetchContactsAndFindFriends() async {
        print("📇 [CONTACTS SERVICE] ════════════════════════════════════════════════")
        print("📇 [CONTACTS SERVICE] Starting fetchContactsAndFindFriends...")
        
        guard canAccessContacts else {
            print("⚠️ [CONTACTS SERVICE] No access to contacts - aborting")
            print("📇 [CONTACTS SERVICE] ════════════════════════════════════════════════")
            return
        }
        
        isLoading = true
        defer { 
            isLoading = false
            print("📇 [CONTACTS SERVICE] ════════════════════════════════════════════════")
        }
        
        // Step 1: Fetch contact emails and phone numbers from device
        print("📇 [CONTACTS SERVICE] Step 1: Fetching contact info from device...")
        await fetchContactInfo()
        print("📇 [CONTACTS SERVICE] ✓ Fetched \(contactPhoneNumbers.count) phones, \(contactEmails.count) emails")
        
        // Step 2: Find matching users in the app database
        print("📇 [CONTACTS SERVICE] Step 2: Finding matching Fit33 users...")
        await findMatchingUsers()
        print("📇 [CONTACTS SERVICE] ✓ Found \(suggestedFriends.count) Fit33 users in contacts")
        
        // Step 3: Sync contacts to database for "contact joined" notifications
        print("📇 [CONTACTS SERVICE] Step 3: Syncing contacts to database...")
        await syncContactsToDatabase()
        print("📇 [CONTACTS SERVICE] ✓ Contacts synced for future notifications")
        
        hasCheckedContacts = true
        print("📇 [CONTACTS SERVICE] ✅ fetchContactsAndFindFriends complete!")
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
                    print("❌ [CONTACTS] Error fetching contacts: \(error)")
                }
                
                continuation.resume(returning: (emails: Array(emails), phones: Array(phones)))
            }
        }
        
        // Back on @MainActor — safe to update @Published properties
        contactEmails = result.emails
        contactPhoneNumbers = result.phones
        print("📇 [CONTACTS] Found \(result.emails.count) emails and \(result.phones.count) phone numbers")
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
            print("⚠️ [CONTACTS] No contact emails or phone numbers to search")
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
        
        print("🔍 [CONTACTS] Searching for matching Fit33 users...")
        print("   └─ Emails: \(contactEmails.count) (sample: \(sampleEmails.joined(separator: ", ")))")
        print("   └─ Phone numbers: \(contactPhoneNumbers.count) (sample: \(samplePhones.joined(separator: ", ")))")
        print("   └─ DEBUG: First 10 full normalized phones: \(Array(contactPhoneNumbers.prefix(10)))")
        
        // Check if Abbie or Nicholas might be in the list
        let abbieNumbers = contactPhoneNumbers.filter { $0.contains("716") || $0.contains("585") }
        print("   └─ DEBUG: Phone numbers with 716/585 area code: \(abbieNumbers.count)")
        
        // Use direct database query method - more reliable than RPC
        print("🔍 [CONTACTS] Using direct database query for maximum reliability...")
        await findMatchingUsersDirect()
    }
    
    /// Fallback: search by email only (for backwards compatibility)
    private func findMatchingUsersByEmailOnly() async {
        guard !contactEmails.isEmpty else {
            print("⚠️ [CONTACTS] No contact emails to search")
            return
        }
        
        do {
            let result: [SuggestedFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("find_friends_from_contacts", params: ["contact_emails": contactEmails])
                .execute()
                .value
            
            suggestedFriends = result
            print("✅ [CONTACTS] Found \(result.count) suggested friends from emails (fallback)")
            
            // Log found friends
            for friend in result {
                print("   👤 Found: \(friend.displayName) (\(friend.email ?? "no email"))")
            }
        } catch {
            print("❌ [CONTACTS] Error finding matching users: \(error)")
            suggestedFriends = []
        }
    }
    
    /// Direct database query fallback - matches both phone and email
    private func findMatchingUsersDirect() async {
        print("🔍 [CONTACTS DIRECT] Querying database directly...")
        
        do {
            // Get current user ID to exclude self
            guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
                print("⚠️ [CONTACTS DIRECT] No current user ID")
                return
            }
            
            // Query for users where phone OR email matches our contacts
            // This is a more flexible query that handles different phone formats
            var matchedUsers: [SuggestedFriend] = []
            
            // Search by email
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
                
                // Convert to SuggestedFriend
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
                
                print("📧 [CONTACTS DIRECT] Found \(emailResults.count) matches by email")
            }
            
            // Search by phone - try multiple phone formats
            if !contactPhoneNumbers.isEmpty {
                // Try exact last 10 digits match
                print("📱 [CONTACTS DIRECT] Searching \(contactPhoneNumbers.count) phone numbers...")
                
                // First, get count of ALL users in database for debugging
                struct CountResult: Decodable {
                    let count: Int?
                }
                
                let totalCount: CountResult = try await SupabaseManager.shared.supabaseClient
                    .from("user_profiles")
                    .select("*", head: false, count: .exact)
                    .limit(1)
                    .single()
                    .execute()
                    .value
                
                print("📱 [CONTACTS DIRECT] Total users in database: \(totalCount.count ?? 0)")
                
                // Get ALL users with phone numbers
                struct UserProfile: Decodable {
                    let id: UUID
                    let name: String?
                    let email: String?
                    let username: String?
                    let profile_photo_url: String?
                    let phone_number: String?
                }
                
                print("📱 [CONTACTS DIRECT] Fetching all user profiles from database...")
                let allUsers: [UserProfile] = try await SupabaseManager.shared.supabaseClient
                    .from("user_profiles")
                    .select("id, name, email, username, profile_photo_url, phone_number")
                    .neq("id", value: currentUserId.uuidString)
                    .execute()
                    .value
                
                print("📱 [CONTACTS DIRECT] Got \(allUsers.count) TOTAL users from database")
                
                // Filter to those with phone numbers
                let usersWithPhones = allUsers.filter { $0.phone_number != nil && !$0.phone_number!.isEmpty }
                print("📱 [CONTACTS DIRECT] \(usersWithPhones.count) users have phone_number populated")
                
                // Log users with phones for debugging
                for (index, user) in usersWithPhones.prefix(10).enumerated() {
                    if let phone = user.phone_number {
                        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        let last4 = String(digits.suffix(4))
                        let userName = user.name ?? user.username ?? "Unknown"
                        print("   📱 User \(index + 1): \(userName) - ends in ...\(last4)")
                    }
                }
                
                // Check each user's phone against our contacts
                for user in usersWithPhones {
                    if let userPhone = user.phone_number {
                        // Extract all digits from user's phone
                        let userDigits = userPhone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        
                        var matched = false
                        let userName = user.name ?? user.username ?? "Unknown"
                        let userE164 = userPhone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+\(userDigits)" : userDigits
                        
                        // Strategy 1: E.164 exact match (e.g., +14161234567)
                        if contactPhoneNumbers.contains(userE164) {
                            matched = true
                            print("   ✅ Phone match (E.164)! \(userName)")
                        }
                        
                        // Strategy 2: Last 10 digits (backward-compatible US matching)
                        if !matched && userDigits.count >= 10 {
                            let userLast10 = String(userDigits.suffix(10))
                            if contactPhoneNumbers.contains(userLast10) {
                                matched = true
                                print("   ✅ Phone match (last 10)! \(userName)")
                            }
                        }
                        
                        // Strategy 3: Full digits match
                        if !matched && contactPhoneNumbers.contains(userDigits) {
                            matched = true
                            print("   ✅ Phone match (full digits)! \(userName)")
                        }
                        
                        // Strategy 4: Contact has country code, user doesn't (or vice versa)
                        if !matched {
                            for contactPhone in contactPhoneNumbers {
                                let contactDigits = contactPhone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                                if userDigits.hasSuffix(contactDigits) || contactDigits.hasSuffix(userDigits) {
                                    if min(userDigits.count, contactDigits.count) >= 7 {
                                        matched = true
                                        print("   ✅ Phone match (suffix)! \(userName)")
                                        break
                                    }
                                }
                            }
                        }
                        
                        if matched {
                            // Convert to SuggestedFriend and add
                            let friend = SuggestedFriend(
                                userId: user.id,
                                name: user.name,
                                email: user.email,
                                username: user.username,
                                profilePhotoUrl: user.profile_photo_url,
                                phoneNumber: user.phone_number,
                                fitnessGoal: nil,
                                isFriend: false,
                                hasOutgoingRequest: false,
                                hasIncomingRequest: false
                            )
                            
                            // Avoid duplicates
                            if !matchedUsers.contains(where: { $0.userId == friend.userId }) {
                                matchedUsers.append(friend)
                            }
                        }
                    }
                }
            }
            
            suggestedFriends = matchedUsers
            print("✅ [CONTACTS DIRECT] Total unique matches: \(matchedUsers.count)")
            
            for friend in matchedUsers {
                print("   👤 \(friend.displayName) (@\(friend.username ?? "no username"))")
            }
        } catch {
            print("❌ [CONTACTS DIRECT] Query failed: \(error)")
            suggestedFriends = []
        }
    }
    
    /// Refresh suggestions (call after adding a friend)
    func refreshSuggestions() async {
        if canAccessContacts && hasCheckedContacts {
            await findMatchingUsers()
        }
    }
    
    // MARK: - People You May Know (Friends-of-Friends)
    
    /// Fetch friends-of-friends with mutual friend counts
    func fetchPeopleYouMayKnow() async {
        print("👥 [PYMK] Fetching people you may know...")
        
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
            
            print("✅ [PYMK] Found \(peopleYouMayKnow.count) people you may know")
            
            // Preload photos
            let photoEntries = peopleYouMayKnow.compactMap { friend -> (id: String, url: String?)? in
                return (id: friend.userId.uuidString, url: friend.profilePhotoUrl)
            }
            FriendPhotoCache.shared.preloadPhotos(for: photoEntries)
            
        } catch {
            print("⚠️ [PYMK] Error fetching people you may know: \(error)")
            // Non-fatal - just use contact suggestions
        }
    }
    
    /// Contact-only suggestions, enriched with mutual friend data for sorting.
    /// Only people in the user's contacts are shown — no random strangers.
    /// Contacts who are also mutual friends (friends-of-friends) get boosted to the top.
    func allSuggestions(excludingFriendIds friendIds: Set<UUID>, excludingSentIds sentIds: Set<UUID>) -> [SuggestedFriend] {
        let excludeIds = friendIds.union(sentIds)
        
        // Build a lookup of mutual friend counts from the friends-of-friends query
        let mutualCountByUserId = Dictionary(
            uniqueKeysWithValues: peopleYouMayKnow.map { ($0.userId, $0.mutualFriendCount ?? 0) }
        )
        
        // Start with ONLY contact-based suggestions — no randoms
        let contacts = suggestedFriends.filter { suggestion in
            guard !excludeIds.contains(suggestion.userId) else { return false }
            guard !suggestion.isFriend else { return false }
            guard !suggestion.hasOutgoingRequest else { return false }
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
        guard canAccessContacts, !contactEmails.isEmpty else {
            print("⚠️ [CONTACTS] Cannot sync - no access or no emails")
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
            
            print("✅ [CONTACTS] Synced \(contactEmails.count) contacts to database")
            
            // Check for any pending "contact joined" notifications
            await checkForContactJoinedNotifications()
        } catch {
            print("❌ [CONTACTS] Error syncing contacts: \(error)")
        }
    }
    
    /// Check and send notifications for contacts who recently joined
    func checkForContactJoinedNotifications() async {
        do {
            let notifications: [ContactJoinedNotification] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_pending_contact_notifications")
                .execute()
                .value
            
            print("📬 [CONTACTS] Found \(notifications.count) pending contact joined notifications")
            
            // Send push notification for each
            for notification in notifications {
                await sendContactJoinedPushNotification(notification)
            }
        } catch {
            print("❌ [CONTACTS] Error checking contact notifications: \(error)")
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
            
            print("✅ [CONTACTS] Marked notification sent for \(displayName)")
        } catch {
            print("❌ [CONTACTS] Error marking notification sent: \(error)")
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
    /// This notifies existing Fit33 users who have the new user in their contacts
    func notifyExistingUsersOfNewJoin() async {
        guard let newUserId = SupabaseManager.shared.currentUser?.id else {
            print("❌ [CONTACTS] Cannot notify - no user ID")
            return
        }
        
        print("📬 [CONTACTS] Notifying existing users that \(newUserId) joined Fit33...")
        
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
            
            print("✅ [CONTACTS] Notified \(response.notifications_queued) existing users")
            print("   Message: \(response.message)")
            
        } catch {
            print("❌ [CONTACTS] Error notifying existing users: \(error)")
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
    let mutualFriendCount: Int? // Number of mutual friends (friends-of-friends)
    var isMutual: Bool  // Whether this suggestion came from friends-of-friends
    
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
    }
    
    init(userId: UUID, name: String?, email: String?, username: String?, profilePhotoUrl: String?, phoneNumber: String?, fitnessGoal: String?, isFriend: Bool, hasOutgoingRequest: Bool, hasIncomingRequest: Bool, mutualFriendCount: Int? = nil, isMutual: Bool = false) {
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
