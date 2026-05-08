//
//  RealtimeService.swift
//  Fit33
//
//  Supabase Realtime Service - Provides instant updates for social features
//  Handles: Friend requests, shared workouts, challenge updates
//
//  Created by Infrastructure Team - 2026-02-03
//

import Foundation
import Supabase
import Realtime

// MARK: - Realtime Service

/// Manages Supabase Realtime subscriptions for instant social updates
/// This eliminates the need for polling and provides immediate feedback
@MainActor
class RealtimeService: ObservableObject {
    static let shared = RealtimeService()
    
    // MARK: - Published State
    
    @Published var isConnected = false
    @Published var connectionError: String?
    
    /// Live feed of realtime events for debugging (most recent first, capped at 200)
    @Published var realtimeEventLog: [RealtimeEventEntry] = []
    
    /// Timestamp of the last realtime event received (any type)
    @Published var lastEventReceivedAt: Date?
    
    /// Timestamp of the last OPPONENT progress event received
    @Published var lastOpponentProgressAt: Date?
    
    /// Details of the last opponent progress update (for cross-device verification)
    @Published var lastOpponentProgressEvent: DailyProgressPayload?
    
    // MARK: - Channels
    
    private var friendshipsChannel: RealtimeChannelV2?
    private var sharedWorkoutsChannel: RealtimeChannelV2?
    private var challengesChannel: RealtimeChannelV2?
    private var dailyProgressChannel: RealtimeChannelV2?
    private var privateChallengeChannel: RealtimeChannelV2?
    private var communityChallengeChannel: RealtimeChannelV2?
    private var communityParticipantsChannel: RealtimeChannelV2?
    private var privateMembersChannel: RealtimeChannelV2?
    private var friendActivityFeedChannel: RealtimeChannelV2?
    private var privacyChangeChannel: RealtimeChannelV2?
    private var exercisesChannel: RealtimeChannelV2?

    /// Per-challenge reactions channel. Owned + torn down by the
    /// challenge-detail view that's currently visible. Replaces the
    /// previous "fetch on view-appear" reaction list with a live
    /// stream powered by `challenge_reactions` realtime INSERTs.
    /// Per PE invariant 9 the parent detail view is the sole owner;
    /// nested rows must NOT subscribe themselves.
    private var challengeReactionsChannel: RealtimeChannelV2?
    private var challengeReactionsListenerTask: Task<Void, Never>?
    private var subscribedReactionChallengeId: UUID?

    /// Persistent dashboard-level incoming-reactions channel — covers
    /// EVERY active challenge the user participates in, filtered by
    /// `recipient_id = me`. Drives the "comic-bubble shouts out of
    /// the dashboard widget" effect (`BattleCryShoutBubble`) on
    /// `ActiveChallengeHeaderRow` + `groupChallengeWidget` so the user
    /// sees an opponent's battle cry land WITHOUT having to drill
    /// into the challenge detail view. Owned by `connect()` /
    /// `disconnect()` (NOT per-view) — it's the social equivalent of
    /// the friendships / shared_workouts channels: one channel for
    /// the lifetime of the foreground session.
    private var incomingReactionsChannel: RealtimeChannelV2?
    private var incomingReactionsListenerTask: Task<Void, Never>?

    private var outgoingBattleCryAckChannel: RealtimeChannelV2?
    private var outgoingBattleCryAckListenerTask: Task<Void, Never>?
    private var didHydrateStickyIncomingFromDisk = false

    /// Opponent → me battle cries shown on the Home dashboard challenge
    /// cards (`BattleCryShoutBubble`). One entry per `challenge_id`
    /// (newest wins). Persists across tab switches and cold start
    /// (UserDefaults) until the user opens that challenge's detail view
    /// or backgrounds the app — see `dismissIncomingBattleCryBanner`
    /// and `clearIncomingBattleCriesForAppExit`.
    @Published private(set) var dashboardIncomingBattleCryByChallenge: [UUID: ChallengeReaction] = [:]

    /// Me → opponent battle cries still "in flight" until their device
    /// foregrounds Fit33 (server sets `recipient_opened_app_at`; sender
    /// hears UPDATE or reconciles on reconnect). Keyed by `reactionId`.
    @Published private(set) var dashboardOutgoingBattleCryByReactionId: [UUID: ChallengeReaction] = [:]

    /// Bumps whenever incoming/outgoing dashboard battle-cry maps change so
    /// `BattleCryShoutBubble` can sync without requiring `[UUID: …]` to be
    /// `Equatable` for `.onChange`.
    @Published private(set) var dashboardBattleCryRenderToken: UInt64 = 0

    private static let stickyIncomingPersistenceKey = "Fit33.dashboardStickyIncomingBattleCries.v1"

    /// Suppresses duplicate dashboard + home-widget paint when the same
    /// battle cry lands via `UNUserNotificationCenter` (`willPresent` /
    /// silent push) and Supabase realtime within a short window.
    private var lastIncomingBattleCryDedupeKey: String?
    private var lastIncomingBattleCryDedupeAt: Date?

    /// `true` when `MainTabView` is on the Home tab (index 0) and
    /// `scenePhase != .background`. Used only for analytics-style gating;
    /// incoming battle cry UI is **sticky** and no longer cleared when
    /// switching tabs.
    @Published private(set) var isDashboardBattleCryHostVisible: Bool = false

    // MARK: - Dashboard battle cry host (Home tab + foreground)

    /// Called from `MainTabView` when the Home tab + scene phase change.
    func setDashboardBattleCryHostVisible(_ visible: Bool) {
        guard visible != isDashboardBattleCryHostVisible else { return }
        isDashboardBattleCryHostVisible = visible
    }

    /// Clears the opponent→me dashboard bubble for one challenge when the
    /// user opens that challenge's detail surface.
    func dismissIncomingBattleCryBanner(for challengeId: UUID) {
        guard dashboardIncomingBattleCryByChallenge.removeValue(forKey: challengeId) != nil else { return }
        persistStickyIncomingBattleCries()
        bumpBattleCryDashboardRenderToken()
    }

    /// Clears all incoming dashboard battle cries when the app is sent to
    /// the background (user "exited" Fit33 in the product sense).
    func clearIncomingBattleCriesForAppExit() {
        guard !dashboardIncomingBattleCryByChallenge.isEmpty else { return }
        dashboardIncomingBattleCryByChallenge.removeAll()
        persistStickyIncomingBattleCries()
        bumpBattleCryDashboardRenderToken()
    }

    /// Tear down all battle-cry dashboard state on sign-out / account switch.
    func clearAllDashboardBattleCryStateForLogout() {
        dashboardIncomingBattleCryByChallenge.removeAll()
        dashboardOutgoingBattleCryByReactionId.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.stickyIncomingPersistenceKey)
        didHydrateStickyIncomingFromDisk = false
        bumpBattleCryDashboardRenderToken()
    }

    /// Registers a just-sent reaction so the sender sees a "delivered when
    /// they open Fit33" bubble until `recipient_opened_app_at` is set.
    func registerPendingOutgoingBattleCry(_ reaction: ChallengeReaction) {
        dashboardOutgoingBattleCryByReactionId[reaction.reactionId] = reaction
        bumpBattleCryDashboardRenderToken()
    }

    /// Latest outgoing pending reaction for a challenge card (may be nil).
    func latestPendingOutgoingBattleCry(for challengeId: UUID) -> ChallengeReaction? {
        dashboardOutgoingBattleCryByReactionId.values
            .filter { $0.challengeId == challengeId }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    /// Recipient foreground — marks unread rows so senders get realtime UPDATE.
    func ackBattleCryReceiptsIfRecipient() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        let now = Date()
        if let last = lastAckBattleCryRpcAt, now.timeIntervalSince(last) < 45 { return }
        lastAckBattleCryRpcAt = now
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("ack_my_pending_battle_cry_receipts")
                .execute()
        } catch {
            _ = NetworkErrorClassifier.log(
                error,
                context: "ack_my_pending_battle_cry_receipts",
                category: .network,
                endpoint: "rpc/ack_my_pending_battle_cry_receipts",
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }

    private var lastAckBattleCryRpcAt: Date?

    private func bumpBattleCryDashboardRenderToken() {
        dashboardBattleCryRenderToken &+= 1
    }

    /// Foreground APNs path (`NotificationManager` `willPresent`) so the
    /// dashboard `BattleCryShoutBubble` paints even when the realtime
    /// socket is stale or the INSERT event is delayed.
    func ingestIncomingBattleCryFromNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let challengeIdStr = userInfo["challenge_id"] as? String,
              let challengeId = UUID(uuidString: challengeIdStr),
              let senderIdStr = userInfo["from_user_id"] as? String,
              let senderId = UUID(uuidString: senderIdStr),
              let emoji = userInfo["reaction_emoji"] as? String,
              let text = userInfo["reaction_text"] as? String,
              let me = SupabaseManager.shared.currentUser?.id else { return }
        if senderId == me { return }

        let reactionKey = (userInfo["reaction_key"] as? String) ?? ""
        let category = (userInfo["reaction_category"] as? String) ?? "trash_talk"
        let reactionId = (userInfo["reaction_id"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()
        let senderName = userInfo["from_user_name"] as? String

        let reaction = ChallengeReaction(
            reactionId: reactionId,
            challengeId: challengeId,
            senderId: senderId,
            senderName: senderName,
            senderPhotoUrl: nil,
            recipientId: me,
            reactionKey: reactionKey,
            reactionEmoji: emoji,
            reactionText: text,
            reactionCategory: category,
            createdAt: Date()
        )
        applyIncomingBattleCry(reaction, widgetSenderDisplayName: senderName)
    }

    // MARK: - Debounce State
    
    /// Debounce task for batched community challenge progress refreshes.
    /// Collects challenge IDs over a 3s window, then does ONE refresh for all.
    private var communityProgressDebounceTask: Task<Void, Never>?
    private var pendingCommunityRefreshChallengeIds: Set<String> = []
    
    /// Separate debounce for auto-tracked challenges (steps, active_minutes, etc.)
    /// Uses a longer 6s window since HealthKit events fire in rapid bursts.
    private var autoTrackedDebounceTask: Task<Void, Never>?
    
    private var privateProgressDebounceTask: Task<Void, Never>?
    
    /// Periodic refresh timer — now a 120s safety-net fallback since event-driven
    /// debouncing handles the primary refresh path for both manual and auto-tracked challenges.
    private var autoTrackedRefreshTimer: Task<Void, Never>?
    private static let autoTrackedRefreshInterval: UInt64 = 120_000_000_000 // 120s fallback (was 90s)
    
    /// Timestamp when community view became visible — used for adaptive refresh cadence
    private var communityViewBecameVisibleAt: Date?
    
    private var hasConfiguredCallbacks = false
    
    // MARK: - Throttle State (prevent cascading fetches)
    
    /// Last time we fetched community challenges from a realtime event.
    /// Used to throttle rapid-fire events from triggering redundant network calls.
    private var lastCommunityFetchTime: Date?
    private static let communityFetchThrottleInterval: TimeInterval = 3.0 // Don't re-fetch within 3s
    
    /// Last time we fetched 1v1/group challenges from a realtime event.
    private var lastChallengeFetchTime: Date?
    private static let challengeFetchThrottleInterval: TimeInterval = 3.0 // Don't re-fetch within 3s
    
    /// Last time we fetched private challenges from a realtime event.
    private var lastPrivateFetchTime: Date?
    private static let privateFetchThrottleInterval: TimeInterval = 3.0
    
    /// Throttled community challenge fetch — prevents cascading duplicate network calls.
    private func throttledCommunityFetch() async {
        let now = Date()
        if let last = lastCommunityFetchTime, now.timeIntervalSince(last) < Self.communityFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastCommunityFetchTime = now
        await CommunityChallengeService.shared.fetchMyChallenges()
    }
    
    /// Throttled 1v1/group challenge fetch — prevents cascading duplicate network calls.
    private func throttledChallengeFetch() async {
        let now = Date()
        if let last = lastChallengeFetchTime, now.timeIntervalSince(last) < Self.challengeFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastChallengeFetchTime = now
        await ChallengeService.shared.fetchActiveChallenges()
        await ChallengeService.shared.fetchActiveGroupChallenges()
    }
    
    /// Throttled private challenge fetch — prevents cascading duplicate network calls.
    private func throttledPrivateFetch() async {
        let now = Date()
        if let last = lastPrivateFetchTime, now.timeIntervalSince(last) < Self.privateFetchThrottleInterval {
            return // Already fetched very recently
        }
        lastPrivateFetchTime = now
        await PrivateChallengeService.shared.fetchMyChallenges()
    }
    
    /// Returns true if this challenge type is manually input by the user (protein, hydration, etc.).
    /// Manual-input challenges should refresh instantly when a real-time event arrives.
    /// Auto-tracked challenges (steps, active minutes) refresh on a periodic cadence instead.
    private static func isManualInputType(_ challengeType: String?) -> Bool {
        guard let type = challengeType else { return true } // Default to instant if unknown
        switch type {
        case "protein", "hydrate", "sleep", "lift", "workout_streak":
            return true  // User explicitly logs these — refresh instantly
        case "steps", "active_minutes", "walk", "run", "calories":
            return false // HealthKit auto-syncs these — refresh on cadence
        default:
            return true  // Unknown types default to instant
        }
    }
    
    /// Look up the challenge type for a community challenge by its ID.
    /// Returns nil if the challenge isn't in the user's local list.
    private func lookupCommunityChallengeType(challengeId: String) -> String? {
        guard let uuid = UUID(uuidString: challengeId) else { return nil }
        return CommunityChallengeService.shared.myChallenges
            .first(where: { $0.challengeId == uuid })?.challengeType
    }
    
    /// Look up the challenge type for a private challenge by its ID.
    private func lookupPrivateChallengeType(challengeId: String) -> String? {
        guard let uuid = UUID(uuidString: challengeId) else { return nil }
        return PrivateChallengeService.shared.myChallenges
            .first(where: { $0.challengeId == uuid })?.challengeType
    }
    
    // MARK: - Callbacks
    
    /// Called when a new friend request is received
    var onFriendRequestReceived: ((FriendRequestPayload) -> Void)?
    
    /// Called when a friend request is accepted
    var onFriendRequestAccepted: ((FriendRequestPayload) -> Void)?
    
    /// Called when a new workout is shared with the user
    var onWorkoutReceived: ((SharedWorkoutPayload) -> Void)?
    
    /// Called when a challenge invite is received
    var onChallengeInviteReceived: ((ChallengePayload) -> Void)?
    
    /// Called when challenge progress is updated
    var onChallengeProgressUpdated: ((ChallengePayload) -> Void)?
    
    /// Called when opponent's daily progress updates (for live challenge widget)
    var onOpponentDailyProgressUpdated: ((DailyProgressPayload) -> Void)?

    /// Called when a new battle cry / power-up reaction is inserted
    /// for the currently-subscribed challenge (set via
    /// `subscribeChallengeReactions(challengeId:)`). Detail views set
    /// this in `.task` to drive the `ReactiveBattleFeed` fly-in
    /// animation + confetti burst.
    var onChallengeReactionReceived: ((ChallengeReaction) -> Void)?
    
    private init() {}
    
    // MARK: - Safe JSON Value Extraction
    
    /// Safely extracts an Int from a JSON value that may arrive as AnyJSON, Int, Double, NSNumber, or String.
    /// Supabase Realtime v2.40+ wraps ALL record values in AnyJSON enum (.integer, .double, .string, etc.)
    /// Direct `as? Int` FAILS silently on AnyJSON.integer(42), causing progress updates to be dropped.
    private func jsonInt(_ value: Any?) -> Int? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let i = json.intValue { return i }
            if let d = json.doubleValue { return Int(d) }
            if let s = json.stringValue, let i = Int(s) { return i }
            return nil
        }
        // ── Fallback for raw Swift types (manual dict construction, tests, etc.) ──
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }
    
    /// Safely extracts a String from a JSON value (handles AnyJSON wrapper)
    private func jsonString(_ value: Any?) -> String? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let s = json.stringValue { return s }
            if let i = json.intValue { return String(i) }
            if let d = json.doubleValue { return String(d) }
            if let b = json.boolValue { return String(b) }
            return nil
        }
        // ── Fallback for raw Swift types ──
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let d = value as? Double { return String(Int(d)) }
        if let i = value as? Int { return String(i) }
        return nil
    }
    
    /// Safely extracts a Bool from a JSON value (handles AnyJSON wrapper)
    private func jsonBool(_ value: Any?) -> Bool? {
        // ── AnyJSON (the ACTUAL type from Supabase Realtime v2) ──
        if let json = value as? AnyJSON {
            if let b = json.boolValue { return b }
            if let i = json.intValue { return i != 0 }
            if let s = json.stringValue { return s.lowercased() == "true" || s == "1" }
            return nil
        }
        // ── Fallback for raw Swift types ──
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let i = value as? Int { return i != 0 }
        if let s = value as? String { return s.lowercased() == "true" || s == "1" }
        return nil
    }
    
    // MARK: - Event Logging
    
    /// Log a realtime event for debugging visibility
    func logRealtimeEvent(type: String, source: String, details: String, isError: Bool = false) {
        let entry = RealtimeEventEntry(
            timestamp: Date(),
            type: type,
            source: source,
            details: details,
            isError: isError
        )
        realtimeEventLog.insert(entry, at: 0)
        // Cap at 200 entries
        if realtimeEventLog.count > 200 {
            realtimeEventLog = Array(realtimeEventLog.prefix(200))
        }
        lastEventReceivedAt = Date()
    }
    
    // MARK: - Connection Management
    
    private var isConnecting = false
    private var lastConnectTime: Date?
    private static let connectThrottleInterval: TimeInterval = 10

    /// Phase 2.1 Snappiness Overhaul (PerfFlags.phase2RealtimeGate).
    ///
    /// When `disconnect()` is invoked from a brief background trip, we no
    /// longer tear down the WebSocket immediately. Instead we schedule a
    /// 60s "grace" timer here; if the user foregrounds again within the
    /// window the timer is cancelled and the live socket is reused —
    /// realtime events that arrived during the background blip deliver
    /// LIVE instead of being missed during the post-foreground reconnect
    /// window.
    ///
    /// See `scheduleGraceDisconnect(after:)` / `cancelGraceDisconnect()` /
    /// `actuallyDisconnectAll()` below.
    private var graceDisconnectTask: Task<Void, Never>?

    /// Threshold past which we consider the realtime channel "stale" / probably
    /// dead — exceeded `Date().timeIntervalSince(lastEventReceivedAt)` means
    /// either no events ever arrived OR iOS killed the WebSocket while we
    /// were suspended. The connect-throttle (`connectThrottleInterval`) is
    /// bypassed once we cross this threshold so a foreground retry actually
    /// re-arms the channel instead of silently no-op'ing.
    ///
    /// Sync-triage 2026-04-28 — paired with `forceReconnectIfStale()` below.
    static let staleEventThreshold: TimeInterval = 30

    /// Start all realtime subscriptions for the current user
    func connect() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("Cannot connect - not authenticated", category: .network)
            return
        }
        
        // Prevent concurrent or rapid reconnections
        if isConnecting {
            AppLogger.debug("⏭️ [REALTIME] Skipping connect — already connecting", category: .network)
            return
        }
        // 2026-04-28 sync-triage Layer B — the 10s connect-throttle protects
        // against rapid scenePhase storms, but it MUST yield when the
        // channel looks dead. If `lastEventReceivedAt` is older than
        // `staleEventThreshold` (or `nil`), bypass the throttle so the
        // foreground retry path can actually rebuild the WebSocket.
        // Without this bypass, a user who backgrounds for 30s and
        // returns gets a "skipped — connected 9s ago" no-op while the
        // socket has been dead for 25s.
        let recentlyConnected = lastConnectTime.map {
            Date().timeIntervalSince($0) < Self.connectThrottleInterval
        } ?? false
        let recentEvent = lastEventReceivedAt.map {
            Date().timeIntervalSince($0) < Self.staleEventThreshold
        } ?? false
        if isConnected && recentlyConnected && recentEvent {
            let connAge = lastConnectTime.map { Int(Date().timeIntervalSince($0)) } ?? -1
            AppLogger.debug("⏭️ [REALTIME] Skipping connect — connected \(connAge)s ago, last event fresh", category: .network)
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        
        if isConnected || friendshipsChannel != nil {
            AppLogger.debug("Cleaning up existing channels before reconnecting...", category: .network)
            // Internal teardown-and-rebuild path needs the immediate disconnect,
            // never the Phase 2.1 grace timer — we're about to re-subscribe and
            // a deferred disconnect would race the new channels to nil. The
            // public `disconnect()` flag-gates the grace path; this internal
            // path bypasses it.
            await actuallyDisconnectAll()
        }
        
        AppLogger.debug("Connecting to realtime channels...", category: .network)

        hydrateStickyIncomingBattleCriesFromDiskIfNeeded()

        // Subscribe to all relevant channels
        await subscribeFriendships(userId: userId)
        await subscribeSharedWorkouts(userId: userId)
        await subscribeChallenges(userId: userId)
        await subscribeDailyProgress(userId: userId)
        await subscribePrivateChallengeProgress(userId: userId)
        await subscribeCommunityChallengeProgress(userId: userId)
        await subscribeCommunityParticipants(userId: userId)
        await subscribePrivateMembers(userId: userId)
        await subscribeFriendActivityFeed(userId: userId)
        await subscribePrivacyChanges(userId: userId)
        await subscribeExercises(userId: userId)
        await subscribeIncomingReactions(userId: userId)
        await subscribeOutgoingBattleCryAcks(userId: userId)

        // Start periodic cadence refresh for auto-tracked challenges (steps, active_minutes, etc.)
        startAutoTrackedRefreshTimer()

        isConnected = true
        connectionError = nil
        lastConnectTime = Date()
        AppLogger.info("Connected to all channels", category: .network)
        logRealtimeEvent(type: "CONNECTED", source: "RealtimeService",
                        details: "✅ All channels active: friendships, shared_workouts, challenges, daily_progress, private_challenges, community_challenges, community_participants, private_members, friend_activity_feed, privacy_changes, exercises, incoming_reactions, outgoing_reaction_acks + auto-tracked refresh timer")

        // ─── Sync-triage 2026-04-28 Layer B — post-connect canonical resync ───
        //
        // Bug-intel `721fe5d6` (HIGH, 2026-04-27): a freshly-onboarded user
        // got the friend-request push but the card never appeared on home.
        // Auth/JWT propagation can race the initial RPC fetches AND any
        // INSERT event that fires server-side BEFORE every channel above
        // finishes `await channel.subscribe()`. Both paths are at risk, so
        // every `connect()` ends with a one-shot resync of every
        // `@Published` array the dashboard carousel + activity feed read.
        //
        // 2026-04-28 (Layer B) — the original (Phase 3+4) resync only
        // hit 4 surfaces; under the dead-socket scenario, every social
        // service is at risk simultaneously, so the resync now covers
        // the same 10 surfaces as the foreground social re-sync in
        // `Fit33App.scenePhase == .active`. `connect()` becomes the
        // single canonical "everything social, refreshed" entry point.
        //
        // 2026-04-28 (Layer B.2) — added 1v1 active challenges
        // (`ChallengeService.fetchActiveChallenges`) to the resync. The
        // previous 9-surface list excluded 1v1 active, leaving the
        // dashboard's `DashboardChallengesWrapper` widget AND the
        // home-screen `ActiveChallengeWidget` dependent on opponent
        // realtime events firing post-reconnect. After a stale
        // dead-socket window, missed events between disconnect and
        // re-subscribe never arrive — without this explicit fetch the
        // widgets sat stale until the user logged HK data themselves.
        // `fetchActiveChallenges` triggers
        // `cacheActiveChallenges` → `ActiveChallengeWidgetBridge.publish`,
        // which writes the App Group payload + reloads widget timelines
        // in one pass.
        //
        // We detach because `connect()` is awaited from the main
        // foreground pipeline and we don't want to extend that critical
        // path; per-service `isAuthenticated` guards + `RequestCoalescer`
        // de-dupe make these fetches cheap when the foreground re-sync
        // already kicked them off (Data invariant #4 — no duplicate
        // fetches; coalescer turns parallel callers into one network
        // roundtrip).
        Task.detached(priority: .userInitiated) {
            await RealtimeService.shared.reconcileAcknowledgedOutgoingBattleCriesFromServer()
            // Friend request cards
            await FriendService.shared.fetchPendingRequests()
            // 1v1 challenge invite cards (received)
            await ChallengeService.shared.fetchPendingInvites()
            // 1v1 challenge cards I sent (so the sender carousel updates
            // when the opponent accepts)
            await ChallengeService.shared.fetchPendingSentChallenges()
            // 1v1 active challenges — drives `DashboardChallengesWrapper`
            // active-challenge widget AND the home-screen widget (via
            // `ActiveChallengeWidgetBridge.publish`). Internal 1s
            // throttle + RequestCoalescer keep this cheap when the
            // foreground fan-out already ran it.
            await ChallengeService.shared.fetchActiveChallenges()
            // Group challenge invites (`isMyInvitePending` filter on
            // `activeGroupChallenges` drives the group invite card)
            await ChallengeService.shared.fetchActiveGroupChallenges()
            // Private challenge invites (carousel)
            await PrivateChallengeService.shared.fetchPendingInvites()
            // Private challenge list (the body of accepted private
            // challenges — friends sub for new members landed here)
            await PrivateChallengeService.shared.fetchMyChallenges()
            // Community challenges (leaderboard widget)
            await CommunityChallengeService.shared.fetchMyChallenges()
            // Recent Activity feed (Joe-can't-see-Paul's-workouts)
            await ActivityFeedService.shared.fetchFeed()
            // Received-workout cards (carousel)
            await FriendService.shared.fetchReceivedWorkouts()

            // Hoist counts into local lets — `AppLogger.debug`'s message param
            // is `@autoclosure` (deferred), and Swift won't allow `await` in a
            // non-async autoclosure. Reading these MainActor-isolated
            // @Published values requires `await` to hop actors, so capture
            // them ahead of the log call. Cheap (n main-actor hops, no
            // network).
            let frCount = await FriendService.shared.pendingRequests.count
            let ciCount = await ChallengeService.shared.pendingInvites.count
            let csCount = await ChallengeService.shared.pendingSentChallenges.count
            let caCount = await ChallengeService.shared.activeChallenges.count
            let cgCount = await ChallengeService.shared.activeGroupChallenges.count
            let pcCount = await PrivateChallengeService.shared.pendingInvites.count
            let pmCount = await PrivateChallengeService.shared.myChallenges.count
            let cmCount = await CommunityChallengeService.shared.myChallenges.count
            let afCount = await ActivityFeedService.shared.activities.count
            let rwCount = await FriendService.shared.receivedWorkouts.count
            AppLogger.debug(
                "[REALTIME] Post-connect canonical resync complete (friend req: \(frCount), 1v1 inv: \(ciCount), 1v1 sent: \(csCount), 1v1 active: \(caCount), group: \(cgCount), priv inv: \(pcCount), priv mine: \(pmCount), comm mine: \(cmCount), feed: \(afCount), recv workouts: \(rwCount))",
                category: .network
            )
        }
    }

    /// Sync-triage 2026-04-28 Layer B — reconnect realtime if the channel
    /// looks dead.
    ///
    /// The previous Phase 3+4 fix called `connect()` only when
    /// `RealtimeService.shared.isConnected == false`. That's a trap —
    /// `isConnected` is a Swift `@Published` Bool, not a live socket-state
    /// query. iOS suspends the app, the underlying WebSocket dies, but
    /// `isConnected` stays `true` because nothing in this service flips it
    /// back to `false` on socket close. Result: the foreground retry path
    /// became a permanent no-op for returning users, and realtime events
    /// from the background never landed.
    ///
    /// The cheapest reliable "is the socket dead?" signal is "did we receive
    /// ANY realtime event recently?" — `lastEventReceivedAt` is updated by
    /// every postgres_changes payload via `logRealtimeEvent`, and if it's
    /// older than `staleEventThreshold` (30s), the channel is at minimum
    /// suspect. We tear down + re-subscribe; the post-connect canonical
    /// resync above handles the missed-event window.
    ///
    /// Idempotent: when the channel IS healthy (recent event), the
    /// throttle inside `connect()` itself short-circuits and this is a
    /// cheap no-op.
    func forceReconnectIfStale() async {
        // Phase 2.1 Snappiness Overhaul (PerfFlags.phase2RealtimeGate) —
        // foreground-within-grace fast path. If we're inside a pending
        // 60s grace window AND the socket is still alive (it should be —
        // the SDK's phx_ping heartbeat keeps it warm), cancel the grace
        // timer, log the save, and skip the entire reconnect cycle (which
        // today does a forceReconnect + 10-RPC post-connect resync).
        // If `isConnected` flipped to false during the background trip
        // (iOS suspended the network despite our intent), we fall through
        // to the existing safety net below.
        if PerfFlags.phase2RealtimeGate {
            cancelGraceDisconnect()
            if isConnected {
                AppLogger.info("Realtime: foreground within grace window, socket alive, skipping reconnect", category: .network)
                return
            }
        }

        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("[REALTIME] forceReconnectIfStale: not authenticated, skipping", category: .network)
            return
        }

        let now = Date()
        let lastEventAge: TimeInterval = lastEventReceivedAt.map {
            now.timeIntervalSince($0)
        } ?? .greatestFiniteMagnitude
        let isStale = lastEventAge > Self.staleEventThreshold

        // Sync-triage 2026-05-02 (Layer E) — staleness alone is NOT enough.
        // The `.background` scenePhase observer in `Fit33App.swift` fires
        // `Task { await RealtimeService.shared.disconnect() }` to save
        // battery; that nils every channel + sets `isConnected = false`
        // but does NOT touch `lastEventReceivedAt`. A user who locks
        // their phone for 5s after a recent event would foreground into
        // a "channel healthy, last event 5s ago" no-op, leaving the
        // app subscribed to NOTHING while the staleness gate stayed
        // closed. Symptoms: friend requests / battle cries / opponent
        // step updates only appear after the foreground social fan-out
        // (`Priority 2`, line ~1114 of `Fit33App.swift`) finishes its
        // ~1s of RPCs — not real time.
        //
        // Treat "channels actually torn down" as the dominant signal.
        // `friendshipsChannel` is the canonical "any channel up" probe
        // (it's the first channel `connect()` opens; it's the last one
        // `disconnect()` nils). `!isConnected` is a belt-and-suspenders
        // catch for the rare case where a channel ref leaks past a
        // disconnect.
        let channelsAreDown = friendshipsChannel == nil || !isConnected

        if isStale || channelsAreDown {
            let reason: String
            if channelsAreDown && !isStale {
                reason = "channels torn down (likely from prior backgrounding)"
            } else if channelsAreDown && isStale {
                reason = "channels torn down + stale (last event \(lastEventReceivedAt == nil ? "never" : "\(Int(lastEventAge))s ago"))"
            } else {
                reason = "stale (last event \(lastEventReceivedAt == nil ? "never" : "\(Int(lastEventAge))s ago"))"
            }
            AppLogger.info(
                "🔄 [REALTIME] Reconnecting — \(reason)",
                category: .network
            )
            logRealtimeEvent(
                type: "FORCE_RECONNECT",
                source: "RealtimeService",
                details: "🔄 \(reason). Tearing down + re-subscribing."
            )
            // Tear down so `connect()` doesn't bail on the
            // `if isConnected || friendshipsChannel != nil { disconnect }`
            // happy-path inside `connect()` — we want a deterministic
            // teardown + fresh subscribe even if it ran <10s ago.
            // Use `actuallyDisconnectAll()` directly (NOT the public
            // `disconnect()` wrapper) so the Phase 2.1 grace timer doesn't
            // defer the teardown beneath the immediate `connect()` below.
            await actuallyDisconnectAll()
            await connect()
        } else {
            AppLogger.debug(
                "[REALTIME] forceReconnectIfStale: channel healthy (last event \(Int(lastEventAge))s ago) — no-op",
                category: .network
            )
        }
    }
    
    /// Disconnect from all realtime channels.
    ///
    /// Phase 2.1 Snappiness Overhaul (`PerfFlags.phase2RealtimeGate`):
    /// when ON, this defers the actual teardown via `scheduleGraceDisconnect()`
    /// — the WebSocket stays alive for 60s of background time so events
    /// arriving during brief background trips deliver LIVE. If the user
    /// foregrounds within the window, `forceReconnectIfStale()` calls
    /// `cancelGraceDisconnect()` and the post-foreground reconnect cycle is
    /// skipped entirely.
    ///
    /// When the flag is OFF the path is byte-identical to today's behavior
    /// (immediate `actuallyDisconnectAll()`).
    ///
    /// Internal callers inside this service (`connect()`, `forceReconnectIfStale()`)
    /// MUST call `actuallyDisconnectAll()` directly — they need a deterministic
    /// teardown before the immediately-following `connect()`. External callers
    /// (Fit33App scenePhase handler, SupabaseManager sign-out) continue to call
    /// `disconnect()` and pick up the flag-gated behavior automatically.
    func disconnect() async {
        if PerfFlags.phase2RealtimeGate {
            scheduleGraceDisconnect()
        } else {
            await actuallyDisconnectAll()
        }
    }

    /// Schedule the real disconnect to fire after a grace window (default 60s).
    ///
    /// Cancels any previously pending grace task so consecutive `disconnect()`
    /// calls from rapid scenePhase storms don't stack. The timer fires on the
    /// MainActor (this whole service is `@MainActor`) and the task self-nils
    /// after `actuallyDisconnectAll()` returns so the property always reflects
    /// "is a teardown pending".
    ///
    /// Public so Phase 2.2 (Fit33App scenePhase extension) and tests can drive it.
    func scheduleGraceDisconnect(after seconds: TimeInterval = 60) {
        graceDisconnectTask?.cancel()
        let secondsInt = Int(seconds)
        AppLogger.debug("⏳ [REALTIME] Scheduling grace disconnect in \(secondsInt)s — keeping socket alive across brief background trip", category: .network)
        graceDisconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self else { return }
            AppLogger.info("⏰ [REALTIME] Grace window expired (\(secondsInt)s) — disconnecting", category: .network)
            await self.actuallyDisconnectAll()
            self.graceDisconnectTask = nil
        }
    }

    /// Cancel a pending grace disconnect (foreground-within-grace fast path).
    ///
    /// Logs `realtime.grace_save` ONLY when there was actually a pending
    /// grace task — that's the proof signal that today's "events during
    /// brief background trips were missed by the post-foreground reconnect"
    /// is now fixed.
    ///
    /// Design note: per the Phase 2.1 spec, this function does NOT itself
    /// kick `forceReconnectIfStale()` if the socket happens to be dead.
    /// Its sole caller is `forceReconnectIfStale()` itself (top of the
    /// function); kicking from here would recurse. The fall-through into
    /// `forceReconnectIfStale`'s existing body is the safety net for the
    /// "iOS suspended the network despite our intent" case.
    ///
    /// Public so Phase 2.2 (Fit33App scenePhase extension) and tests can drive it.
    func cancelGraceDisconnect() {
        let hadPending = graceDisconnectTask != nil
        graceDisconnectTask?.cancel()
        graceDisconnectTask = nil
        if hadPending {
            AppLogger.info("realtime.grace_save: socket kept alive across background", category: .network)
        }
    }

    /// Immediate teardown of all realtime channels — the original body of
    /// `disconnect()`. Internal callers needing a deterministic synchronous
    /// teardown (`connect()` cleanup, `forceReconnectIfStale()` rebuild)
    /// MUST call this directly to bypass the Phase 2.1 grace timer.
    ///
    /// Cancels any pending grace task at the top so a stale grace timer
    /// firing post-reconnect can't nil a freshly-rebuilt channel set.
    private func actuallyDisconnectAll() async {
        // Belt-and-suspenders: a pending grace task whose Task.sleep wakes
        // up AFTER we've already torn down + reconnected would call
        // `actuallyDisconnectAll()` again and silently kill the live socket.
        // Cancel here (cheap, idempotent) so the timer is dead before the
        // teardown body runs.
        graceDisconnectTask?.cancel()
        graceDisconnectTask = nil

        AppLogger.debug("Disconnecting from channels...", category: .network)
        
        if let channel = friendshipsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = sharedWorkoutsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = challengesChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = dailyProgressChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = privateChallengeChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = communityChallengeChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = communityParticipantsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = privateMembersChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = friendActivityFeedChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = privacyChangeChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        if let channel = exercisesChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        incomingReactionsListenerTask?.cancel()
        incomingReactionsListenerTask = nil
        await unsubscribeOutgoingBattleCryAcks()
        if let channel = incomingReactionsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        await unsubscribeChallengeReactions()

        // Also tear down service-level realtime channels so they can re-subscribe on reconnect.
        // Without this, the services hold a stale channel reference and the guard in
        // subscribeToRealtimeUpdates() prevents re-subscription after background → foreground.
        await PrivateChallengeService.shared.unsubscribeFromRealtimeUpdates()
        await CommunityChallengeService.shared.unsubscribeFromRealtimeUpdates()
        
        // Cancel any pending debounced refresh tasks and the cadence timer
        communityProgressDebounceTask?.cancel()
        privateProgressDebounceTask?.cancel()
        communityProgressDebounceTask = nil
        privateProgressDebounceTask = nil
        stopAutoTrackedRefreshTimer()
        
        friendshipsChannel = nil
        sharedWorkoutsChannel = nil
        challengesChannel = nil
        dailyProgressChannel = nil
        privateChallengeChannel = nil
        communityChallengeChannel = nil
        communityParticipantsChannel = nil
        privateMembersChannel = nil
        friendActivityFeedChannel = nil
        privacyChangeChannel = nil
        exercisesChannel = nil
        incomingReactionsChannel = nil

        // Sync-triage 2026-05-02 (Layer E) — clear the last-event-time
        // along with the channels. The previous version left this set,
        // which fooled `forceReconnectIfStale()` into thinking the
        // channel was still healthy after a fresh disconnect. The
        // staleness gate now sees `nil → .greatestFiniteMagnitude`
        // and reliably triggers a reconnect on the next foreground.
        lastEventReceivedAt = nil
        isDashboardBattleCryHostVisible = false

        isConnected = false
        AppLogger.info("Disconnected from all channels", category: .network)
    }
    
    // MARK: - Privacy Changes Subscription (League + Activity Feed)
    
    /// Subscribe to privacy_change_events — unified signal table for all privacy toggles.
    /// When any user toggles privacy_hide_league or privacy_hide_activity, a Postgres trigger
    /// inserts a row → this subscription fires → relevant data refreshes instantly.
    private func subscribePrivacyChanges(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("privacy_changes-\(userId.uuidString)")
        
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "privacy_change_events"
        )
        
        Task { [weak self] in
            for await action in insertions {
                guard let self else { break }
                let record = action.record
                let eventUserId = self.jsonString(record["user_id"]) ?? ""
                let changeType = self.jsonString(record["change_type"]) ?? ""
                let isHidden = self.jsonBool(record["is_hidden"]) ?? false
                
                guard eventUserId != userId.uuidString else { continue }
                
                switch changeType {
                case "league":
                    let eventGroupId = self.jsonString(record["group_id"]) ?? ""
                    let myGroupId = await WeeklyLeagueService.shared.standing?.groupId.uuidString
                    guard eventGroupId == myGroupId else { continue }
                    
                    AppLogger.debug("🏆 [LEAGUE] Privacy change: user \(eventUserId.prefix(8)) is now \(isHidden ? "hidden" : "visible") — refreshing leaderboard", category: .social)
                    self.logRealtimeEvent(type: "LEAGUE_PRIVACY", source: "privacy_change_events",
                                         details: "⚡️ User \(eventUserId.prefix(8)) → \(isHidden ? "hidden" : "visible") in group \(eventGroupId.prefix(8))")
                    await WeeklyLeagueService.shared.fetchFullLeaderboard()
                    
                case "activity":
                    let friendIds = await FriendService.shared.friends.map { $0.friendId }
                    guard let eventUUID = UUID(uuidString: eventUserId),
                          friendIds.contains(eventUUID) else { continue }
                    
                    AppLogger.debug("📰 [FEED] Privacy change: friend \(eventUserId.prefix(8)) is now \(isHidden ? "hidden" : "visible") — refreshing feed", category: .social)
                    self.logRealtimeEvent(type: "FEED_PRIVACY", source: "privacy_change_events",
                                         details: "⚡️ Friend \(eventUserId.prefix(8)) → \(isHidden ? "hidden" : "visible") in activity feed")
                    await ActivityFeedService.shared.fetchFeed()
                    
                default:
                    AppLogger.warning("Unknown privacy change_type: \(changeType)", category: .social)
                }
            }
        }
        
        await channel.subscribe()
        privacyChangeChannel = channel
        
        AppLogger.debug("Subscribed to privacy_change_events (league + activity) for user \(userId)", category: .network)
    }
    
    // MARK: - Exercise Library Subscription (Admin CMS → App live sync)
    
    /// Subscribe to the `exercises` table so admin CMS edits appear in the app
    /// within seconds instead of waiting up to 6 hours for the next full
    /// re-sync. INSERT/UPDATE events decode the row into an `ExerciseDTO` and
    /// upsert it in Core Data; DELETE events remove the row by id.
    ///
    /// Requires: `public.exercises` in the supabase_realtime publication with
    /// REPLICA IDENTITY FULL — set by migration 20260420_exercises_realtime.sql.
    private func subscribeExercises(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("exercises-\(userId.uuidString)")
        
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "exercises")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "exercises")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "exercises")
        
        let decoder = JSONDecoder()
        
        Task { [weak self] in
            for await action in inserts {
                guard let self else { break }
                await self.handleExerciseRowChange(record: action.record, decoder: decoder, kind: "INSERT")
            }
        }
        
        Task { [weak self] in
            for await action in updates {
                guard let self else { break }
                await self.handleExerciseRowChange(record: action.record, decoder: decoder, kind: "UPDATE")
            }
        }
        
        Task { [weak self] in
            for await action in deletes {
                guard let self else { break }
                await self.handleExerciseRowDelete(oldRecord: action.oldRecord)
            }
        }
        
        await channel.subscribe()
        exercisesChannel = channel
        
        AppLogger.debug("Subscribed to exercises table (CMS live sync)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "exercises",
                        details: "✅ Listening for INSERT/UPDATE/DELETE on public.exercises (admin CMS → app live sync)")
    }
    
    private func handleExerciseRowChange(record: [String: AnyJSON], decoder: JSONDecoder, kind: String) async {
        // Skip user-created custom exercises — those live in the custom_exercises
        // path and don't come from the admin CMS.
        if jsonBool(record["is_custom"]) == true { return }
        
        let name = jsonString(record["name"]) ?? "<unknown>"
        let id   = jsonString(record["id"])   ?? "?"
        
        do {
            // `[String: AnyJSON]` is JSON-encodable, so round-trip through
            // JSON and decode as our existing ExerciseDTO to reuse all field
            // mappings (snake_case ↔ camelCase, FlexibleInt, MuscleField, ...).
            let data = try JSONEncoder().encode(record)
            let dto = try decoder.decode(ExerciseDTO.self, from: data)
            
            logRealtimeEvent(type: "EXERCISE_\(kind)", source: "exercises",
                            details: "🏋️ \(kind) '\(dto.name)' (\(id.prefix(8))) from CMS — upserting locally")
            
            await ExerciseLibraryService.shared.upsertExerciseFromCloud(dto)
        } catch {
            AppLogger.error("Realtime exercises \(kind) decode failed for '\(name)': \(error.localizedDescription)", category: .network)
            logRealtimeEvent(type: "EXERCISE_\(kind)_ERROR", source: "exercises",
                            details: "❌ Decode failed for '\(name)' (\(id.prefix(8))): \(error.localizedDescription)", isError: true)
        }
    }
    
    private func handleExerciseRowDelete(oldRecord: [String: AnyJSON]) async {
        guard let idString = jsonString(oldRecord["id"]),
              let uuid = UUID(uuidString: idString) else {
            AppLogger.warning("Realtime exercises DELETE: missing id in oldRecord", category: .network)
            return
        }
        let name = jsonString(oldRecord["name"]) ?? "<unknown>"
        
        logRealtimeEvent(type: "EXERCISE_DELETE", source: "exercises",
                        details: "🗑️ DELETE '\(name)' (\(idString.prefix(8))) from CMS — removing locally")
        
        await ExerciseLibraryService.shared.deleteExerciseById(uuid)
    }
    
    // MARK: - Friend Activity Feed Subscription
    
    private func subscribeFriendActivityFeed(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("friend_activity_feed-\(userId.uuidString)")
        
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friend_activity_feed"
        )

        // Sprint 2 Q2-46 — pick up is_hidden flips from the moderation
        // webhook so a flagged post vanishes from the sender's feed in real
        // time (they never refetch after send).
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friend_activity_feed"
        )

        Task {
            for await _ in insertions {
                AppLogger.debug("New friend activity feed item!", category: .network)
                logRealtimeEvent(type: "INSERT", source: "friend_activity_feed",
                                details: "New activity in feed — refreshing")
                await ActivityFeedService.shared.fetchFeed()
                ActivityFeedService.shared.lastRealtimeUpdate = Date()
            }
        }

        Task {
            for await action in updates {
                let record = action.record
                let isHidden = (record["is_hidden"] as? AnyJSON)?.boolValue ?? false
                guard isHidden,
                      let idStr = jsonString(record["id"]),
                      let activityId = UUID(uuidString: idStr) else { continue }
                AppLogger.info("Realtime: activity \(activityId.uuidString.prefix(8)) hidden by moderation", category: .network)
                await ActivityFeedService.shared.applyModerationHide(activityId: activityId)
            }
        }

        await channel.subscribe()
        friendActivityFeedChannel = channel

        AppLogger.debug("Subscribed to friend_activity_feed for user \(userId)", category: .network)
    }
    
    // MARK: - Friend Requests Subscription
    
    private func subscribeFriendships(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        // Create channel for friendships table changes targeting this user
        let channel = client.realtimeV2.channel("friendships-\(userId.uuidString)")
        
        // Subscribe to new friend requests (where I am the addressee)
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friendships",
            filter: "addressee_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to updates (for when my requests are accepted)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "requester_id=eq.\(userId.uuidString)"
        )
        
        // Also subscribe to updates where I'm the addressee (for status changes)
        let myUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "addressee_id=eq.\(userId.uuidString)"
        )
        
        Task {
            for await action in insertions {
                await handleFriendshipInsert(action)
            }
        }
        
        Task {
            for await action in updates {
                await handleFriendshipUpdate(action, isRequester: true)
            }
        }
        
        Task {
            for await action in myUpdates {
                await handleFriendshipUpdate(action, isRequester: false)
            }
        }
        
        await channel.subscribe()
        friendshipsChannel = channel
        
        AppLogger.debug("Subscribed to friendships for user \(userId)", category: .network)
    }
    
    private func handleFriendshipInsert(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        guard let friendshipId = UUID(uuidString: jsonString(record["id"]) ?? ""),
              let requesterId = UUID(uuidString: jsonString(record["requester_id"]) ?? ""),
              let addresseeId = UUID(uuidString: jsonString(record["addressee_id"]) ?? "") else {
            AppLogger.warning("handleFriendshipInsert: malformed UUID in payload — dropping event", category: .network)
            return
        }
        
        AppLogger.debug("New friend request received!", category: .network)
        
        let payload = FriendRequestPayload(
            friendshipId: friendshipId,
            requesterId: requesterId,
            addresseeId: addresseeId,
            status: status,
            createdAt: Date()
        )
        
        // Trigger callback
        onFriendRequestReceived?(payload)
        
        // Refresh friend requests in FriendService
        await FriendService.shared.fetchPendingRequests()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    private func handleFriendshipUpdate(_ action: UpdateAction, isRequester: Bool) async {
        let record = action.record
        guard let status = jsonString(record["status"]) else { return }
        
        if status == "accepted" {
            guard let friendshipId = UUID(uuidString: jsonString(record["id"]) ?? ""),
                  let requesterId = UUID(uuidString: jsonString(record["requester_id"]) ?? ""),
                  let addresseeId = UUID(uuidString: jsonString(record["addressee_id"]) ?? "") else {
                AppLogger.warning("handleFriendshipUpdate: malformed UUID in accepted payload — dropping event", category: .network)
                return
            }
            AppLogger.info("Friend request accepted!", category: .network)
            
            let payload = FriendRequestPayload(
                friendshipId: friendshipId,
                requesterId: requesterId,
                addresseeId: addresseeId,
                status: status,
                createdAt: Date()
            )
            
            if isRequester {
                // My request was accepted
                onFriendRequestAccepted?(payload)
            }
            
            // Refresh friends list
            await FriendService.shared.fetchFriends()
            
            // Haptic feedback
            HapticManager.notification(.success)
        }
    }
    
    // MARK: - Shared Workouts Subscription
    
    private func subscribeSharedWorkouts(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("shared_workouts-\(userId.uuidString)")
        
        // Subscribe to new shared workouts where I am the recipient
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "shared_workouts",
            filter: "recipient_id=eq.\(userId.uuidString)"
        )
        
        Task {
            for await action in insertions {
                await handleSharedWorkoutInsert(action)
            }
        }
        
        await channel.subscribe()
        sharedWorkoutsChannel = channel
        
        AppLogger.debug("Subscribed to shared_workouts for user \(userId)", category: .network)
    }
    
    private func handleSharedWorkoutInsert(_ action: InsertAction) async {
        let record = action.record
        
        guard let workoutId = UUID(uuidString: jsonString(record["id"]) ?? ""),
              let senderId = UUID(uuidString: jsonString(record["sender_id"]) ?? ""),
              let recipientId = UUID(uuidString: jsonString(record["recipient_id"]) ?? "") else {
            AppLogger.warning("handleSharedWorkoutInsert: malformed UUID in payload — dropping event", category: .network)
            return
        }
        
        AppLogger.debug("New workout shared!", category: .network)
        
        let payload = SharedWorkoutPayload(
            workoutId: workoutId,
            senderId: senderId,
            recipientId: recipientId,
            workoutName: jsonString(record["workout_name"]) ?? "Workout",
            status: jsonString(record["status"]) ?? "pending",
            createdAt: Date()
        )
        
        // Trigger callback
        onWorkoutReceived?(payload)
        
        // Refresh received workouts
        await FriendService.shared.fetchReceivedWorkouts()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    // MARK: - Challenges Subscription
    
    private func subscribeChallenges(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("challenges-\(userId.uuidString)")
        
        // Subscribe to new challenge invites (challenge_participants)
        let invites = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_participants",
            filter: "user_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to challenge participant updates (status changes: pending → accepted/declined)
        let participantStatusChanges = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_participants",
            filter: "user_id=eq.\(userId.uuidString)"
        )
        
        // Subscribe to ALL challenge participant updates (for opponent accepting your sent challenge)
        let allParticipantUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_participants"
        )
        
        // Subscribe to challenge status changes (group_challenges is the actual table)
        let challengeUpdates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "group_challenges"
        )
        
        Task {
            for await action in invites {
                await handleChallengeInvite(action)
            }
        }
        
        // Route MY status changes (e.g. I accepted a challenge) to the proper handler
        Task {
            for await action in participantStatusChanges {
                await handleParticipantStatusChange(action, userId: userId)
            }
        }
        
        // Route ALL participant updates (opponent accepting, progress changes) to the proper handler
        Task {
            for await action in allParticipantUpdates {
                await handleAllParticipantUpdates(action, userId: userId)
            }
        }
        
        Task {
            for await action in challengeUpdates {
                await handleChallengeStatusChange(action)
            }
        }
        
        await channel.subscribe()
        challengesChannel = channel
        
        AppLogger.debug("Subscribed to challenges for user \(userId)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenges",
                        details: "✅ Listening on challenge_participants (INSERT+UPDATE) + group_challenges (UPDATE)")
    }
    
    private func handleChallengeInvite(_ action: InsertAction) async {
        let record = action.record
        guard let status = jsonString(record["status"]),
              status == "pending" else { return }
        
        guard let challengeId = UUID(uuidString: jsonString(record["challenge_id"]) ?? ""),
              let participantId = UUID(uuidString: jsonString(record["user_id"]) ?? "") else {
            AppLogger.warning("handleChallengeInvite: malformed UUID in payload — dropping event", category: .network)
            logRealtimeEvent(type: "CHALLENGE_INVITE", source: "challenge_participants", details: "❌ Malformed UUID", isError: true)
            return
        }
        
        AppLogger.debug("New challenge invite!", category: .network)
        logRealtimeEvent(type: "CHALLENGE_INVITE", source: "challenge_participants", details: "New challenge invite received")
        
        let payload = ChallengePayload(
            challengeId: challengeId,
            participantId: participantId,
            status: status,
            totalProgress: jsonInt(record["total_progress"]) ?? 0
        )
        
        // Trigger callback
        onChallengeInviteReceived?(payload)
        
        // Refresh challenge invites
        await ChallengeService.shared.fetchPendingInvites()
        
        // Haptic feedback
        HapticManager.notification(.success)
    }
    
    private func handleParticipantStatusChange(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        let oldRecord = action.oldRecord
        
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let oldStatus = jsonString(oldRecord["status"]) ?? ""
        let newStatus = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        let oldTotalProgress = jsonInt(oldRecord["total_progress"]) ?? 0
        
        AppLogger.debug("MY challenge participant: status \(oldStatus) → \(newStatus), progress \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))", category: .network)
        logRealtimeEvent(type: "MY_PARTICIPANT", source: "challenge_participants",
                        details: "status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            AppLogger.info("I accepted a challenge - refreshing all lists (1v1 + group)", category: .network)
            await ChallengeService.shared.fetchPendingInvites()  // Remove from pending
            await throttledChallengeFetch()  // Add to active (1v1 + group) — throttled
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            AppLogger.debug("I declined a challenge", category: .network)
            await ChallengeService.shared.fetchPendingInvites()
        } else if totalProgress != oldTotalProgress {
            // My progress was confirmed in DB — refresh group challenges to show DB-backed values
            AppLogger.debug("My own progress confirmed in DB: \(totalProgress) — refreshing", category: .network)
            await throttledChallengeFetch()
        }
    }
    
    private func handleAllParticipantUpdates(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        let oldRecord = action.oldRecord
        
        let participantUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let oldStatus = jsonString(oldRecord["status"]) ?? ""
        let newStatus = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        let oldTotalProgress = jsonInt(oldRecord["total_progress"]) ?? 0
        
        // Skip if it's my own update (already handled by handleParticipantStatusChange)
        guard participantUserId != userId.uuidString else { return }
        
        AppLogger.debug("OPPONENT challenge participant: \(oldStatus) → \(newStatus), progress: \(oldTotalProgress) → \(totalProgress) (challenge: \(challengeId))", category: .network)
        logRealtimeEvent(type: "OPPONENT_PARTICIPANT", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), status: \(oldStatus)→\(newStatus), progress: \(oldTotalProgress)→\(totalProgress), challenge: \(challengeId.prefix(8))")
        
        if oldStatus == "pending" && newStatus == "accepted" {
            AppLogger.info("Opponent ACCEPTED my challenge - moving from sent → active (1v1 + group)", category: .network)
            logRealtimeEvent(type: "OPPONENT_ACCEPTED", source: "challenge_participants",
                            details: "✅ Opponent accepted! Refreshing all lists...")
            await ChallengeService.shared.fetchPendingSentChallenges()  // Remove from sent
            await throttledChallengeFetch()  // Add to active (1v1 + group)

            // 2026-04-28 sync-triage Layer D — back-fill the SENDER's
            // own `challenge_daily_progress` row the instant the
            // challenge becomes active. Without this, only the
            // ACCEPTING side (`ChallengeService.respondToChallenge`)
            // would write a row; the sender's row never landed until
            // their next foreground HK sync, leaving BOTH active-
            // challenge widgets ("opponent: —" on each side) stale
            // for hours despite both clients having real HK data.
            // Canonical incident: Joe ↔ Paul 10K Steps Daily Steps
            // challenge `4076da0d` — Paul (sender) showed "Joe — no
            // data" on his home-screen widget.
            //
            // 2026-04-28 hardening — the previous version required
            // `activeChallenges.first(where:)` to succeed on the first
            // try, but `throttledChallengeFetch()` above has a 3s
            // throttle that frequently bails on a freshly-foregrounded
            // app (the foreground 10-fan-out just ran <3s earlier).
            // When the throttle wins, the lookup miss caused the
            // SENDER backfill to silently skip — symptom: 10K Club
            // challenge `742c0bd0` showed Paul's "0 steps" widget for
            // multiple seconds after Joe accepted, only resolving when
            // a separate code path eventually wrote the row. Recovery:
            // on miss, call `forceFetchActiveChallenges()` (bypasses
            // throttle; RequestCoalescer dedupes any in-flight fetch)
            // and retry the lookup ONCE. If the second lookup still
            // fails the challenge truly isn't visible to this user
            // (RLS / type filter mismatch) and we accept the miss.
            if let challengeUUID = UUID(uuidString: challengeId) {
                var challenge = await MainActor.run(body: {
                    ChallengeService.shared.activeChallenges.first(where: { $0.challengeId == challengeUUID })
                })
                if challenge == nil {
                    logRealtimeEvent(type: "SENDER_BACKFILL_RETRY", source: "challenge_participants",
                                    details: "Lookup miss for \(challengeId.prefix(8)) — forcing non-throttled refetch")
                    await ChallengeService.shared.forceFetchActiveChallenges()
                    challenge = await MainActor.run(body: {
                        ChallengeService.shared.activeChallenges.first(where: { $0.challengeId == challengeUUID })
                    })
                }
                if let challenge = challenge {
                    logRealtimeEvent(type: "SENDER_BACKFILL", source: "challenge_participants",
                                    details: "Backfilling sender progress for activated challenge \(challengeId.prefix(8))")
                    await ChallengeService.shared.backfillTodayProgressForChallenge(
                        challengeId: challengeUUID,
                        challengeType: challenge.challengeType,
                        targetUnit: challenge.targetUnit,
                        dailyTargetForTargetHitLog: challenge.dailyTarget ?? 0,
                        titleForLogs: challenge.title
                    )
                } else {
                    logRealtimeEvent(type: "SENDER_BACKFILL_MISS", source: "challenge_participants",
                                    details: "Challenge \(challengeId.prefix(8)) not in activeChallenges after force-refetch — skipping sender backfill")
                }
            }
            HapticManager.notification(.success)
        } else if oldStatus == "pending" && newStatus == "declined" {
            AppLogger.debug("Opponent DECLINED my challenge - removing from sent", category: .network)
            logRealtimeEvent(type: "OPPONENT_DECLINED", source: "challenge_participants",
                            details: "Opponent declined challenge \(challengeId.prefix(8))")
            await ChallengeService.shared.fetchPendingSentChallenges()
        } else if totalProgress != oldTotalProgress {
            // Opponent's progress changed (they logged new steps/hydration/etc.)
            AppLogger.debug("Opponent progress changed: \(oldTotalProgress) → \(totalProgress) - refreshing all challenges", category: .network)
            logRealtimeEvent(type: "OPPONENT_PROGRESS", source: "challenge_participants",
                            details: "🔥 Progress: \(oldTotalProgress)→\(totalProgress) for challenge \(challengeId.prefix(8))")
            await throttledChallengeFetch()
        } else {
            // DEFENSIVE: Even if progress looks unchanged, refresh if we got an update event
            // This catches cases where oldRecord is empty (REPLICA IDENTITY not FULL)
            let hasOldData = !oldRecord.isEmpty
            if !hasOldData {
                AppLogger.warning("No old record data — REPLICA IDENTITY may not be FULL. Refreshing defensively.", category: .network)
                logRealtimeEvent(type: "OPPONENT_UPDATE_NO_OLD", source: "challenge_participants",
                                details: "⚠️ No old record data — refreshing defensively. newProgress=\(totalProgress)")
                await throttledChallengeFetch()
            }
        }
    }
    
    private func handleChallengeProgress(_ action: UpdateAction, userId: UUID) async {
        let record = action.record
        
        guard let participantUserId = jsonString(record["user_id"]) else {
            AppLogger.warning("handleChallengeProgress: missing user_id. Keys: \(record.keys.joined(separator: ", "))", category: .network)
            logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants", details: "❌ Missing user_id in record", isError: true)
            return
        }
        
        let challengeId = jsonString(record["challenge_id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        let totalProgress = jsonInt(record["total_progress"]) ?? 0
        
        logRealtimeEvent(type: "CHALLENGE_PROGRESS", source: "challenge_participants",
                        details: "user: \(participantUserId.prefix(8)), challenge: \(challengeId.prefix(8)), status: \(status), progress: \(totalProgress)")
        
        // If it's my own update, skip — we already know our own progress
        if participantUserId == userId.uuidString {
            return
        }
        
        guard let challengeUUID = UUID(uuidString: challengeId),
              let participantUUID = UUID(uuidString: participantUserId) else {
            AppLogger.warning("handleChallengeProgress: malformed UUID (challenge='\(challengeId)', user='\(participantUserId)') — dropping event", category: .network)
            return
        }
        
        let payload = ChallengePayload(
            challengeId: challengeUUID,
            participantId: participantUUID,
            status: status,
            totalProgress: totalProgress
        )
        
        // Trigger callback
        onChallengeProgressUpdated?(payload)
        
        // ⚡️ PERF FIX: Use throttled fetch instead of 4 sequential fetches
        await throttledChallengeFetch()
    }
    
    private func handleChallengeStatusChange(_ action: UpdateAction) async {
        let record = action.record
        
        let challengeId = jsonString(record["id"]) ?? "unknown"
        let status = jsonString(record["status"]) ?? ""
        
        #if DEBUG
        AppLogger.debug("Challenge status: \(challengeId.prefix(8)) → \(status)", category: .network)
        #endif
        logRealtimeEvent(type: "CHALLENGE_STATUS", source: "group_challenges", details: "Challenge \(challengeId.prefix(8)) → \(status)")
        
        // ⚡️ PERF FIX: Use throttled fetch instead of 4 sequential fetches.
        // Status changes (cancelled, completed, declined) are infrequent, so one
        // consolidated fetch is sufficient — the throttle prevents cascading.
        await throttledChallengeFetch()
        await ChallengeService.shared.fetchPendingInvites()
        
        #if DEBUG
        AppLogger.info("Challenge data refreshed after status change", category: .network)
        #endif
    }
    
    // MARK: - Daily Progress Subscription (for live challenge widget)
    
    /// Subscribe to opponent's daily progress updates
    /// This is battery-efficient: uses WebSocket (no polling), only triggers on actual changes
    private func subscribeDailyProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        // Subscribe to challenge_daily_progress table
        // We listen for ALL changes, then filter client-side to only process opponent updates
        let channel = client.realtimeV2.channel("daily_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handleDailyProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleDailyProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        dailyProgressChannel = channel
        
        AppLogger.debug("Subscribed to daily progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on challenge_daily_progress (all rows)")
    }
    
    private func handleDailyProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        // CRITICAL FIX: Supabase Realtime v2 sends records as [String: AnyJSON].
        // AnyJSON wraps values in enum cases (.string, .integer, .double, etc.)
        // Direct `as? String` / `as? Int` FAILS on AnyJSON — must use jsonString/jsonInt helpers.
        guard let record = record else {
            AppLogger.warning("handleDailyProgressChange: nil record", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ nil record", isError: true)
            return
        }
        
        guard let recordUserId = jsonString(record["user_id"]) else {
            AppLogger.warning("handleDailyProgressChange: missing user_id. Keys: \(record.keys.joined(separator: ", ")), types: \(record.map { "\($0.key)=\(type(of: $0.value))" }.joined(separator: ", "))", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing user_id. Keys: \(record.keys.joined(separator: ", "))", isError: true)
            return
        }
        
        guard let challengeIdString = jsonString(record["challenge_id"]),
              let challengeId = UUID(uuidString: challengeIdString) else {
            AppLogger.warning("handleDailyProgressChange: missing/invalid challenge_id", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress", details: "❌ Missing challenge_id", isError: true)
            return
        }
        
        // Use jsonInt for safe extraction — this was the ROOT BUG
        guard let progressValue = jsonInt(record["progress_value"]) else {
            AppLogger.warning("handleDailyProgressChange: cannot parse progress_value. Raw: \(String(describing: record["progress_value"])), type: \(type(of: record["progress_value"] as Any))", category: .network)
            logRealtimeEvent(type: "DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "❌ Cannot parse progress_value: \(String(describing: record["progress_value"]))", isError: true)
            return
        }
        
        let isOwnUpdate = recordUserId == userId.uuidString
        let targetHit = jsonBool(record["target_hit"]) ?? false
        let progressDate = jsonString(record["progress_date"]) ?? ""
        
        if isOwnUpdate {
            // 2026-04-25: previous "skip own update" perf optimization broke
            // the dashboard 1v1/group challenge widgets. The widget reads
            // ChallengeService.activeChallenges, which only updates after a
            // get_active_challenges RPC. When a workout cascade-writes to
            // challenge_daily_progress, the immediate logProgress() refetch
            // can be dropped by ChallengeService.fetchMinInterval (multiple
            // challenges in one workout); the realtime event was the last
            // chance to re-pull aggregates (myToday/oppToday/amWinning).
            // Always refresh on own update — RealtimeService's 3s throttle
            // + RequestCoalescer prevents thrash.
            logRealtimeEvent(type: "OWN_DAILY_PROGRESS", source: "challenge_daily_progress",
                            details: "✅ Own progress confirmed: \(progressValue), challenge: \(challengeIdString.prefix(8)) — refreshing widget")
            await throttledChallengeFetch()
            return
        }
        
        // ═══════════════════════════════════════════════════════════
        // OPPONENT'S daily progress changed — this is the CRITICAL path
        // ═══════════════════════════════════════════════════════════
        
        let timestamp = Date()
        #if DEBUG
        AppLogger.debug("Opponent daily progress: \(recordUserId.prefix(8)) → \(progressValue) (hit: \(targetHit)) challenge: \(challengeIdString.prefix(8))", category: .network)
        #endif
        
        logRealtimeEvent(type: "🔥 OPPONENT_DAILY_PROGRESS", source: "challenge_daily_progress",
                        details: "⚡️ Opponent \(recordUserId.prefix(8)) → \(progressValue) (hit: \(targetHit)) challenge: \(challengeIdString.prefix(8))")
        
        guard let opponentId = UUID(uuidString: recordUserId) else {
            AppLogger.warning("handleDailyProgressChange: malformed opponent user_id '\(recordUserId)' — dropping event", category: .network)
            return
        }
        
        let payload = DailyProgressPayload(
            challengeId: challengeId,
            opponentId: opponentId,
            progressDate: progressDate,
            progressValue: progressValue,
            targetHit: targetHit
        )
        
        // Store for cross-device verification
        lastOpponentProgressAt = timestamp
        lastOpponentProgressEvent = payload
        
        // Trigger callback (ChallengeDetailView and GroupChallengeDetailView listen to this)
        onOpponentDailyProgressUpdated?(payload)
        
        // Refresh BOTH 1v1 and group challenges — throttled to prevent cascading duplicates
        await throttledChallengeFetch()
        
        // Haptic feedback when opponent hits their daily target
        if targetHit {
            HapticManager.notification(.warning)
        }
    }
    // MARK: - Private Challenge Progress Subscription
    
    /// Subscribe to private_challenge_daily_progress updates.
    /// When ANY member of a private challenge logs progress, all other members
    /// see it instantly via WebSocket — no polling required.
    private func subscribePrivateChallengeProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("private_challenge_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged by any member)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed for any member)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handlePrivateChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handlePrivateChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        privateChallengeChannel = channel
        
        AppLogger.debug("Subscribed to private_challenge_daily_progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "private_challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on private_challenge_daily_progress")
    }
    
    private func handlePrivateChallengeProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let progressValue = jsonInt(record["progress_value"]) ?? 0
        
        let isOwnUpdate = recordUserId == userId.uuidString
        let challengeType = lookupPrivateChallengeType(challengeId: challengeId)
        let isManual = Self.isManualInputType(challengeType)
        
        if isOwnUpdate {
            logRealtimeEvent(type: "OWN_PRIVATE_PROGRESS", source: "private_challenge_daily_progress",
                            details: "✅ Own progress: \(progressValue), challenge: \(challengeId.prefix(8)) — SKIPPED refresh")
            // ⚡️ PERF FIX: Skip fetching for own updates — we already have the data locally.
            return
        }
        
        AppLogger.debug("Private challenge member progress: \(recordUserId.prefix(8)) → \(progressValue) (challenge: \(challengeId.prefix(8)), type: \(challengeType ?? "?"), manual: \(isManual))", category: .network)
        logRealtimeEvent(type: "🔥 PRIVATE_MEMBER_PROGRESS", source: "private_challenge_daily_progress",
                        details: "⚡️ Member \(recordUserId.prefix(8)) → \(progressValue), challenge: \(challengeId.prefix(8)), manual: \(isManual)")
        
        if isManual {
            // Manual-input challenges (protein, hydration, etc.): debounced refresh
            // Cancels any pending debounce and waits 1.5s before fetching.
            privateProgressDebounceTask?.cancel()
            privateProgressDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
                guard !Task.isCancelled else { return }
                await throttledPrivateFetch()
            }
        }
        // Auto-tracked challenges: refresh on periodic cadence timer instead.
    }
    
    // MARK: - Community Challenge Progress Subscription
    
    /// Subscribe to community_challenge_daily_progress updates.
    /// When ANY community member logs progress, the leaderboard updates live.
    private func subscribeCommunityChallengeProgress(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("community_challenge_progress-\(userId.uuidString)")
        
        // Listen for inserts (new daily progress logged by any member)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        // Listen for updates (progress value changed for any member)
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_daily_progress"
        )
        
        Task {
            for await action in inserts {
                await handleCommunityChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleCommunityChallengeProgressChange(action.record, userId: userId)
            }
        }
        
        await channel.subscribe()
        communityChallengeChannel = channel
        
        AppLogger.debug("Subscribed to community_challenge_daily_progress updates", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "community_challenge_daily_progress",
                        details: "✅ Listening for INSERT + UPDATE on community_challenge_daily_progress")
    }
    
    private func handleCommunityChallengeProgressChange(_ record: [String: AnyJSON]?, userId: UUID) async {
        guard let record = record else {
            AppLogger.warning("Community progress event with nil record", category: .network)
            return
        }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let progressValue = jsonInt(record["progress_value"]) ?? 0
        
        let isOwnUpdate = recordUserId == userId.uuidString
        
        // PERF FIX: Skip own events entirely — we already know our own progress.
        // These arrive because we subscribe without a user_id filter, and each
        // INSERT/UPDATE from our own log_community_challenge_progress triggers
        // 2 events (insert + update) that cascade into redundant fetchMyChallenges() calls.
        if isOwnUpdate {
            #if DEBUG
            AppLogger.debug("Community progress (OWN) — skipping refresh for \(challengeId.prefix(8))", category: .network)
            #endif
            logRealtimeEvent(type: "OWN_COMMUNITY_PROGRESS", source: "community_challenge_daily_progress",
                            details: "✅ Own community progress confirmed: \(progressValue), challenge: \(challengeId.prefix(8)) — SKIPPED refresh")
            return
        }
        
        let challengeType = lookupCommunityChallengeType(challengeId: challengeId)
        let isManual = Self.isManualInputType(challengeType)
        
        #if DEBUG
        AppLogger.debug("COMMUNITY PROGRESS — user: \(recordUserId.prefix(8)), challenge: \(challengeId.prefix(8)), value: \(progressValue), type: \(challengeType ?? "unknown"), manual: \(isManual)", category: .network)
        #endif
        
        logRealtimeEvent(type: "🌍 COMMUNITY_MEMBER_PROGRESS", source: "community_challenge_daily_progress",
                        details: "⚡️ Member \(recordUserId.prefix(8)) → \(progressValue), challenge: \(challengeId.prefix(8)), manual: \(isManual)")
        
        // Optimistic local patch — update the leaderboard entry immediately (<16ms)
        await CommunityChallengeService.shared.applyOptimisticProgressUpdate(
            challengeId: challengeId, userId: recordUserId, progressValue: progressValue
        )
        
        if isManual {
            // Manual-input challenges: batch challenge IDs over a 3s window, then ONE refresh
            pendingCommunityRefreshChallengeIds.insert(challengeId)
            communityProgressDebounceTask?.cancel()
            communityProgressDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
                guard !Task.isCancelled else { return }
                let batchedIds = pendingCommunityRefreshChallengeIds
                pendingCommunityRefreshChallengeIds.removeAll()
                AppLogger.debug("Community manual input (batched \(batchedIds.count) challenges) — refreshing", category: .network)
                await throttledCommunityFetch()
            }
        } else {
            // Auto-tracked challenges: longer 6s debounce to batch rapid HealthKit-driven events
            autoTrackedDebounceTask?.cancel()
            autoTrackedDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000) // 6s debounce
                guard !Task.isCancelled else { return }
                AppLogger.debug("Community auto-tracked (debounced 6s) — refreshing", category: .network)
                await throttledCommunityFetch()
            }
        }
    }
    
    // MARK: - Community Participants Subscription (Join/Leave Events)
    
    /// Subscribe to community_challenge_participants for real-time join/leave events.
    /// When a user joins or leaves a community challenge, all members see the update instantly.
    private func subscribeCommunityParticipants(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("community_participants-\(userId.uuidString)")
        
        // Listen for new members joining (INSERT)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        // Listen for member status changes (UPDATE) — e.g. deactivation
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "community_challenge_participants"
        )
        
        Task {
            for await action in inserts {
                await handleCommunityParticipantChange(action.record, type: "JOIN", userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handleCommunityParticipantChange(action.record, type: "UPDATE", userId: userId)
            }
        }
        
        await channel.subscribe()
        communityParticipantsChannel = channel
        
        AppLogger.debug("Subscribed to community_challenge_participants (join/leave)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "community_challenge_participants",
                        details: "✅ Listening for INSERT + UPDATE on community_challenge_participants")
    }
    
    private func handleCommunityParticipantChange(_ record: [String: AnyJSON]?, type: String, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let isOwnJoin = recordUserId == userId.uuidString
        
        AppLogger.debug("Community participant \(type): user \(recordUserId.prefix(8)) in challenge \(challengeId.prefix(8))", category: .network)
        logRealtimeEvent(type: "COMMUNITY_PARTICIPANT_\(type)", source: "community_challenge_participants",
                        details: "\(isOwnJoin ? "You" : "Member \(recordUserId.prefix(8))") \(type.lowercased()) community challenge \(challengeId.prefix(8))")
        
        // Throttled refresh — join/leave events are infrequent but can still double-fire
        await throttledCommunityFetch()
        
        if !isOwnJoin {
            HapticManager.impact(.light)
        }
    }
    
    // MARK: - Private Challenge Members Subscription (Join/Leave Events)
    
    /// Subscribe to private_challenge_members for real-time join/leave events.
    /// When a user joins or leaves a private challenge, all members see it instantly.
    private func subscribePrivateMembers(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        
        let channel = client.realtimeV2.channel("private_members-\(userId.uuidString)")
        
        // Listen for new members joining (INSERT)
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        // Listen for member status changes (UPDATE) — e.g. role change, deactivation
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "private_challenge_members"
        )
        
        Task {
            for await action in inserts {
                await handlePrivateMemberChange(action.record, type: "JOIN", userId: userId)
            }
        }
        
        Task {
            for await action in updates {
                await handlePrivateMemberChange(action.record, type: "UPDATE", userId: userId)
            }
        }
        
        await channel.subscribe()
        privateMembersChannel = channel
        
        AppLogger.debug("Subscribed to private_challenge_members (join/leave)", category: .network)
        logRealtimeEvent(type: "SUBSCRIBED", source: "private_challenge_members",
                        details: "✅ Listening for INSERT + UPDATE on private_challenge_members")
    }
    
    private func handlePrivateMemberChange(_ record: [String: AnyJSON]?, type: String, userId: UUID) async {
        guard let record = record else { return }
        
        let recordUserId = jsonString(record["user_id"]) ?? ""
        let challengeId = jsonString(record["challenge_id"]) ?? ""
        let isOwnJoin = recordUserId == userId.uuidString
        
        AppLogger.debug("Private member \(type): user \(recordUserId.prefix(8)) in challenge \(challengeId.prefix(8))", category: .network)
        logRealtimeEvent(type: "PRIVATE_MEMBER_\(type)", source: "private_challenge_members",
                        details: "\(isOwnJoin ? "You" : "Member \(recordUserId.prefix(8))") \(type.lowercased()) private challenge \(challengeId.prefix(8))")
        
        // Throttled refresh — join/leave events are infrequent but can still double-fire
        await throttledPrivateFetch()
        
        // Signal detail views to reload their member list
        PrivateChallengeService.shared.memberChangeToken = UUID()
        
        if !isOwnJoin {
            HapticManager.impact(.light)
        }
    }
    
    // MARK: - Periodic Cadence Refresh (Community + Private Challenges)
    
    /// Start the periodic fallback refresh timer for community/private challenges.
    /// Now primarily a safety net (120s) since event-driven debouncing handles
    /// both manual-input (1.5s) and auto-tracked (6s) challenges directly.
    ///
    /// Adaptive cadence based on user engagement:
    /// - Community view visible + recently appeared (<60s) → refresh every 30s
    /// - Community view visible + idle (>60s) → refresh every 60s
    /// - Not visible → skip entirely
    func startAutoTrackedRefreshTimer() {
        autoTrackedRefreshTimer?.cancel()
        autoTrackedRefreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.autoTrackedRefreshInterval)
                guard !Task.isCancelled else { break }
                
                guard CommunityChallengeService.shared.isCommunityViewVisible else {
                    communityViewBecameVisibleAt = nil
                    continue
                }
                
                if communityViewBecameVisibleAt == nil {
                    communityViewBecameVisibleAt = Date()
                }
                
                // Adaptive staleness threshold based on engagement duration
                let engagementDuration = communityViewBecameVisibleAt.map { Date().timeIntervalSince($0) } ?? 999
                let stalenessThreshold: TimeInterval = engagementDuration < 60 ? 30 : 60
                
                let communityStale = lastCommunityFetchTime.map { Date().timeIntervalSince($0) > stalenessThreshold } ?? true
                let privateStale = lastPrivateFetchTime.map { Date().timeIntervalSince($0) > stalenessThreshold } ?? true
                
                let hasCommunity = !CommunityChallengeService.shared.myChallenges.isEmpty
                let hasPrivate = !PrivateChallengeService.shared.myChallenges.isEmpty
                
                if (hasCommunity && communityStale) || (hasPrivate && privateStale) {
                    AppLogger.debug("Cadence refresh (adaptive \(Int(stalenessThreshold))s threshold)", category: .network)
                    
                    if hasCommunity && communityStale {
                        lastCommunityFetchTime = Date()
                        await CommunityChallengeService.shared.fetchMyChallenges()
                    }
                    if hasPrivate && privateStale {
                        lastPrivateFetchTime = Date()
                        await PrivateChallengeService.shared.fetchMyChallenges()
                    }
                }
            }
        }
    }
    
    /// Stop the periodic refresh timer (called on disconnect).
    func stopAutoTrackedRefreshTimer() {
        autoTrackedRefreshTimer?.cancel()
        autoTrackedRefreshTimer = nil
    }

    // MARK: - Challenge Reactions Subscription (per-detail-view)

    /// Subscribe to INSERT events on `challenge_reactions` filtered by
    /// `challenge_id`. Owned by whichever challenge-detail view is
    /// currently visible. The view calls this in `.task(id:)` and
    /// `unsubscribeChallengeReactions()` in `.onDisappear`. Idempotent
    /// when called with the same `challengeId` twice (returns early).
    /// Switching to a different challengeId tears the previous channel
    /// down before opening a new one.
    func subscribeChallengeReactions(challengeId: UUID) async {
        // Same channel already open for this challenge — no-op so a
        // .task(id:) re-evaluation doesn't churn the socket.
        if subscribedReactionChallengeId == challengeId, challengeReactionsChannel != nil {
            return
        }

        await unsubscribeChallengeReactions()

        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("challenge_reactions-\(challengeId.uuidString)")

        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_reactions",
            filter: "challenge_id=eq.\(challengeId.uuidString)"
        )

        challengeReactionsListenerTask = Task { [weak self] in
            for await action in inserts {
                guard let self = self else { return }
                await self.handleChallengeReactionInsert(action.record)
            }
        }

        await channel.subscribe()
        challengeReactionsChannel = channel
        subscribedReactionChallengeId = challengeId

        logRealtimeEvent(
            type: "SUBSCRIBED",
            source: "challenge_reactions",
            details: "✅ Listening for INSERT on challenge_reactions for \(challengeId.uuidString.prefix(8))"
        )
    }

    /// Tear down the per-challenge reactions subscription (mirrors the
    /// "1 channel per visible detail view" lifetime contract).
    func unsubscribeChallengeReactions() async {
        challengeReactionsListenerTask?.cancel()
        challengeReactionsListenerTask = nil

        if let channel = challengeReactionsChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        challengeReactionsChannel = nil
        subscribedReactionChallengeId = nil
    }

    private func handleChallengeReactionInsert(_ record: [String: AnyJSON]?) async {
        guard let record = record else { return }

        // Decode the inserted row into the existing `ChallengeReaction`
        // model. Realtime payloads carry the columns we own
        // (`reaction_*`, `sender_id`, `recipient_id`, `created_at`)
        // but NOT joined `sender_name` / `sender_photo_url` (those
        // come from the RPC view). Best-effort: hand the row to the
        // callback with a nil/empty name; the receiver row will fall
        // back to the cached `CachedFriendPhoto` initials avatar and
        // will re-hydrate on the next `fetchReactions` refresh.
        guard let reactionIdString = jsonString(record["id"]),
              let reactionId = UUID(uuidString: reactionIdString),
              let senderIdString = jsonString(record["sender_id"]),
              let senderId = UUID(uuidString: senderIdString),
              let recipientIdString = jsonString(record["recipient_id"]),
              let recipientId = UUID(uuidString: recipientIdString) else {
            AppLogger.warning("[REACTIONS_REALTIME] Malformed reaction insert; dropping event", category: .network)
            return
        }

        let challengeIdValue: UUID? = jsonString(record["challenge_id"]).flatMap { UUID(uuidString: $0) }
        let reactionKey = jsonString(record["reaction_key"]) ?? ""
        let reactionEmoji = jsonString(record["reaction_emoji"]) ?? "💬"
        let reactionText = jsonString(record["reaction_text"]) ?? ""
        let reactionCategory = jsonString(record["reaction_category"]) ?? "trash_talk"

        let createdAt: Date = {
            if let raw = jsonString(record["created_at"]) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = iso.date(from: raw) { return parsed }
                iso.formatOptions = [.withInternetDateTime]
                if let parsed = iso.date(from: raw) { return parsed }
            }
            return Date()
        }()

        let reaction = ChallengeReaction(
            reactionId: reactionId,
            challengeId: challengeIdValue,
            senderId: senderId,
            senderName: nil,
            senderPhotoUrl: nil,
            recipientId: recipientId,
            reactionKey: reactionKey,
            reactionEmoji: reactionEmoji,
            reactionText: reactionText,
            reactionCategory: reactionCategory,
            createdAt: createdAt
        )

        logRealtimeEvent(
            type: "🔥 CHALLENGE_REACTION",
            source: "challenge_reactions",
            details: "⚡️ \(reactionEmoji) \(reactionText) from \(senderIdString.prefix(8))"
        )

        onChallengeReactionReceived?(reaction)
    }

    // MARK: - Dashboard Incoming Reactions (recipient-filtered)

    /// Subscribe to INSERT events on `challenge_reactions` filtered by
    /// `recipient_id = userId`. Owned by `connect()` / `disconnect()`
    /// — NOT per-view. Powers the dashboard `BattleCryShoutBubble`
    /// effect: every active challenge widget the user is rendering
    /// listens to `dashboardIncomingBattleCryByChallenge` via
    /// `BattleCryShoutBubble` when the reaction's `challengeId` matches
    ///
    /// Coexists with `subscribeChallengeReactions(challengeId:)` (the
    /// per-detail-view channel). The two have different filters:
    ///   • Detail-view channel = "all reactions for THIS challenge"
    ///     (filtered by `challenge_id`) — drives the in-feed bubble
    ///     stack on `ChallengeDetailView` / `GroupChallengeDetailView`
    ///     / `CommunityChallengeViews`.
    ///   • Dashboard channel  = "all reactions targeted at ME"
    ///     (filtered by `recipient_id`) — drives the dashboard widget
    ///     shout bubble. Includes reactions from challenges I haven't
    ///     opened the detail view of yet.
    /// Realtime delivers a separate event to each, so the user only
    /// sees one logical bubble per surface (dashboard vs detail view).
    private func subscribeIncomingReactions(userId: UUID) async {
        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("incoming_reactions-\(userId.uuidString)")

        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "challenge_reactions",
            filter: "recipient_id=eq.\(userId.uuidString)"
        )

        incomingReactionsListenerTask = Task { [weak self] in
            for await action in inserts {
                guard let self = self else { return }
                await self.handleIncomingReactionInsert(action.record)
            }
        }

        await channel.subscribe()
        incomingReactionsChannel = channel

        logRealtimeEvent(
            type: "SUBSCRIBED",
            source: "incoming_reactions",
            details: "✅ Listening for INSERT on challenge_reactions where recipient_id=\(userId.uuidString.prefix(8))"
        )
    }

    /// Writes the latest opponent battle cry into the App Group sidecar
    /// so the home-screen Active Challenge widget can render the shout
    /// bubble. Called for every incoming cry (realtime + APNs) — deduped
    /// by `SmackTalkWidgetBridge.publish` hash when payloads match.
    private func publishBattleCryToHomeScreenWidget(
        challengeId: UUID,
        senderDisplayName: String?,
        reactionEmoji: String,
        reactionText: String,
        reactionCategory: String
    ) {
        let full = senderDisplayName ?? "Someone"
        let first = full
            .components(separatedBy: " ")
            .first
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"
        let payload = SmackTalkWidgetBridge.WidgetSmackTalk(
            challengeId: challengeId.uuidString.lowercased(),
            senderFirstName: first,
            reactionEmoji: reactionEmoji,
            reactionText: reactionText,
            reactionCategory: reactionCategory,
            receivedAt: Date()
        )
        SmackTalkWidgetBridge.publish(payload, shouldWrite: { true })
    }

    /// Shared path for dashboard bubble + widget + pending buffer.
    private func applyIncomingBattleCry(
        _ reaction: ChallengeReaction,
        widgetSenderDisplayName: String?
    ) {
        guard let challengeId = reaction.challengeId else { return }

        let dedupeKey = "\(challengeId.uuidString)|\(reaction.senderId.uuidString)|\(reaction.reactionText)|\(reaction.reactionEmoji)"
        let now = Date()
        if let prevKey = lastIncomingBattleCryDedupeKey,
           let prevAt = lastIncomingBattleCryDedupeAt,
           prevKey == dedupeKey,
           now.timeIntervalSince(prevAt) < 4 {
            AppLogger.debug(
                "[INCOMING_REACTIONS] Deduped repeat within 4s — \(reaction.reactionEmoji)",
                category: .network
            )
            return
        }
        lastIncomingBattleCryDedupeKey = dedupeKey
        lastIncomingBattleCryDedupeAt = now

        publishBattleCryToHomeScreenWidget(
            challengeId: challengeId,
            senderDisplayName: widgetSenderDisplayName ?? reaction.senderName,
            reactionEmoji: reaction.reactionEmoji,
            reactionText: reaction.reactionText,
            reactionCategory: reaction.reactionCategory
        )

        dashboardIncomingBattleCryByChallenge[challengeId] = reaction
        persistStickyIncomingBattleCries()
        HapticManager.notification(.warning)
        bumpBattleCryDashboardRenderToken()
    }

    private func handleIncomingReactionInsert(_ record: [String: AnyJSON]?) async {
        guard let record = record else { return }

        guard let reactionIdString = jsonString(record["id"]),
              let reactionId = UUID(uuidString: reactionIdString),
              let senderIdString = jsonString(record["sender_id"]),
              let senderId = UUID(uuidString: senderIdString),
              let recipientIdString = jsonString(record["recipient_id"]),
              let recipientId = UUID(uuidString: recipientIdString),
              let challengeIdString = jsonString(record["challenge_id"]),
              let challengeId = UUID(uuidString: challengeIdString) else {
            AppLogger.warning("[INCOMING_REACTIONS] Malformed reaction insert; dropping event", category: .network)
            return
        }

        // Defensive — skip our own sends. The server-side `recipient_id`
        // filter SHOULD make this a no-op (we never set ourselves as
        // the recipient), but a future RPC change that fans out to
        // multi-recipient groups could violate that. Belt-and-suspenders.
        if senderId == SupabaseManager.shared.currentUser?.id { return }

        let reactionKey = jsonString(record["reaction_key"]) ?? ""
        let reactionEmoji = jsonString(record["reaction_emoji"]) ?? "💬"
        let reactionText = jsonString(record["reaction_text"]) ?? ""
        let reactionCategory = jsonString(record["reaction_category"]) ?? "trash_talk"

        let createdAt: Date = {
            if let raw = jsonString(record["created_at"]) {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = iso.date(from: raw) { return parsed }
                iso.formatOptions = [.withInternetDateTime]
                if let parsed = iso.date(from: raw) { return parsed }
            }
            return Date()
        }()

        let reaction = ChallengeReaction(
            reactionId: reactionId,
            challengeId: challengeId,
            senderId: senderId,
            senderName: nil,
            senderPhotoUrl: nil,
            recipientId: recipientId,
            reactionKey: reactionKey,
            reactionEmoji: reactionEmoji,
            reactionText: reactionText,
            reactionCategory: reactionCategory,
            createdAt: createdAt
        )

        logRealtimeEvent(
            type: "🔥 INCOMING_REACTION",
            source: "incoming_reactions",
            details: "📣 \(reactionEmoji) \(reactionText) for challenge \(challengeIdString.prefix(8))"
        )

        applyIncomingBattleCry(reaction, widgetSenderDisplayName: nil)
    }

    private func persistStickyIncomingBattleCries() {
        var encoded: [String: ChallengeReaction] = [:]
        for (k, v) in dashboardIncomingBattleCryByChallenge {
            encoded[k.uuidString.lowercased()] = v
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        UserDefaults.standard.set(data, forKey: Self.stickyIncomingPersistenceKey)
    }

    private func hydrateStickyIncomingBattleCriesFromDiskIfNeeded() {
        guard !didHydrateStickyIncomingFromDisk else { return }
        didHydrateStickyIncomingFromDisk = true
        guard dashboardIncomingBattleCryByChallenge.isEmpty,
              let data = UserDefaults.standard.data(forKey: Self.stickyIncomingPersistenceKey),
              let decoded = try? JSONDecoder().decode([String: ChallengeReaction].self, from: data) else { return }
        var merged: [UUID: ChallengeReaction] = [:]
        for (k, v) in decoded {
            guard let uuid = UUID(uuidString: k) else { continue }
            merged[uuid] = v
        }
        dashboardIncomingBattleCryByChallenge = merged
        bumpBattleCryDashboardRenderToken()
    }

    /// Clears local pending-outgoing rows whose recipients already foregrounded
    /// (covers missed realtime UPDATE while the socket was torn down).
    func reconcileAcknowledgedOutgoingBattleCriesFromServer() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        struct Row: Decodable { let reaction_id: UUID }
        do {
            let rows: [Row] = try await SupabaseManager.shared.supabaseClient
                .rpc("list_acknowledged_battle_cry_ids_for_sender")
                .execute()
                .value
            var removedAny = false
            for row in rows {
                if dashboardOutgoingBattleCryByReactionId.removeValue(forKey: row.reaction_id) != nil {
                    removedAny = true
                }
            }
            if removedAny { bumpBattleCryDashboardRenderToken() }
        } catch {
            AppLogger.debug(
                "[OUTGOING_REACTION_ACK] reconcile RPC: \(error.localizedDescription)",
                category: .network
            )
        }
    }

    private func subscribeOutgoingBattleCryAcks(userId: UUID) async {
        await unsubscribeOutgoingBattleCryAcks()
        let client = SupabaseManager.shared.supabaseClient
        let channel = client.realtimeV2.channel("outgoing_reaction_acks-\(userId.uuidString)")
        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "challenge_reactions",
            filter: "sender_id=eq.\(userId.uuidString)"
        )
        outgoingBattleCryAckListenerTask = Task { [weak self] in
            for await action in updates {
                guard let self = self else { return }
                await self.handleOutgoingBattleCryAckUpdate(action.record)
            }
        }
        await channel.subscribe()
        outgoingBattleCryAckChannel = channel
        logRealtimeEvent(
            type: "SUBSCRIBED",
            source: "challenge_reactions_acks",
            details: "✅ Listening for UPDATE on challenge_reactions where sender_id=\(userId.uuidString.prefix(8))"
        )
    }

    private func unsubscribeOutgoingBattleCryAcks() async {
        outgoingBattleCryAckListenerTask?.cancel()
        outgoingBattleCryAckListenerTask = nil
        if let channel = outgoingBattleCryAckChannel {
            await SupabaseManager.shared.supabaseClient.realtimeV2.removeChannel(channel)
        }
        outgoingBattleCryAckChannel = nil
    }

    private func handleOutgoingBattleCryAckUpdate(_ record: [String: AnyJSON]?) async {
        guard let record = record else { return }
        guard jsonString(record["recipient_opened_app_at"]) != nil else { return }
        guard let idStr = jsonString(record["id"]),
              let rid = UUID(uuidString: idStr) else { return }
        guard dashboardOutgoingBattleCryByReactionId.removeValue(forKey: rid) != nil else { return }
        bumpBattleCryDashboardRenderToken()
        logRealtimeEvent(
            type: "✅ OUTGOING_BATTLE_CRY_ACK",
            source: "challenge_reactions",
            details: "Recipient opened app — cleared sender bubble \(idStr.prefix(8))"
        )
    }
}

// MARK: - Payload Types

struct FriendRequestPayload {
    let friendshipId: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
    let createdAt: Date
}

struct SharedWorkoutPayload {
    let workoutId: UUID
    let senderId: UUID
    let recipientId: UUID
    let workoutName: String
    let status: String
    let createdAt: Date
}

struct ChallengePayload {
    let challengeId: UUID
    let participantId: UUID
    let status: String
    let totalProgress: Int
}

struct DailyProgressPayload {
    let challengeId: UUID
    let opponentId: UUID
    let progressDate: String
    let progressValue: Int
    let targetHit: Bool
}

/// Entry for the realtime event debug log (visible in simulator & dev menu)
struct RealtimeEventEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: String           // e.g. "OPPONENT_DAILY_PROGRESS", "CHALLENGE_STATUS", etc.
    let source: String         // e.g. "challenge_daily_progress", "challenge_participants"
    let details: String
    let isError: Bool
    
    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}

// MARK: - App Integration Extension

extension RealtimeService {
    /// Setup default callbacks for notifications
    /// Call this after authentication
    func setupDefaultCallbacks() {
        guard !hasConfiguredCallbacks else { return }
        hasConfiguredCallbacks = true
        
        // Friend request received → refresh data (push notification handles the alert)
        onFriendRequestReceived = { payload in
            Task { @MainActor in
                // Refresh immediately so the UI shows the request instantly
                await FriendService.shared.fetchPendingRequests()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Friend request data refreshed from realtime callback", category: .network)
                // NOTE: No local notification here — the push notification from Supabase
                // handles the user-facing alert. Sending both would cause duplicates.
            }
        }
        
        // Friend request accepted → refresh data (push notification handles the alert)
        onFriendRequestAccepted = { _ in
            Task { @MainActor in
                await FriendService.shared.fetchFriends()
                AppLogger.debug("Friends list refreshed after acceptance", category: .network)
            }
        }
        
        // Workout received → refresh data (push notification handles the alert)
        onWorkoutReceived = { _ in
            Task { @MainActor in
                await FriendService.shared.loadReceivedWorkouts()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Received workouts refreshed from realtime", category: .network)
            }
        }
        
        // Challenge invite → refresh data (push notification handles the alert)
        onChallengeInviteReceived = { _ in
            Task { @MainActor in
                await ChallengeService.shared.fetchPendingInvites()
                await ChallengeService.shared.fetchActiveGroupChallenges()
                NotificationManager.shared.updateBadgeCount()
                AppLogger.debug("Challenge invites refreshed from realtime", category: .network)
            }
        }
        
        AppLogger.info("Default callbacks configured", category: .network)
    }
    
    /// Fetch a user's display name
    private func fetchUserName(userId: UUID) async -> String {
        do {
            struct UserProfile: Decodable {
                let name: String?
                let username: String?
            }
            
            let response: [UserProfile] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("name, username")
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            if let profile = response.first {
                return profile.name ?? profile.username ?? "Someone"
            }
        } catch {
            AppLogger.warning("Error fetching user name: \(error.localizedDescription)", category: .network)
        }
        
        return "Someone"
    }
}
