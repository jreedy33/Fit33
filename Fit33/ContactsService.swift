import Foundation
import Contacts
import SwiftUI

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
        do {
            let granted = try await store.requestAccess(for: .contacts)
            checkAuthorizationStatus()
            
            if granted {
                print("✅ [CONTACTS] Access granted")
                await fetchContactsAndFindFriends()
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
        guard canAccessContacts else {
            print("⚠️ [CONTACTS] No access to contacts")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Fetch contact emails and phone numbers
        await fetchContactInfo()
        
        // Find matching users in the app
        await findMatchingUsers()
        
        // Sync contacts to database for "contact joined" notifications
        await syncContactsToDatabase()
        
        hasCheckedContacts = true
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
        guard !contactEmails.isEmpty else {
            print("⚠️ [CONTACTS] No contact emails to search")
            return
        }
        
        do {
            // Call database function to find matching users
            let result: [SuggestedFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("find_friends_from_contacts", params: ["contact_emails": contactEmails])
                .execute()
                .value
            
            suggestedFriends = result
            print("✅ [CONTACTS] Found \(result.count) suggested friends from contacts")
        } catch {
            print("❌ [CONTACTS] Error finding matching users: \(error)")
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
}

// MARK: - Suggested Friend Model

struct SuggestedFriend: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let email: String?
    let username: String?
    let profilePhotoUrl: String?
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
