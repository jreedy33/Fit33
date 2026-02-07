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
        
        var emails: Set<String> = []
        var phones: Set<String> = []
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                // Collect emails (lowercase for matching)
                for email in contact.emailAddresses {
                    let emailString = (email.value as String).lowercased().trimmingCharacters(in: .whitespaces)
                    if !emailString.isEmpty {
                        emails.insert(emailString)
                    }
                }
                
                // Collect phone numbers (normalized)
                for phone in contact.phoneNumbers {
                    let phoneString = self.normalizePhoneNumber(phone.value.stringValue)
                    if !phoneString.isEmpty {
                        phones.insert(phoneString)
                    }
                }
            }
            
            contactEmails = Array(emails)
            contactPhoneNumbers = Array(phones)
            
            print("📇 [CONTACTS] Found \(emails.count) emails and \(phones.count) phone numbers")
        } catch {
            print("❌ [CONTACTS] Error fetching contacts: \(error)")
        }
    }
    
    /// Normalize phone number by removing non-digits
    private func normalizePhoneNumber(_ phone: String) -> String {
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        // Return last 10 digits for US numbers, or full number for international
        if digits.count >= 10 {
            return String(digits.suffix(10))
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
                        
                        // Try multiple matching strategies to handle country codes
                        var matched = false
                        
                        // Strategy 1: Last 10 digits (standard US matching)
                        let userLast10 = String(userDigits.suffix(10))
                        let userName = user.name ?? user.username ?? "Unknown"
                        if contactPhoneNumbers.contains(userLast10) {
                            matched = true
                            print("   ✅ Phone match (last 10)! \(userName) - \(userLast10)")
                        }
                        
                        // Strategy 2: Full number with country code (e.g., +17163079290 matches 17163079290)
                        if !matched && contactPhoneNumbers.contains(userDigits) {
                            matched = true
                            print("   ✅ Phone match (full)! \(userName) - \(userDigits)")
                        }
                        
                        // Strategy 3: Check if contact has country code prefix
                        if !matched {
                            for contactPhone in contactPhoneNumbers {
                                // Try with +1 prefix
                                if userDigits == "1\(contactPhone)" || userDigits == contactPhone {
                                    matched = true
                                    print("   ✅ Phone match (country code)! \(userName) - \(contactPhone)")
                                    break
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
    
    var id: UUID { userId }
    
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
