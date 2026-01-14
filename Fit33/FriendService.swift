import Foundation
import SwiftUI

// MARK: - Friend Service
/// Manages friend connections, requests, and workout sharing between users
@MainActor
class FriendService: ObservableObject {
    static let shared = FriendService()
    
    // MARK: - Published Properties
    @Published var friends: [Friend] = []
    @Published var friendDTOs: [FriendDTO] = [] // For compatibility with existing views
    @Published var pendingRequests: [FriendRequest] = []
    @Published var pendingRequestDTOs: [FriendRequestDTO] = [] // For compatibility
    @Published var receivedWorkouts: [SharedWorkout] = []
    @Published var receivedWorkoutDTOs: [ReceivedWorkoutDTO] = [] // For compatibility
    @Published var sentWorkouts: [SentWorkout] = []
    @Published var notifications: [AppNotification] = []
    @Published var unreadNotificationCount: Int = 0
    
    @Published var isLoading = false
    @Published var searchResults: [UserSearchResult] = []
    @Published var searchResultDTOs: [UserSearchResultDTO] = [] // For compatibility
    
    // Computed property for unread workout count
    var unreadWorkoutCount: Int {
        receivedWorkouts.filter { $0.isPending }.count
    }
    
    private init() {}
    
    // MARK: - Load All Data (for compatibility)
    func loadAllData() async {
        await refreshAll()
    }
    
    // MARK: - Individual Loaders (for compatibility)
    func loadPendingRequests() async {
        await fetchPendingRequests()
    }
    
    func loadReceivedWorkouts() async {
        await fetchReceivedWorkouts()
    }
    
    func loadFriends() async {
        await fetchFriends()
    }
    
    // MARK: - Fetch All Data
    
    /// Refresh all friend-related data from the server
    func refreshAll() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        async let friendsTask: () = fetchFriends()
        async let requestsTask: () = fetchPendingRequests()
        async let receivedTask: () = fetchReceivedWorkouts()
        async let sentTask: () = fetchSentWorkouts()
        async let notificationsTask: () = fetchNotifications()
        async let countTask: () = fetchUnreadCount()
        
        _ = await (friendsTask, requestsTask, receivedTask, sentTask, notificationsTask, countTask)
    }
    
    // MARK: - Friends
    
    func fetchFriends() async {
        do {
            let result: [Friend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_friends")
                .execute()
                .value
            
            self.friends = result
            print("✅ Fetched \(result.count) friends")
        } catch {
            print("❌ Error fetching friends: \(error)")
        }
    }
    
    func removeFriend(friendshipId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("friendships")
                .delete()
                .eq("id", value: friendshipId.uuidString)
                .execute()
            
            // Update local state
            friends.removeAll { $0.friendshipId == friendshipId }
            print("✅ Friend removed")
            return true
        } catch {
            print("❌ Error removing friend: \(error)")
            return false
        }
    }
    
    // MARK: - Friend Requests
    
    func fetchPendingRequests() async {
        do {
            let result: [FriendRequest] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_pending_friend_requests")
                .execute()
                .value
            
            self.pendingRequests = result
            print("✅ Fetched \(result.count) pending friend requests")
        } catch {
            print("❌ Error fetching friend requests: \(error)")
        }
    }
    
    func sendFriendRequest(toUserId: UUID, message: String? = nil) async -> Bool {
        do {
            let _: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_friend_request", params: [
                    "target_user_id": toUserId.uuidString,
                    "request_message": message as Any
                ])
                .execute()
                .value
            
            print("✅ Friend request sent")
            await fetchUnreadCount()
            return true
        } catch {
            print("❌ Error sending friend request: \(error)")
            return false
        }
    }
    
    func acceptFriendRequest(requestId: UUID) async -> Bool {
        do {
            let success: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("accept_friend_request", params: ["request_id": requestId.uuidString])
                .execute()
                .value
            
            if success {
                // Update local state
                pendingRequests.removeAll { $0.requestId == requestId }
                await fetchFriends()
                print("✅ Friend request accepted")
            }
            return success
        } catch {
            print("❌ Error accepting friend request: \(error)")
            return false
        }
    }
    
    func declineFriendRequest(requestId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("friend_requests")
                .update(["status": "declined", "responded_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: requestId.uuidString)
                .execute()
            
            // Update local state
            pendingRequests.removeAll { $0.requestId == requestId }
            print("✅ Friend request declined")
            return true
        } catch {
            print("❌ Error declining friend request: \(error)")
            return false
        }
    }
    
    // MARK: - User Search
    
    func searchUsers(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        do {
            let result: [UserSearchResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("search_users", params: ["search_query": query, "result_limit": 20])
                .execute()
                .value
            
            self.searchResults = result
            print("✅ Found \(result.count) users matching '\(query)'")
        } catch {
            print("❌ Error searching users: \(error)")
            searchResults = []
        }
    }
    
    // MARK: - Shared Workouts
    
    func fetchReceivedWorkouts() async {
        do {
            let result: [SharedWorkout] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_received_workouts")
                .execute()
                .value
            
            self.receivedWorkouts = result
            print("✅ Fetched \(result.count) received workouts")
        } catch {
            print("❌ Error fetching received workouts: \(error)")
        }
    }
    
    func fetchSentWorkouts() async {
        do {
            let result: [SentWorkout] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_sent_workouts")
                .execute()
                .value
            
            self.sentWorkouts = result
            print("✅ Fetched \(result.count) sent workouts")
        } catch {
            print("❌ Error fetching sent workouts: \(error)")
        }
    }
    
    func sendWorkoutToFriend(
        toUserId: UUID,
        workoutName: String,
        exercises: [SharedExercise],
        description: String? = nil,
        message: String? = nil,
        duration: Int? = nil,
        difficulty: String = "Custom"
    ) async -> Bool {
        do {
            // Convert exercises to JSON
            let encoder = JSONEncoder()
            let exerciseData = try encoder.encode(exercises)
            let exerciseJson = String(data: exerciseData, encoding: .utf8) ?? "[]"
            
            let _: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_workout_to_friend", params: [
                    "target_user_id": toUserId.uuidString,
                    "p_workout_name": workoutName,
                    "p_exercises": exerciseJson,
                    "p_description": description as Any,
                    "p_message": message as Any,
                    "p_duration": duration as Any,
                    "p_difficulty": difficulty
                ])
                .execute()
                .value
            
            await fetchSentWorkouts()
            print("✅ Workout sent to friend")
            return true
        } catch {
            print("❌ Error sending workout: \(error)")
            return false
        }
    }
    
    func acceptReceivedWorkout(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "accepted",
                    "responded_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            print("✅ Workout accepted")
            return true
        } catch {
            print("❌ Error accepting workout: \(error)")
            return false
        }
    }
    
    func declineReceivedWorkout(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "declined",
                    "responded_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            print("✅ Workout declined")
            return true
        } catch {
            print("❌ Error declining workout: \(error)")
            return false
        }
    }
    
    func saveWorkoutToFavorites(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update(["saved_to_favorites": true])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            print("✅ Workout saved to favorites")
            return true
        } catch {
            print("❌ Error saving workout to favorites: \(error)")
            return false
        }
    }
    
    func markWorkoutStarted(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "started",
                    "started_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            print("✅ Workout marked as started")
            return true
        } catch {
            print("❌ Error marking workout started: \(error)")
            return false
        }
    }
    
    func markWorkoutCompleted(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "completed",
                    "completed_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            print("✅ Workout marked as completed")
            return true
        } catch {
            print("❌ Error marking workout completed: \(error)")
            return false
        }
    }
    
    // MARK: - Notifications
    
    func fetchNotifications() async {
        do {
            let result: [AppNotification] = try await SupabaseManager.shared.supabaseClient
                .from("app_notifications")
                .select()
                .eq("user_id", value: SupabaseManager.shared.currentUser?.id.uuidString ?? "")
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            self.notifications = result
            print("✅ Fetched \(result.count) notifications")
        } catch {
            print("❌ Error fetching notifications: \(error)")
        }
    }
    
    func fetchUnreadCount() async {
        do {
            let count: Int = try await SupabaseManager.shared.supabaseClient
                .rpc("get_unread_notification_count")
                .execute()
                .value
            
            self.unreadNotificationCount = count
        } catch {
            print("❌ Error fetching unread count: \(error)")
        }
    }
    
    func markNotificationRead(notificationId: UUID) async {
        do {
            let _: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("mark_notification_read", params: ["notification_id": notificationId.uuidString])
                .execute()
                .value
            
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
                notifications[index].isRead = true
            }
            unreadNotificationCount = max(0, unreadNotificationCount - 1)
        } catch {
            print("❌ Error marking notification read: \(error)")
        }
    }
    
    func markAllNotificationsRead() async {
        do {
            let _: Int = try await SupabaseManager.shared.supabaseClient
                .rpc("mark_all_notifications_read")
                .execute()
                .value
            
            // Update local state
            for i in notifications.indices {
                notifications[i].isRead = true
            }
            unreadNotificationCount = 0
        } catch {
            print("❌ Error marking all notifications read: \(error)")
        }
    }
}

// MARK: - Data Models

struct Friend: Codable, Identifiable {
    let friendshipId: UUID
    let friendId: UUID
    let friendName: String?
    let friendEmail: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    let friendsSince: Date
    let totalWorkoutsShared: Int
    
    var id: UUID { friendId }
    
    var displayName: String {
        friendName ?? friendEmail ?? "Unknown"
    }
    
    var initials: String {
        guard let name = friendName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case friendshipId = "friendship_id"
        case friendId = "friend_id"
        case friendName = "friend_name"
        case friendEmail = "friend_email"
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case friendsSince = "friends_since"
        case totalWorkoutsShared = "total_workouts_shared"
    }
}

struct FriendRequest: Codable, Identifiable {
    let requestId: UUID
    let fromUserId: UUID
    let fromUserName: String?
    let fromUserEmail: String?
    let message: String?
    let createdAt: Date
    
    var id: UUID { requestId }
    
    var displayName: String {
        fromUserName ?? fromUserEmail ?? "Unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserEmail = "from_user_email"
        case message
        case createdAt = "created_at"
    }
}

struct UserSearchResult: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let email: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    let isFriend: Bool
    let hasPendingRequest: Bool
    
    var id: UUID { userId }
    
    var displayName: String {
        name ?? email ?? "Unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case email
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case isFriend = "is_friend"
        case hasPendingRequest = "has_pending_request"
    }
}

struct SharedWorkout: Codable, Identifiable {
    let workoutId: UUID
    let fromUserId: UUID
    let fromUserName: String?
    let workoutName: String
    let workoutDescription: String?
    let exercises: [SharedExercise]
    let message: String?
    let status: String
    let estimatedDuration: Int?
    let difficultyLevel: String?
    let createdAt: Date
    let savedToFavorites: Bool
    
    var id: UUID { workoutId }
    
    var senderDisplayName: String {
        fromUserName ?? "Unknown"
    }
    
    var isPending: Bool {
        status == "pending"
    }
    
    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case workoutName = "workout_name"
        case workoutDescription = "workout_description"
        case exercises
        case message
        case status
        case estimatedDuration = "estimated_duration"
        case difficultyLevel = "difficulty_level"
        case createdAt = "created_at"
        case savedToFavorites = "saved_to_favorites"
    }
}

struct SharedExercise: Codable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case sets
        case reps
        case restSeconds = "rest_seconds"
        case notes
    }
    
    init(name: String, sets: Int, reps: String, restSeconds: Int? = nil, notes: String? = nil) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.sets = try container.decode(Int.self, forKey: .sets)
        self.reps = try container.decode(String.self, forKey: .reps)
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct SentWorkout: Codable, Identifiable {
    let workoutId: UUID
    let toUserId: UUID
    let toUserName: String?
    let workoutName: String
    let status: String
    let createdAt: Date
    let startedAt: Date?
    let completedAt: Date?
    
    var id: UUID { workoutId }
    
    var recipientDisplayName: String {
        toUserName ?? "Unknown"
    }
    
    var statusIcon: String {
        switch status {
        case "pending": return "clock"
        case "accepted": return "checkmark.circle"
        case "declined": return "xmark.circle"
        case "started": return "figure.run"
        case "completed": return "trophy.fill"
        default: return "questionmark.circle"
        }
    }
    
    var statusColor: Color {
        switch status {
        case "pending": return .orange
        case "accepted": return .blue
        case "declined": return .red
        case "started": return .green
        case "completed": return .yellow
        default: return .gray
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case toUserId = "to_user_id"
        case toUserName = "to_user_name"
        case workoutName = "workout_name"
        case status
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct AppNotification: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let notificationType: String
    let referenceId: UUID?
    let referenceType: String?
    let fromUserId: UUID?
    let fromUserName: String?
    let title: String
    let body: String
    var isRead: Bool
    let readAt: Date?
    let createdAt: Date
    
    var icon: String {
        switch notificationType {
        case "friend_request_received": return "person.badge.plus"
        case "friend_request_accepted": return "person.2.fill"
        case "workout_received": return "dumbbell.fill"
        case "workout_started": return "figure.run"
        case "workout_completed": return "trophy.fill"
        default: return "bell.fill"
        }
    }
    
    var iconColor: Color {
        switch notificationType {
        case "friend_request_received": return .blue
        case "friend_request_accepted": return .green
        case "workout_received": return .orange
        case "workout_started": return .purple
        case "workout_completed": return .yellow
        default: return .gray
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case notificationType = "notification_type"
        case referenceId = "reference_id"
        case referenceType = "reference_type"
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case title
        case body
        case isRead = "is_read"
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

// MARK: - Compatibility DTOs
// These DTOs match the existing views for compatibility

enum FriendshipStatus: String, Codable {
    case none = "none"
    case pending = "pending"
    case friends = "friends"
    case requestReceived = "request_received"
}

struct FriendDTO: Codable, Identifiable {
    let id: String
    let name: String?
    let email: String?
    let friendshipId: String
    let friendsSince: Date
    var fitnessGoal: String?
    var experienceLevel: String?
    var workoutsShared: Int = 0
    
    var displayName: String {
        name ?? email ?? "Unknown"
    }
    
    var initials: String {
        guard let name = name, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case friendshipId = "friendship_id"
        case friendsSince = "friends_since"
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case workoutsShared = "workouts_shared"
    }
}

struct FriendRequestDTO: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let fromUserName: String?
    let fromUserEmail: String?
    let message: String?
    let createdAt: Date
    
    var displayName: String {
        fromUserName ?? fromUserEmail ?? "Unknown"
    }
    
    var initials: String {
        guard let name = fromUserName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserEmail = "from_user_email"
        case message
        case createdAt = "created_at"
    }
}

struct UserSearchResultDTO: Codable, Identifiable {
    let id: String
    let name: String?
    let email: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    var friendshipStatus: FriendshipStatus
    
    var displayName: String {
        name ?? email ?? "Unknown"
    }
    
    var initials: String {
        guard let name = name, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case friendshipStatus = "friendship_status"
    }
}

struct ReceivedWorkoutDTO: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let fromUserName: String?
    let workoutName: String
    let workoutDescription: String?
    let exercises: [SharedExerciseDTO]
    let message: String?
    let status: String
    let estimatedDuration: Int?
    let difficultyLevel: String?
    let createdAt: Date
    let savedToFavorites: Bool
    
    var senderDisplayName: String {
        fromUserName ?? "Unknown"
    }
    
    var isPending: Bool {
        status == "pending"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case workoutName = "workout_name"
        case workoutDescription = "workout_description"
        case exercises
        case message
        case status
        case estimatedDuration = "estimated_duration"
        case difficultyLevel = "difficulty_level"
        case createdAt = "created_at"
        case savedToFavorites = "saved_to_favorites"
    }
}

struct SharedExerciseDTO: Codable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case sets
        case reps
        case restSeconds = "rest_seconds"
        case notes
    }
}

struct SelectedExerciseForFriend: Identifiable {
    var id = UUID()
    let name: String
    let category: String
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int = 90
    var notes: String = ""
}
