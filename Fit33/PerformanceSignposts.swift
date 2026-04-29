import Foundation
import os

// MARK: - Performance Signposts
//
// Centralized `os_signpost` + metric-persistence layer used across the
// app's hot paths (startup, dashboard hydrate, social fan-out, weight
// log, social feed fetch, etc.).
//
// Every call site that previously only logged `AppLogger.warning` on
// slow paths now wraps the work in a signpost. This gives us three
// measurement channels simultaneously:
//
//   1. Instruments (Points of Interest instrument)  → flame-chart tracing
//   2. Console.app / Xcode debug console            → immediate feedback
//   3. Supabase `performance_metrics` table         → long-tail trending
//      (wired up by Cluster I — `persistMetric()` is a no-op until then)
//
// Usage — measure a fire-and-forget async block:
//
//    let state = PerformanceSignposts.begin(.dashboardHydrate)
//    defer { PerformanceSignposts.end(state) }
//    try await hydrateDashboard()
//
// Or with the closure helper (preferred):
//
//    try await PerformanceSignposts.measure(.dashboardHydrate) {
//        try await hydrateDashboard()
//    }
//
// Operation names are enum-typed so we can rename without chasing
// strings across the app. All names are lowercase with dots for scope.

enum PerformanceSignposts {
    // MARK: Canonical operation names

    /// Every measurable hot-path has a stable name here. Adding a new
    /// case does NOT require any migration — `performance_metrics.op`
    /// is a free-form TEXT column with a GIN index.
    enum Op: String {
        // Startup fan-out (Cluster A)
        case appLaunch               = "app.launch"
        case appForeground           = "app.foreground"
        case appFirstFrame           = "app.first_frame"
        case dashboardHydrate        = "dashboard.hydrate"
        case dashboardSocialFanOut   = "dashboard.social_fanout"
        case startupCoordinatorStage = "startup.coordinator_stage"

        // Auth + session (Cluster D)
        case authWaitForFreshSession = "auth.wait_for_fresh_session"
        case authSessionRecovery     = "auth.session_recovery"

        // Writes (Clusters B/C)
        case weightLog               = "weight.log"
        case stepSave                = "step.save"
        case dailyActivitySave       = "daily_activity.save"
        case cardioSave              = "cardio.save"
        case workoutSave             = "workout.save"
        case healthKitSleepSave      = "healthkit.sleep_save"

        // Social (Cluster G)
        case friendsFetch            = "friends.fetch"
        case activityFeedFetch       = "activity_feed.fetch"
        case challengesFetch         = "challenges.fetch"
        case postWorkoutActivity     = "social.post_workout_activity"
        case postCardioActivity      = "social.post_cardio_activity"

        // Integrations (Cluster D)
        case stravaSync              = "strava.sync"

        // MARK: Phase 9 classifier rollout (added 2026-04-23)
        //
        // Coarse grouping — the structural_fingerprint keys off `op || endpoint`,
        // so "friends.list + rpc/get_friends" and "friends.list + rpc/get_blocked_users"
        // still fingerprint separately. The op is for cluster-level trending, the
        // endpoint distinguishes specific call sites.

        // FriendService
        case friendsList              = "friends.list"
        case friendsWrite             = "friends.write"
        case friendRequestList        = "friend_request.list"
        case friendRequestWrite       = "friend_request.write"
        case sharedWorkoutList        = "shared_workout.list"
        case sharedWorkoutWrite       = "shared_workout.write"
        case socialNotificationList   = "social_notification.list"
        case socialNotificationWrite  = "social_notification.write"

        // ChallengeService
        case challengeCache           = "challenge.cache"
        case challengeRead            = "challenge.read"
        case challengeWrite           = "challenge.write"
        case challengeGroupWrite      = "challenge.group.write"
        case challengePreferences     = "challenge.preferences"
        case challengeProgressSync    = "challenge.progress_sync"

        // SupabaseManager — auth
        case authSignUp               = "auth.sign_up"
        case authSignIn               = "auth.sign_in"
        case authSignOut              = "auth.sign_out"
        case authPasswordReset        = "auth.password_reset"
        case authResendEmail          = "auth.resend_email"

        // SupabaseManager — profile / username / exercise
        case profileRead              = "profile.read"
        case profileWrite             = "profile.write"
        case profileSync              = "profile.sync"
        case usernameWrite            = "username.write"
        case exerciseUpdate           = "exercise.update"

        // SupabaseManager — Core Data ↔ cloud sync fan-out
        case cloudSyncProfile         = "cloud_sync.profile"
        case cloudSyncWorkout         = "cloud_sync.workout"
        case cloudSyncMeal            = "cloud_sync.meal"
        case cloudSyncFavorite        = "cloud_sync.favorite"
        case cloudSyncCustomExercise  = "cloud_sync.custom_exercise"
        case cloudSyncFavoriteWorkout = "cloud_sync.favorite_workout"

        // Nutrition / food search (Cluster H — added 2026-04-25 to drain
        // the 21:24 burst of `Cloud search error: Unauthorized` /
        // `Edge function error: Unauthorized` / `Food search error: Unauthorized`
        // / `USDA API Error: Search failed: Unauthorized` fingerprints
        // [`0bddbb48` / `479cf818` / `d0aaa6e5` / `f94ae6fe`]. Top-level
        // catches in USDAFoodService.performSearch + FoodDatabaseService.searchFoods
        // were AppLogger.error'ing transient 401s mid-foreground refresh.)
        case foodSearch               = "food.search"
        case foodDetails              = "food.details"

        // Monetization / In-App Purchase (Phase 1d — added 2026-04-29 per
        // MONETIZATION_AGENT.md invariants 32–33 + BUG_INTELLIGENCE_AGENT
        // invariants 1–2. StoreKit transactions are async network calls —
        // a sandbox outage or transient App Store flap would otherwise
        // generate a fingerprint per occurrence. Routing IAP catches
        // through NetworkErrorClassifier.log(op:) with these registered
        // ops collapses them to one fingerprint per call site.)
        case iapLoadProducts          = "iap.load_products"
        case iapPurchase              = "iap.purchase"
        case iapRestore               = "iap.restore"
        case iapEntitlementRefresh    = "iap.entitlement_refresh"
        case iapServerVerify          = "iap.server_verify"
    }

    // MARK: Thresholds

    /// Operations slower than this are logged at `.warning` (with
    /// DiagnosticContext so the Bug Intelligence rollup can trend them).
    /// Kept conservative (3s) to match `MainThreadWatchdog.criticalThreshold`.
    /// Individual ops can override via `end(_:slowThresholdMs:)`.
    static let defaultSlowThresholdMs: Int = 3_000

    // MARK: Internals

    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.fit33",
        category: "PerformanceSignposts"
    )

    /// Persistence queue — backing storage for `performance_metrics`.
    /// Cluster I wires this to `SupabaseManager.client.from("performance_metrics").insert(...)`.
    /// Until then, entries are buffered in-memory (bounded) and logged at debug level.
    private static let pendingMetricsQueue = DispatchQueue(label: "com.fit33.perfSignposts.metrics", qos: .utility)
    private static var pendingMetrics: [PerformanceMetric] = []
    private static let pendingMetricsMax = 500

    /// In-flight signpost state returned by `begin(...)`.
    struct State {
        let op: Op
        let intervalState: OSSignpostIntervalState
        let startedAt: Date
        let startedAtMono: CFAbsoluteTime
    }

    // MARK: Begin / End

    @discardableResult
    static func begin(_ op: Op) -> State {
        let intervalState = signposter.beginInterval(
            "op",
            id: signposter.makeSignpostID(),
            "\(op.rawValue, privacy: .public)"
        )
        return State(
            op: op,
            intervalState: intervalState,
            startedAt: Date(),
            startedAtMono: CFAbsoluteTimeGetCurrent()
        )
    }

    /// End the interval. Emits `os_signpost(end)`, enqueues a
    /// `PerformanceMetric` row, and logs a warning if `elapsedMs >= threshold`.
    static func end(
        _ state: State,
        slowThresholdMs: Int? = nil,
        endpoint: String? = nil,
        userId: UUID? = nil,
        extra: [String: String]? = nil
    ) {
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - state.startedAtMono) * 1000)

        signposter.endInterval("op", state.intervalState, "\(elapsedMs)ms")

        enqueueMetric(PerformanceMetric(
            op: state.op.rawValue,
            elapsedMs: elapsedMs,
            startedAt: state.startedAt,
            endpoint: endpoint,
            userId: userId,
            extra: extra
        ))

        let threshold = slowThresholdMs ?? defaultSlowThresholdMs
        if elapsedMs >= threshold {
            let ctx = DiagnosticContext.timing(
                op: state.op.rawValue,
                elapsedMs: elapsedMs,
                endpoint: endpoint,
                userId: userId
            )
            AppLogger.warning(
                "slow operation \(state.op.rawValue) took \(elapsedMs)ms (threshold \(threshold)ms)",
                category: .performance,
                context: ctx
            )
        }
    }

    // MARK: Closure helper

    /// Measure a throwing async block. Signpost ends even if the closure
    /// throws, so partial latencies are still recorded.
    static func measure<T>(
        _ op: Op,
        slowThresholdMs: Int? = nil,
        endpoint: String? = nil,
        userId: UUID? = nil,
        operation: () async throws -> T
    ) async rethrows -> T {
        let state = begin(op)
        do {
            let result = try await operation()
            end(state, slowThresholdMs: slowThresholdMs, endpoint: endpoint, userId: userId)
            return result
        } catch {
            end(
                state,
                slowThresholdMs: slowThresholdMs,
                endpoint: endpoint,
                userId: userId,
                extra: ["outcome": "threw", "error_type": String(describing: type(of: error))]
            )
            throw error
        }
    }

    /// Synchronous closure helper.
    static func measureSync<T>(
        _ op: Op,
        slowThresholdMs: Int? = nil,
        endpoint: String? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        let state = begin(op)
        do {
            let result = try operation()
            end(state, slowThresholdMs: slowThresholdMs, endpoint: endpoint)
            return result
        } catch {
            end(
                state,
                slowThresholdMs: slowThresholdMs,
                endpoint: endpoint,
                extra: ["outcome": "threw", "error_type": String(describing: type(of: error))]
            )
            throw error
        }
    }

    // MARK: Metric persistence hooks

    /// Snapshot + drain of in-memory metrics. Cluster I's
    /// `PerformanceMetricsUploader` calls this on a timer to batch-insert.
    static func drainPendingMetrics() -> [PerformanceMetric] {
        pendingMetricsQueue.sync {
            let snapshot = pendingMetrics
            pendingMetrics.removeAll(keepingCapacity: true)
            return snapshot
        }
    }

    private static func enqueueMetric(_ metric: PerformanceMetric) {
        pendingMetricsQueue.async {
            if pendingMetrics.count >= pendingMetricsMax {
                // Drop oldest to avoid unbounded memory growth (measurement
                // must never cause the very problem it's trying to detect).
                pendingMetrics.removeFirst(pendingMetrics.count - pendingMetricsMax + 1)
            }
            pendingMetrics.append(metric)
        }
    }
}

// MARK: - PerformanceMetric
//
// Mirrors the `performance_metrics` table created by migration
// `20260514_performance_metrics.sql`. Codable so Cluster I's uploader
// can batch-insert via PostgREST.

struct PerformanceMetric: Codable {
    let op: String
    let elapsedMs: Int
    let startedAt: Date
    let endpoint: String?
    let userId: UUID?
    let extra: [String: String]?

    enum CodingKeys: String, CodingKey {
        case op
        case elapsedMs   = "elapsed_ms"
        case startedAt   = "started_at"
        case endpoint
        case userId      = "user_id"
        case extra
    }
}
