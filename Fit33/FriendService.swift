import Foundation
import SwiftUI

// MARK: - Friend Service
/// Manages friend connections, requests, and workout sharing between users
@MainActor
class FriendService: ObservableObject {
    static let shared = FriendService()
    private let logger = SessionLogManager.shared

    /// Hoisted ISO8601 formatter — was being reallocated on every shared-workout
    /// state transition (accept/decline/view/start/complete).
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()
    
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
    @Published var blockedUserIds: Set<UUID> = []
    
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
    
    private static let blockedUserIdsCacheKey = "fit33_blocked_user_ids"
    
    private init() {
        // ⚡️ Cold-start Phase 4: prefer pre-decoded caches (decoded on bg
        // thread by StartupCachePreloader.preloadAll, which runs at the
        // first statement of Fit33App.init). Falls back to the original
        // synchronous decode path only if bg lost the race.
        let pre = StartupCachePreloader.consumeFriends()
        if let cachedFriends = pre.friends, !cachedFriends.isEmpty {
            self.friends = cachedFriends
            AppLogger.debug("[FRIENDS] Loaded \(cachedFriends.count) cached friends (instant — pre-decoded)", category: .social)
        } else {
            loadCachedFriends()
        }
        if let cachedBlocked = pre.blocked {
            self.blockedUserIds = cachedBlocked
            if !cachedBlocked.isEmpty {
                AppLogger.debug("Loaded \(cachedBlocked.count) cached blocked user IDs (pre-decoded)", category: .social)
            }
        } else {
            loadCachedBlockedUserIds()
        }

        let ids = friends.map { $0.friendId.uuidString }
        if !ids.isEmpty {
            FriendPhotoCache.shared.warmMemoryCacheFromDisk(for: ids)
        }
    }
    
    private func loadCachedBlockedUserIds() {
        let strings = UserDefaults.standard.stringArray(forKey: Self.blockedUserIdsCacheKey) ?? []
        blockedUserIds = Set(strings.compactMap { UUID(uuidString: $0) })
        if !blockedUserIds.isEmpty {
            AppLogger.debug("Loaded \(blockedUserIds.count) cached blocked user IDs", category: .social)
        }
    }
    
    func persistBlockedUserIds() {
        let strings = blockedUserIds.map { $0.uuidString }
        UserDefaults.standard.set(Array(strings), forKey: Self.blockedUserIdsCacheKey)
    }
    
    // MARK: - Local Friend Caching (instant display on cold start)
    
    /// Cache friends to UserDefaults for instant display on next app launch
    private func cacheFriends() {
        guard !friends.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(friends)
            UserDefaults.standard.set(data, forKey: friendsCacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: friendsCacheDateKey)
            AppLogger.debug("[FRIENDS] Cached \(friends.count) friends", category: .social)
        } catch {
            AppLogger.warning("[FRIENDS] Failed to cache friends: \(error.localizedDescription)", category: .social)
        }
    }
    
    /// Load cached friends from UserDefaults (called on init for instant display)
    private func loadCachedFriends() {
        guard let data = UserDefaults.standard.data(forKey: friendsCacheKey) else { return }
        do {
            let cached = try JSONDecoder().decode([Friend].self, from: data)
            if !cached.isEmpty {
                friends = cached
                AppLogger.debug("[FRIENDS] Loaded \(cached.count) cached friends (instant)", category: .social)
            }
        } catch {
            AppLogger.warning("[FRIENDS] Failed to load cached friends: \(error.localizedDescription)", category: .social)
            UserDefaults.standard.removeObject(forKey: friendsCacheKey)
        }
    }
    
    // MARK: - Refresh Friend Data (Event-Driven)
    
    /// Refresh workouts and friend requests
    /// Call this on: pull-to-refresh, tab switch, app open, notification tap
    func refreshHomeScreenData() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        AppLogger.debug("[REFRESH] Refreshing home screen friend data...", category: .social)
        
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
        
        AppLogger.info("[REFRESH] Home screen data refreshed", category: .social)
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
                    AppLogger.info("[NEW WORKOUT] Detected new workout from \(workout.senderName)", category: .social)
                    
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
                AppLogger.info("[NEW REQUEST] Detected new friend request from \(request.displayName)", category: .social)
                
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
        guard SupabaseManager.shared.isAuthenticated else { return }
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
            AppLogger.info("Fetched \(result.count) friends", category: .social)
            
            // Preload/refresh friend photos (detects URL changes for updated photos)
            let photoData = result.map { (id: $0.friendId.uuidString, url: $0.profilePhotoUrl) }
            FriendPhotoCache.shared.preloadPhotos(for: photoData)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching friends",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/get_friends",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }
    
    func removeFriend(friendshipId: UUID) async -> Bool {
        guard let friendToRemove = friends.first(where: { $0.friendshipId == friendshipId }) else {
            AppLogger.error("Friend not found in local state", category: .social)
            return false
        }
        
        do {
            struct UnfriendParams: Encodable {
                let p_friend_user_id: String
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("unfriend", params: UnfriendParams(p_friend_user_id: friendToRemove.friendId.uuidString))
                .execute()
            
            friends.removeAll { $0.friendshipId == friendshipId }
            AppLogger.info("Friend removed", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error removing friend",
                category: .social,
                op: PerformanceSignposts.Op.friendsWrite.rawValue,
                endpoint: "rpc/unfriend",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Blocking
    
    func blockUser(userId: UUID) async -> Bool {
        do {
            struct BlockParams: Encodable {
                let p_target_user_id: String
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("block_user", params: BlockParams(p_target_user_id: userId.uuidString))
                .execute()
            
            friends.removeAll { $0.friendId == userId }
            sentRequests.removeAll { $0.toUserId == userId }
            pendingRequests.removeAll { $0.fromUserId == userId }
            receivedWorkouts.removeAll { $0.senderId == userId }
            blockedUserIds.insert(userId)
            persistBlockedUserIds()
            
            FriendRankingService.shared.removeBlockedUser(userId)
            ActivityFeedService.shared.removeBlockedUser(userId)
            
            AppLogger.info("User blocked — purged from all social surfaces", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error blocking user",
                category: .social,
                op: PerformanceSignposts.Op.friendsWrite.rawValue,
                endpoint: "rpc/block_user",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    func unblockUser(userId: UUID) async -> Bool {
        do {
            struct UnblockParams: Encodable {
                let p_target_user_id: String
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("unblock_user", params: UnblockParams(p_target_user_id: userId.uuidString))
                .execute()
            
            blockedUserIds.remove(userId)
            persistBlockedUserIds()
            AppLogger.info("User unblocked", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error unblocking user",
                category: .social,
                op: PerformanceSignposts.Op.friendsWrite.rawValue,
                endpoint: "rpc/unblock_user",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }

    /// Fetches the authenticated user's block list with profile info. Used by
    /// the Settings → Blocked Users screen (Sprint 2 Q2-7).
    func fetchBlockedUsers() async -> [BlockedUser] {
        guard SupabaseManager.shared.isAuthenticated else { return [] }
        do {
            let rows: [BlockedUser] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_blocked_users")
                .execute()
                .value

            // Keep the local cache in sync with the authoritative server list.
            let serverIds = Set(rows.map { $0.userId })
            if blockedUserIds != serverIds {
                blockedUserIds = serverIds
                persistBlockedUserIds()
            }
            return rows
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching blocked users",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/get_blocked_users",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return []
        }
    }

    /// Reports user-authored content for admin review. Writes a row to
    /// `content_moderation_log` server-side with `flagged_categories=["user_report"]`.
    /// Typically called alongside `blockUser` from a Report-and-Block sheet (Sprint 2 Q2-7).
    @discardableResult
    func reportContent(
        tableName: String,
        recordId: String,
        reportedUserId: UUID,
        contentSnippet: String,
        reason: String? = nil
    ) async -> Bool {
        do {
            struct ReportParams: Encodable {
                let p_table_name: String
                let p_record_id: String
                let p_reported_user_id: String
                let p_content_snippet: String
                let p_reason: String?
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("report_content", params: ReportParams(
                    p_table_name: tableName,
                    p_record_id: recordId,
                    p_reported_user_id: reportedUserId.uuidString,
                    p_content_snippet: contentSnippet,
                    p_reason: reason
                ))
                .execute()
            AppLogger.info("Content reported (\(tableName)#\(recordId.prefix(8)))", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error reporting content",
                category: .social,
                op: PerformanceSignposts.Op.friendsWrite.rawValue,
                endpoint: "rpc/report_content",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Friend Requests
    
    func fetchPendingRequests() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                let result: [FriendRequest] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_pending_friend_requests")
                    .execute()
                    .value
                
                self.pendingRequests = result
                AppLogger.info("Fetched \(result.count) pending friend requests", category: .social)
                return
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain &&
                    (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorCancelled)
                if isTimeout && attempt < maxAttempts {
                    AppLogger.warning("fetchPendingRequests timeout (attempt \(attempt)/\(maxAttempts)), retrying...", category: .social)
                    try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                } else {
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error fetching friend requests",
                        category: .social,
                        op: PerformanceSignposts.Op.friendRequestList.rawValue,
                        endpoint: "rpc/get_pending_friend_requests",
                        userId: SupabaseManager.shared.currentUser?.id,
                        retryAttempt: attempt
                    )
                }
            }
        }
    }
    
    func sendFriendRequest(toUserId: UUID, message: String? = nil) async -> Bool {
        AppLogger.debug("[FRIEND REQUEST] Sending request to user: \(toUserId)", category: .social)
        
        // Verify we're authenticated
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[FRIEND REQUEST] Not authenticated - cannot send request", category: .social)
            return false
        }
        
        guard let currentUserId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("[FRIEND REQUEST] No current user ID - cannot send request", category: .social)
            return false
        }
        
        AppLogger.debug("[FRIEND REQUEST] Current user: \(currentUserId), Target: \(toUserId)", category: .social)
        
        do {
            var params: [String: String] = ["target_user_id": toUserId.uuidString]
            if let msg = message {
                params["request_message"] = msg
            }
            
            AppLogger.debug("[FRIEND REQUEST] Calling send_friend_request RPC...", category: .social)
            let requestId: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("send_friend_request", params: params)
                .execute()
                .value
            
            logger.log(.info, category: .social, message: "👋 Friend request SENT", metadata: [
                "to_user_id": toUserId.uuidString.prefix(8),
                "request_id": requestId.uuidString.prefix(8)
            ])
            AppLogger.info("[FRIEND REQUEST] Request sent successfully! ID: \(requestId)", category: .social)
            await fetchUnreadCount()
            await fetchSentRequests()
            
            await DailyQuestService.shared.onFriendRequestSent()

            // NUJ telemetry — flips `added_first_friend` boolean on the
            // user's enrollment row via the trigger (#167 contract:
            // event_type='social' + payload.action='friend_added').
            // We log on REQUEST SENT (not accepted) because that's the user's
            // intent moment — accept happens on the receiver's device, where
            // it can't fire this user's enrollment trigger.
            await MainActor.run {
                NewUserJourneyTracker.shared.logSocial(
                    action: "friend_added",
                    targetUserId: toUserId.uuidString
                )
            }
            
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "Friend request sent — flushing push queue", metadata: ["to_user": toUserId.uuidString.prefix(8)])
            PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "friend_request_sent")
            
            return true
        } catch {
            logger.log(.warning, category: .social, message: "Friend request FAILED", metadata: [
                "to_user_id": toUserId.uuidString.prefix(8),
                "error": "\(error)"
            ])
            _ = NetworkErrorClassifier.log(
                error,
                context: "[FRIEND REQUEST] Error sending friend request",
                category: .social,
                op: PerformanceSignposts.Op.friendRequestWrite.rawValue,
                endpoint: "rpc/send_friend_request",
                userId: currentUserId
            )
            
            // Check if error is "Friend request already exists" - treat as success
            let errorString = String(describing: error)
            if errorString.contains("Friend request already exists") || errorString.contains("already exists") {
                AppLogger.info("[FRIEND REQUEST] Request already exists - treating as success", category: .social)
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
                pendingRequests.removeAll { $0.requestId == requestId }
                await fetchFriends()
                NotificationManager.shared.updateBadgeCount()
                logger.log(.info, category: .social, message: "✅ Friend request ACCEPTED", metadata: ["request_id": requestId.uuidString.prefix(8)])
                AppLogger.info("Friend request accepted", category: .social)

                // 2026-05-04 — Olympian Path: previously-dormant friend-add
                // achievement hook now fires. `BadgeService.onFriendAdded`
                // also fans out to Olympian Path mirror keys
                // (`olympian_<year>_first_friend`, `*_friends_10`). Fire-and-
                // forget so the friend-accept tap doesn't block on RPCs.
                let totalFriends = self.friends.count
                Task.detached {
                    await BadgeService.shared.onFriendAdded(totalFriends: totalFriends)
                }

                SessionLogManager.shared.log(.info, category: .pushNotification, message: "Friend request accepted — flushing push queue", metadata: ["request_id": requestId.uuidString.prefix(8)])
                PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "friend_request_accepted")
            }
            return success
        } catch {
            logger.log(.warning, category: .social, message: "Accept friend request FAILED", metadata: ["error": "\(error)"])
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error accepting friend request",
                category: .social,
                op: PerformanceSignposts.Op.friendRequestWrite.rawValue,
                endpoint: "rpc/accept_friend_request",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
                AppLogger.info("Friend request declined", category: .social)
            }
            return success
        } catch {
            logger.log(.warning, category: .social, message: "Decline friend request FAILED", metadata: ["error": "\(error)"])
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error declining friend request",
                category: .social,
                op: PerformanceSignposts.Op.friendRequestWrite.rawValue,
                endpoint: "rpc/decline_friend_request",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - Sent Friend Requests (Outgoing)
    
    func fetchSentRequests() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        do {
            let result: [SentFriendRequest] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_sent_friend_requests")
                .execute()
                .value
            
            self.sentRequests = result
            AppLogger.info("Fetched \(result.count) sent friend requests", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching sent friend requests",
                category: .social,
                op: PerformanceSignposts.Op.friendRequestList.rawValue,
                endpoint: "rpc/get_sent_friend_requests",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
                AppLogger.info("Friend request cancelled", category: .social)
            }
            return success
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error cancelling friend request",
                category: .social,
                op: PerformanceSignposts.Op.friendRequestWrite.rawValue,
                endpoint: "rpc/cancel_friend_request",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            guard let currentId = SupabaseManager.shared.currentUser?.id else { return false }
            let result: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("are_friends", params: [
                    "user_a": currentId.uuidString,
                    "user_b": userId.uuidString
                ])
                .execute()
                .value
            return result
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error checking friendship",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/are_friends",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    // MARK: - User Search
    
    /// Exact username lookup only. Broad discovery is contacts-based (see ContactsService).
    /// Only hits the server when the query looks like a valid username (no spaces, 3+ chars).
    func searchUsers(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
        
        guard cleaned.count >= 3,
              !cleaned.contains(" "),
              cleaned.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            searchResults = []
            return
        }
        
        do {
            struct SearchParams: Encodable {
                let search_query: String
                let result_limit: Int
            }
            
            let result: [UserSearchResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("search_users", params: SearchParams(search_query: cleaned, result_limit: 5))
                .execute()
                .value
            
            self.searchResults = result
            AppLogger.info("Username lookup: \(result.count) users matching '@\(cleaned)'", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error searching users",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/search_users",
                userId: SupabaseManager.shared.currentUser?.id
            )
            searchResults = []
        }
    }
    
    // MARK: - Shared Workouts
    
    func fetchReceivedWorkouts() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                let result: [ReceivedWorkoutDTO] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_received_workouts")
                    .execute()
                    .value
                
                let filteredResult = result.filter { !addressedWorkoutIds.contains($0.id) }
                
                self.receivedWorkouts = filteredResult
                AppLogger.info("Fetched \(result.count) received workouts (\(result.count - filteredResult.count) filtered as addressed)", category: .social)
                return
            } catch {
                if Task.isCancelled { return }
                
                let nsError = error as NSError
                let isRetryable = nsError.domain == NSURLErrorDomain && (
                    nsError.code == NSURLErrorTimedOut ||
                    nsError.code == NSURLErrorCancelled
                ) || error.localizedDescription.contains("502")
                
                if isRetryable && attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                if isRetryable {
                    AppLogger.warning("Received workouts fetch timed out after \(maxRetries) attempts", category: .social)
                } else {
                    // Cluster F (fingerprint 7297489e): offline -1005/-1009
                    // on dashboard notification carousel. Classifier downgrades
                    // transient to `.warning`; real RPC failures stay `.error`
                    // with pg_code.
                    _ = NetworkErrorClassifier.log(
                        error,
                        context: "Error fetching received workouts",
                        category: .social,
                        op: "social.fetch_received_workouts",
                        endpoint: "rpc/get_received_workouts",
                        userId: SupabaseManager.shared.currentUser?.id
                    )
                }
            }
        }
    }
    
    func fetchSentWorkouts() async {
        do {
            let result: [SentWorkout] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_sent_workouts")
                .execute()
                .value
            
            self.sentWorkouts = result
            AppLogger.info("Fetched \(result.count) sent workouts", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching sent workouts",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutList.rawValue,
                endpoint: "rpc/get_sent_workouts",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            AppLogger.info("Workout sent to friend", category: .social)

            // Update daily quest progress for sharing a workout
            await DailyQuestService.shared.onWorkoutShared()

            // 2026-04-29 — League Redesign Plan §C1.
            // +15 league points for sharing a workout. Capped at 3×/week
            // client-side via `WeeklyLeagueService.canAwardPoints` (server
            // cap in Sprint 3 §sprint3-caps-enforcement). Send-flow
            // success path only — failures fall through to the catch and
            // don't award.
            if WeeklyLeagueService.shared.canAwardPoints(source: .workoutSharedWithFriend) {
                await WeeklyLeagueService.shared.addPoints(source: .workoutSharedWithFriend)
            }

            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error sending workout",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "rpc/send_workout_to_friend",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    func acceptReceivedWorkout(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "accepted",
                    "responded_at": Self.iso8601.string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            AppLogger.info("Workout accepted", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error accepting workout",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(accept)",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    func declineReceivedWorkout(workoutId: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update([
                    "status": "declined",
                    "responded_at": Self.iso8601.string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            AppLogger.info("Workout declined", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error declining workout",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(decline)",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            AppLogger.info("Workout saved to favorites", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error saving workout to favorites",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(saved_to_favorites)",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return false
        }
    }
    
    func markWorkoutViewed(workoutId: UUID) async {
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("shared_workouts")
                .update(["viewed_at": Self.iso8601.string(from: Date())])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            NotificationManager.shared.updateBadgeCount()
            AppLogger.info("Workout marked as viewed", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error marking workout viewed",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(viewed_at)",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
                    "started_at": Self.iso8601.string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            AppLogger.info("Workout marked as started: \(workoutId)", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error marking workout started",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(started)",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
                    "completed_at": Self.iso8601.string(from: Date())
                ])
                .eq("id", value: workoutId.uuidString)
                .execute()
            
            await fetchReceivedWorkouts()
            AppLogger.info("Workout marked as completed", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error marking workout completed",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(completed)",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            
            AppLogger.info("Workout deleted from server: \(workoutId)", category: .social)
            return true
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error deleting workout",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(delete)",
                userId: SupabaseManager.shared.currentUser?.id
            )
            // Keep it addressed locally even if server delete fails
            AppLogger.warning("Keeping workout marked as addressed locally despite server error", category: .social)
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
            
            AppLogger.info("Workout saved: \(workoutId)", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error saving workout to server",
                category: .social,
                op: PerformanceSignposts.Op.sharedWorkoutWrite.rawValue,
                endpoint: "shared_workouts(saved)",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
        
        let sharedExercises = exercises.map { dto in
            SharedExercise(
                exerciseId: dto.exerciseId,
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
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        do {
            let result: [AppNotification] = try await SupabaseManager.shared.supabaseClient
                .from("app_notifications")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            self.notifications = result
            AppLogger.info("Fetched \(result.count) notifications", category: .social)
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching notifications",
                category: .social,
                op: PerformanceSignposts.Op.socialNotificationList.rawValue,
                endpoint: "app_notifications(select)",
                userId: userId
            )
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
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error fetching unread count",
                category: .social,
                op: PerformanceSignposts.Op.socialNotificationList.rawValue,
                endpoint: "rpc/get_unread_notification_count",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error marking notification read",
                category: .social,
                op: PerformanceSignposts.Op.socialNotificationWrite.rawValue,
                endpoint: "rpc/mark_notification_read",
                userId: SupabaseManager.shared.currentUser?.id
            )
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
            _ = NetworkErrorClassifier.log(
                error,
                context: "Error marking all notifications read",
                category: .social,
                op: PerformanceSignposts.Op.socialNotificationWrite.rawValue,
                endpoint: "rpc/mark_all_notifications_read",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }

    // MARK: - Mutual Friends

    func fetchMutualFriends(for targetUserId: UUID) async -> [MutualFriend] {
        guard SupabaseManager.shared.isAuthenticated else { return [] }
        do {
            let result: [MutualFriend] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_mutual_friends", params: ["p_target_user_id": targetUserId.uuidString])
                .execute()
                .value
            return result
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch mutual friends",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/get_mutual_friends",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return []
        }
    }

    // MARK: - Other User's Friends List (Instagram-style)

    /// Fetches the *target user's* accepted friend list (not the caller's).
    /// Powers `UserFriendsListView` reached via "See friends >" on a non-friend
    /// profile. Each entry includes per-row signals (`isMyFriend`,
    /// `hasOutgoingRequest`, `hasIncomingRequest`) so the UI can render the
    /// right CTA per row without an extra round-trip.
    /// Backed by RPC `get_user_friends_list(p_target_user_id, p_limit)` —
    /// see `supabase/20260504_get_user_friends_list.sql`.
    func fetchUserFriendsList(for targetUserId: UUID, limit: Int = 200) async -> [UserFriendListEntry] {
        guard SupabaseManager.shared.isAuthenticated else { return [] }
        do {
            let result: [UserFriendListEntry] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_user_friends_list", params: [
                    "p_target_user_id": targetUserId.uuidString,
                    "p_limit": String(max(1, min(limit, 500)))
                ])
                .execute()
                .value
            return result
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch user friends list",
                category: .social,
                op: PerformanceSignposts.Op.friendsList.rawValue,
                endpoint: "rpc/get_user_friends_list",
                userId: SupabaseManager.shared.currentUser?.id
            )
            return []
        }
    }
}

// MARK: - Data Models

/// Row of `get_user_friends_list(p_target_user_id, p_limit)` (#196). Used by
/// `UserFriendsListView` to render an Instagram-style list of *another user's*
/// friends with per-row CTA state (already friends / pending / can-add /
/// can-accept) so we don't need a per-row roundtrip.
struct UserFriendListEntry: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let isVerified: Bool?
    let isGoldVerified: Bool?
    /// True when the caller is already friends with this user — render a
    /// "Friends" badge instead of an "Add" button.
    let isMyFriend: Bool
    /// True when the caller has already sent this user a friend request and
    /// it's still pending — render "Pending".
    let hasOutgoingRequest: Bool
    /// True when this user has sent the caller a friend request that's still
    /// pending — render "Accept".
    let hasIncomingRequest: Bool

    var id: UUID { userId }

    var displayName: String {
        if let username, !username.isEmpty { return "@\(username)" }
        return name ?? "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
        case isMyFriend = "is_my_friend"
        case hasOutgoingRequest = "has_outgoing_request"
        case hasIncomingRequest = "has_incoming_request"
    }
}

struct MutualFriend: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?

    var id: UUID { userId }

    var displayName: String {
        name ?? username ?? "Unknown"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
    }
}

/// A user the caller has blocked. Populated by `get_blocked_users` RPC.
struct BlockedUser: Codable, Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let profilePhotoUrl: String?
    let blockedAt: Date?

    var id: UUID { userId }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let username, !username.isEmpty { return "@\(username)" }
        return "Blocked user"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case username
        case profilePhotoUrl = "profile_photo_url"
        case blockedAt = "blocked_at"
    }
}

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
    let isVerified: Bool?
    let isGoldVerified: Bool?

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
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    let isVerified: Bool?
    let isGoldVerified: Bool?
    
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
        case profilePhotoUrl = "from_user_profile_photo_url"
        case message
        case createdAt = "created_at"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    let isVerified: Bool?
    let isGoldVerified: Bool?
    
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
        case profilePhotoUrl = "to_user_profile_photo_url"
        case message
        case createdAt = "created_at"
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    let hasOutgoingRequest: Bool?
    let hasIncomingRequest: Bool?
    let isVerified: Bool?
    let isGoldVerified: Bool?

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
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
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
    let exerciseId: String?
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case name
        case sets
        case reps
        case restSeconds = "rest_seconds"
        case notes
    }
    
    init(exerciseId: String? = nil, name: String, sets: Int, reps: String, restSeconds: Int? = nil, notes: String? = nil) {
        self.exerciseId = exerciseId
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseId = try container.decodeIfPresent(String.self, forKey: .exerciseId)
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
    let senderIsVerified: Bool?
    let senderIsGoldVerified: Bool?

    // Identifiable conformance
    var id: UUID { workoutId }
    
    // Computed properties for exercise details
    var exerciseCount: Int {
        exercises?.count ?? exerciseNamesArray?.count ?? 0
    }
    
    var exerciseNames: [String] {
        if let exercises = exercises, !exercises.isEmpty {
            return exercises.map { $0.name }
        }
        return exerciseNamesArray ?? []
    }

    var exerciseIdNamePairs: [(id: String?, name: String)] {
        if let exercises = exercises, !exercises.isEmpty {
            return exercises.map { (id: $0.exerciseId, name: $0.name) }
        }
        return (exerciseNamesArray ?? []).map { (id: nil, name: $0) }
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
        case senderIsVerified = "sender_is_verified"
        case senderIsGoldVerified = "sender_is_gold_verified"
    }
}

struct SharedExerciseDTO: Codable, Identifiable {
    var id: UUID = UUID()
    let exerciseId: String?
    let name: String
    let sets: Int
    let reps: String
    var restSeconds: Int? = nil
    var notes: String? = nil
    
    init(exerciseId: String? = nil, name: String, sets: Int, reps: String, restSeconds: Int? = nil, notes: String? = nil) {
        self.exerciseId = exerciseId
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }
    
    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case name
        case sets
        case reps
        case restSeconds = "rest_seconds"
        case notes
    }
}

struct SelectedExerciseForFriend: Identifiable {
    var id = UUID()
    var exerciseId: String? = nil
    let name: String
    var category: String?
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int = 90
    var notes: String = ""
}

// Type alias for compatibility
typealias SharedWorkoutDTO = ReceivedWorkoutDTO
