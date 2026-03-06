import Foundation
import SwiftUI

// MARK: - Friend Service
/// Manages friend connections, requests, and workout sharing between users
@MainActor
class FriendService: ObservableObject {
    static let shared = FriendService()
    private let logger = SessionLogManager.shared
    
    // MARK: - Published Properties
    @Published var friends: [Friend] = []
    @Published var friendDTOs: [FriendDTO] = [] // For compatibility with existing views
    @Published var pendingRequests: [FriendRequest] = []  // Incoming requests (others → me)
    @Published var sentRequests: [SentFriendRequest] = [] // Outgoing requests (me → others)
    @Published var pendingRequestDTOs: [FriendRequestDTO] = [] // For compatibility
    @Published var receivedWorkouts: [ReceivedWorkoutDTO] = [] // Changed to DTO for compatibility
    @Published var sentWorkouts: [SentWorkout] = []
    @Published var notifications: [AppNotification] = []
    @Published var unreadNotificationCount: Int = 0
    
    @Published var isLoading = false
    @Published var searchResults: [UserSearchResult] = []
    @Published var searchResultDTOs: [UserSearchResultDTO] = [] // For compatibility
    
    // Computed property for unread workout count (unviewed pending workouts)
    var unreadWorkoutCount: Int {
        receivedWorkouts.filter { $0.viewedAt == nil && $0.isPending }.count
    }
    
    // Track last known workout count for detecting new workouts
    private var lastKnownWorkoutCount: Int = 0
    private var lastCheckedWorkoutIds: Set<UUID> = []
    
    // Track addressed workout IDs (started, saved, or deleted) to prevent reappearing
    // This ensures widgets disappear immediately and stay gone even if server is slow
    private var addressedWorkoutIds: Set<UUID> = []
    
    /// Track last known request IDs for detecting new friend requests
    private var lastCheckedRequestIds: Set<UUID> = []
    
    // MARK: - Cache Keys
    private let friendsCacheKey = "fit33_cached_friends"
    private let friendsCacheDateKey = "fit33_friends_cache_date"
    
    private init() {
        // Load cached friends immediately so Friends tab never shows empty state
        loadCachedFriends()
    }
    
    // MARK: - Local Friend Caching (instant display on cold start)
    
    /// Cache friends to UserDefaults for instant display on next app launch
    private func cacheFriends() {
        guard !friends.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(friends)
            UserDefaults.standard.set(data, forKey: friendsCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: friendsCacheDateKey)
            print("💾 [FRIENDS] Cached \(friends.count) friends")
        } catch {
            print("⚠️ [FRIENDS] Failed to cache friends: \(error)")
        }
    }
    
    /// Load cached friends from UserDefaults (called on init for instant display)
    private func loadCachedFriends() {
        guard let data = UserDefaults.standard.data(forKey: friendsCacheKey) else { return }
        do {
            let cached = try JSONDecoder().decode([Friend].self, from: data)
            if !cached.isEmpty {
                friends = cached
                print("⚡️ [FRIENDS] Loaded \(cached.count) cached friends (instant)")
            }
        } catch {
            print("⚠️ [FRIENDS] Failed to load cached friends: \(error)")
            UserDefaults.standard.removeObject(forKey: friendsCacheKey)
        }
    }
    
    // MARK: - Refresh Friend Data (Event-Driven)
    
    /// Refresh workouts and friend requests
    /// Call this on: pull-to-refresh, tab switch, app open, notification tap
    func refreshHomeScreenData() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        print("🔄 [REFRESH] Refreshing home screen friend data...")
        
        // Initialize tracking sets if empty
        if lastCheckedWorkoutIds.isEmpty {
            lastCheckedWorkoutIds = Set(receivedWorkouts.map { $0.id })
        }
        if lastCheckedRequestIds.isEmpty {
            lastCheckedRequestIds = Set(pendingRequests.map { $0.requestId })
        }
        
        // Fetch both in parallel
        async let workoutsTask: () = checkForNewWorkouts()
        async let requestsTask: () = checkForNewFriendRequests()
        
        _ = await (workoutsTask, requestsTask)
        
        print("✅ [REFRESH] Home screen data refreshed")
    }
    
    // MARK: - Check for New Workouts
    
    /// Check for new shared workouts and show notification if found
    /// Call this when app becomes active or periodically
    func checkForNewWorkouts() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let previousIds = lastCheckedWorkoutIds
        
        // Fetch latest workouts
        await fetchReceivedWorkouts()
        
        // Find truly new workouts (ones we haven't seen before)
        let currentIds = Set(receivedWorkouts.map { $0.id })
        let newWorkoutIds = currentIds.subtracting(previousIds)
        
        // Update tracking
        lastCheckedWorkoutIds = currentIds
        
        // Show notifications and haptic for new workouts
        for newId in newWorkoutIds {
            if let workout = receivedWorkouts.first(where: { $0.id == newId }) {
                // Only notify for unviewed workouts
                if workout.viewedAt == nil {
                    print("📬 [NEW WORKOUT] Detected new workout from \(workout.senderName)")
                    
                    NotificationManager.shared.sendSharedWorkoutNotification(
                        senderName: workout.senderName,
                        workoutName: workout.workoutName,
                        workoutId: workout.id.uuidString
                    )
                    
                    // Haptic feedback for new workout
                    HapticManager.notification(.success)
                }
            }
        }
    }
    
    // MARK: - Check for New Friend Requests
    
    /// Check for new friend requests and provide feedback
    func checkForNewFriendRequests() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let previousIds = lastCheckedRequestIds
        
        // Fetch latest requests
        await fetchPendingRequests()
        
        // Find truly new requests (ones we haven't seen before)
        let currentIds = Set(pendingRequests.map { $0.requestId })
        let newRequestIds = currentIds.subtracting(previousIds)
        
        // Update tracking
        lastCheckedRequestIds = currentIds
        
        // Haptic feedback for new friend requests
        for newId in newRequestIds {
            if let request = pendingRequests.first(where: { $0.requestId == newId }) {
                print("👋 [NEW REQUEST] Detected new friend request from \(request.displayName)")
                
                // Haptic feedback for new request
                HapticManager.notification(.success)
            }
        }
    }
    
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
        async let sentRequestsTask: () = fetchSentRequests()
        async let receivedTask: () = fetchReceivedWorkouts()
        async let sentTask: () = fetchSentWorkouts()
        async let notificationsTask: () = fetchNotifications()
        async let countTask: () = fetchUnreadCount()
        
        _ = await (friendsTask, requestsTask, sentRequestsTask, receivedTask, sentTask, notificationsTask, countTask)
    }
    
    // MARK: - Friends
    
    func fetchFriends() async {
        do {
            let result: [Friend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_friends")
                .execute()
                .value
            
            self.friends = result
            cacheFriends() // Persist for instant display on next launch
            
            logger.log(.info, category: .social, message: "Fetched \(result.count) friends", metadata: result.isEmpty ? nil : [
                "friends": result.prefix(5).map { $0.friendName ?? $0.friendUsername ?? "?" }.joined(separator: ", ")
            ])
            print("✅ Fetched \(result.count) friends")
            
            // Preload/refresh friend photos (detects URL changes for updated photos)
            let photoData = result.map { (id: $0.friendId.uuidString, url: $0.profilePhotoUrl) }
            FriendPhotoCache.shared.preloadPhotos(for: photoData)
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
        print("📤 [FRIEND REQUEST] Sending request to user: \(toUserId)")
        
        // Verify we're authenticated
        guard SupabaseManager.shared.isAuthenticated else {
            print("❌ [FRIEND REQUEST] Not authenticated - cannot send request")
            return false
        }
        
        guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
            print("❌ [FRIEND REQUEST] No current user ID - cannot send request")
            return false
        }
        
        print("📤 [FRIEND REQUEST] Current user: \(currentUserId), Target: \(toUserId)")
        
        do {
            var params: [String: String] = ["target_user_id": toUserId.uuidString]
            if let msg = message {
                params["request_message"] = msg
            }
            
            print("📤 [FRIEND REQUEST] Calling send_friend_request RPC...")
            let requestId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_friend_request", params: params)
                .execute()
                .value
            
            logger.log(.info, category: .social, message: "👋 Friend request SENT", metadata: [
                "to_user_id": toUserId.uuidString.prefix(8),
                "request_id": requestId.uuidString.prefix(8)
            ])
            print("✅ [FRIEND REQUEST] Request sent successfully! ID: \(requestId)")
            await fetchUnreadCount()
            await fetchSentRequests()  // Refresh sent requests list
            
            // Update daily quest progress for adding a friend
            await DailyQuestService.shared.onFriendRequestSent()
            
            return true
        } catch {
            logger.log(.error, category: .social, message: "Friend request FAILED", metadata: [
                "to_user_id": toUserId.uuidString.prefix(8),
                "error": "\(error)"
            ])
            print("❌ [FRIEND REQUEST] Error sending friend request: \(error)")
            print("❌ [FRIEND REQUEST] Error details: \(String(describing: error))")
            
            // Check if error is "Friend request already exists" - treat as success
            let errorString = String(describing: error)
            if errorString.contains("Friend request already exists") || errorString.contains("already exists") {
                print("ℹ️ [FRIEND REQUEST] Request already exists - treating as success")
                await fetchUnreadCount()
                await fetchSentRequests()
                return true
            }
            
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
                NotificationManager.shared.updateBadgeCount()
                logger.log(.info, category: .social, message: "✅ Friend request ACCEPTED", metadata: ["request_id": requestId.uuidString.prefix(8)])
                print("✅ Friend request accepted")
            }
            return success
        } catch {
            logger.log(.error, category: .social, message: "Accept friend request FAILED", metadata: ["error": "\(error)"])
            print("❌ Error accepting friend request: \(error)")
            return false
        }
    }
    
    func declineFriendRequest(requestId: UUID) async -> Bool {
        do {
            let success: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("decline_friend_request", params: ["request_id": requestId.uuidString])
                .execute()
                .value
            
            if success {
                // Update local state
                pendingRequests.removeAll { $0.requestId == requestId }
                NotificationManager.shared.updateBadgeCount()
                logger.log(.info, category: .social, message: "Friend request DECLINED", metadata: ["request_id": requestId.uuidString.prefix(8)])
                print("✅ Friend request declined")
            }
            return success
        } catch {
            logger.log(.error, category: .social, message: "Decline friend request FAILED", metadata: ["error": "\(error)"])
            print("❌ Error declining friend request: \(error)")
            return false
        }
    }
    
    // MARK: - Sent Friend Requests (Outgoing)
    
    func fetchSentRequests() async {
        do {
            let result: [SentFriendRequest] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_sent_friend_requests")
                .execute()
                .value
            
            self.sentRequests = result
            print("✅ Fetched \(result.count) sent friend requests")
        } catch {
            print("❌ Error fetching sent friend requests: \(error)")
        }
    }
    
    func cancelSentRequest(requestId: UUID) async -> Bool {
        do {
            let success: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("cancel_friend_request", params: ["request_id": requestId.uuidString])
                .execute()
                .value
            
            if success {
                // Update local state
                sentRequests.removeAll { $0.requestId == requestId }
                print("✅ Friend request cancelled")
            }
            return success
        } catch {
            print("❌ Error cancelling friend request: \(error)")
            return false
        }
    }
    
    /// Check if the current user is friends with another user
    func areFriends(with userId: UUID) async -> Bool {
        // Check local cache first
        if friends.contains(where: { $0.friendId == userId }) {
            return true
        }
        
        // If not in cache, check server
        do {
            let result: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("are_friends", params: [
                    "user_a": SupabaseManager.shared.currentUser?.id.uuidString ?? "",
                    "user_b": userId.uuidString
                ])
                .execute()
                .value
            return result
        } catch {
            print("❌ Error checking friendship: \(error)")
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
            // Define params struct for type safety
            struct SearchParams: Encodable {
                let search_query: String
                let result_limit: Int
            }
            
            let result: [UserSearchResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("search_users", params: SearchParams(search_query: query, result_limit: 20))
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
            let result: [ReceivedWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_received_workouts")
                .execute()
                .value
            
            // Filter out any workouts that were addressed (started, saved, or deleted)
            // This prevents zombie workouts from reappearing
            let filteredResult = result.filter { !addressedWorkoutIds.contains($0.id) }
            
            self.receivedWorkouts = filteredResult
            print("✅ Fetched \(result.count) received workouts (\(result.count - filteredResult.count) filtered as addressed)")
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
            
            // Create params struct for type safety
            struct SendWorkoutParams: Encodable {
                let target_user_id: String
                let p_workout_name: String
                let p_exercises: String
                let p_description: String?
                let p_message: String?
                let p_duration: Int?
                let p_difficulty: String
            }
            
            let params = SendWorkoutParams(
                target_user_id: toUserId.uuidString,
                p_workout_name: workoutName,
                p_exercises: exerciseJson,
                p_description: description,
                p_message: message,
                p_duration: duration,
                p_difficulty: difficulty
            )
            
            let _: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_workout_to_friend", params: params)
                .execute()
                .value
            
            await fetchSentWorkouts()
            print("✅ Workout sent to friend")
            
            // Update daily quest progress for sharing a workout
            await DailyQuestService.shared.onWorkoutShared()
            
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
    
    func markWorkoutViewed(workoutId: UUID) async {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update(["viewed_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            NotificationManager.shared.updateBadgeCount()
            print("✅ Workout marked as viewed")
        } catch {
            print("❌ Error marking workout viewed: \(error)")
        }
    }
    
    func markWorkoutStarted(workoutId: UUID) async -> Bool {
        // Track as addressed immediately - removes from pending widgets
        addressedWorkoutIds.insert(workoutId)
        
        // Optimistic update: Remove from local array for immediate UI feedback
        receivedWorkouts.removeAll { $0.id == workoutId }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "started",
                    "started_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            print("✅ Workout marked as started: \(workoutId)")
            return true
        } catch {
            print("❌ Error marking workout started: \(error)")
            // Keep it addressed locally even if server fails
            return true
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
    
    // Overload for String id
    func markWorkoutCompleted(workoutId: String) async -> Bool {
        guard let uuid = UUID(uuidString: workoutId) else { return false }
        return await markWorkoutCompleted(workoutId: uuid)
    }
    
    // Delete received workout (removes from database)
    func deleteReceivedWorkout(workoutId: UUID) async -> Bool {
        // Track as addressed immediately - removes from pending widgets
        addressedWorkoutIds.insert(workoutId)
        
        // Optimistic update: Remove from local array FIRST for snappy UI
        receivedWorkouts.removeAll { $0.id == workoutId }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .delete()
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            print("✅ Workout deleted from server: \(workoutId)")
            return true
        } catch {
            print("❌ Error deleting workout: \(error)")
            // Keep it addressed locally even if server delete fails
            print("⚠️ Keeping workout marked as addressed locally despite server error")
            return true  // Return true so UI treats it as deleted
        }
    }
    
    /// Clear addressed workout tracking (call when user logs out)
    func clearAddressedWorkoutTracking() {
        addressedWorkoutIds.removeAll()
    }
    
    // Save shared workout (marks as saved)
    func saveSharedWorkout(workoutId: UUID) async throws {
        // Track as addressed immediately - removes from pending widgets
        addressedWorkoutIds.insert(workoutId)
        
        // Optimistic update: Remove from local array for immediate UI feedback
        receivedWorkouts.removeAll { $0.id == workoutId }
        
        struct SaveWorkoutUpdate: Encodable {
            let status: String
            let saved_to_favorites: Bool
        }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update(SaveWorkoutUpdate(status: "saved", saved_to_favorites: true))
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            print("✅ Workout saved: \(workoutId)")
        } catch {
            print("❌ Error saving workout to server: \(error)")
            // Keep it addressed locally even if server fails
            // Don't re-throw - the user sees it as saved
        }
    }
    
    // Simplified sendWorkout method for SharedWorkoutPreviewView compatibility
    func sendWorkout(
        to friendId: String,
        workoutName: String,
        description: String?,
        exercises: [SharedExerciseDTO],
        message: String?
    ) async throws {
        guard let friendUUID = UUID(uuidString: friendId) else {
            throw NSError(domain: "FriendService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid friend ID"])
        }
        
        // Convert SharedExerciseDTO to SharedExercise
        let sharedExercises = exercises.map { dto in
            SharedExercise(
                name: dto.name,
                sets: dto.sets,
                reps: dto.reps,
                restSeconds: dto.restSeconds,
                notes: dto.notes
            )
        }
        
        let success = await sendWorkoutToFriend(
            toUserId: friendUUID,
            workoutName: workoutName,
            exercises: sharedExercises,
            description: description,
            message: message
        )
        
        if !success {
            throw NSError(domain: "FriendService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to send workout"])
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
    let friendUsername: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    let profilePhotoUrl: String?
    let friendsSince: Date
    let totalWorkoutsShared: Int
    
    var id: UUID { friendId }
    
    var displayName: String {
        // Show username first if available, then name, then email
        if let username = friendUsername, !username.isEmpty {
            return "@\(username)"
        }
        return friendName ?? friendEmail ?? "Unknown"
    }
    
    var initials: String {
        // Use name for initials, not username
        guard let name = friendName, !name.isEmpty else { 
            // Fall back to username initials
            if let username = friendUsername, !username.isEmpty {
                return String(username.prefix(2)).uppercased()
            }
            return "?" 
        }
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
        case friendUsername = "friend_username"
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case profilePhotoUrl = "profile_photo_url"
        case friendsSince = "friends_since"
        case totalWorkoutsShared = "total_workouts_shared"
    }
}

struct FriendRequest: Codable, Identifiable {
    let requestId: UUID
    let fromUserId: UUID
    let fromUserName: String?
    let fromUserEmail: String?
    let fromUserUsername: String?
    let profilePhotoUrl: String?
    let message: String?
    let createdAt: Date
    
    var id: UUID { requestId }
    
    var displayName: String {
        fromUserName ?? fromUserUsername ?? "Unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case fromUserId = "from_user_id"
        case fromUserName = "from_user_name"
        case fromUserEmail = "from_user_email"
        case fromUserUsername = "from_user_username"
        case profilePhotoUrl = "profile_photo_url"
        case message
        case createdAt = "created_at"
    }
}

/// Represents a friend request sent BY the current user (outgoing)
struct SentFriendRequest: Codable, Identifiable {
    let requestId: UUID
    let toUserId: UUID
    let toUserName: String?
    let toUserEmail: String?
    let toUserUsername: String?
    let profilePhotoUrl: String?
    let message: String?
    let createdAt: Date
    
    var id: UUID { requestId }
    
    var displayName: String {
        // Show username first if available
        if let username = toUserUsername, !username.isEmpty {
            return "@\(username)"
        }
        return toUserName ?? "Unknown"
    }
    
    var initials: String {
        // Use name for initials
        if let name = toUserName, !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        // Fall back to username
        if let username = toUserUsername, !username.isEmpty {
            return String(username.prefix(2)).uppercased()
        }
        return "?"
    }
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case toUserId = "to_user_id"
        case toUserName = "to_user_name"
        case toUserEmail = "to_user_email"
        case toUserUsername = "to_user_username"
        case profilePhotoUrl = "to_user_profile_photo_url"  // Fix: match SQL column name
        case message
        case createdAt = "created_at"
    }
}

struct UserSearchResult: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let email: String?
    let username: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    let profilePhotoUrl: String?
    let isFriend: Bool
    let hasPendingRequest: Bool        // Either direction (for backwards compatibility)
    let hasOutgoingRequest: Bool?      // I sent THEM a request (show "Pending")
    let hasIncomingRequest: Bool?      // THEY sent ME a request (show "Respond")
    
    var id: UUID { userId }
    
    var displayName: String {
        // Show username with @ if available
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
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case profilePhotoUrl = "profile_photo_url"
        case isFriend = "is_friend"
        case hasPendingRequest = "has_pending_request"
        case hasOutgoingRequest = "has_outgoing_request"
        case hasIncomingRequest = "has_incoming_request"
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
    let workoutId: UUID
    let senderId: UUID
    let senderName: String
    let senderUsername: String?
    let senderProfilePhotoUrl: String?
    let workoutName: String
    let workoutDescription: String?
    let exercises: [SharedExerciseDTO]?
    let exerciseNamesArray: [String]?  // From database exercise_names column
    let message: String?
    let status: String
    let estimatedDuration: Int?
    let difficultyLevel: String?
    let createdAt: Date
    let viewedAt: Date?
    let savedToFavorites: Bool?
    
    // Identifiable conformance
    var id: UUID { workoutId }
    
    // Computed properties for exercise details
    var exerciseCount: Int {
        exercises?.count ?? exerciseNamesArray?.count ?? 0
    }
    
    var exerciseNames: [String] {
        // Prefer parsed exercises, fall back to exercise_names array
        if let exercises = exercises, !exercises.isEmpty {
            return exercises.map { $0.name }
        }
        return exerciseNamesArray ?? []
    }
    
    var exerciseSets: [Int] {
        exercises?.map { $0.sets } ?? []
    }
    
    var exerciseReps: [String] {
        exercises?.map { $0.reps } ?? []
    }
    
    var exerciseNotes: [String] {
        exercises?.map { $0.notes ?? "" } ?? []
    }
    
    var senderDisplayName: String {
        senderName
    }
    
    var isPending: Bool {
        status == "pending"
    }
    
    var isSavedToFavorites: Bool {
        savedToFavorites ?? false
    }
    
    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderUsername = "sender_username"
        case senderProfilePhotoUrl = "sender_profile_photo_url"
        case workoutName = "workout_name"
        case workoutDescription = "workout_description"
        case exercises
        case exerciseNamesArray = "exercise_names"
        case message
        case status
        case estimatedDuration = "estimated_duration"
        case difficultyLevel = "difficulty_level"
        case createdAt = "created_at"
        case viewedAt = "viewed_at"
        case savedToFavorites = "saved_to_favorites"
    }
}

struct SharedExerciseDTO: Codable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let sets: Int
    let reps: String
    var restSeconds: Int? = nil
    var notes: String? = nil
    
    init(name: String, sets: Int, reps: String, restSeconds: Int? = nil, notes: String? = nil) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }
    
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
    var category: String?
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int = 90
    var notes: String = ""
}

// Type alias for compatibility
typealias SharedWorkoutDTO = ReceivedWorkoutDTO
