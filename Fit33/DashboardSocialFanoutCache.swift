//
//  DashboardSocialFanoutCache.swift
//  Fit33
//
//  Snappiness Overhaul Phase 5.A — Dashboard `social_fanout` 5-min disk cache
//  (`PerfFlags.phase5DashboardCache`).
//
//  Mirrors the Phase 3 similarity-map disk-cache pattern:
//    • `Library/Caches/dashboard_social_fanout.<userId>.plist`
//    • `PropertyListEncoder(.binary)` payload (`DashboardSocialFanoutCachePayload`)
//    • TTL: 5 minutes from `cachedAt`.
//    • User-scoped via the file name AND the `userId` field on the payload
//      (defense-in-depth — both a path mismatch AND a payload mismatch must
//      pass for a hit, so a stale file from a previous account cannot leak).
//    • Process-pinned via `processId`. iOS keeps service singletons
//      (`FriendService`, `ChallengeService`, etc.) alive ONLY for the lifetime
//      of the running process. A disk-cache hit from a previous app launch is
//      meaningless — those services are empty after a relaunch and need a
//      live fanout to populate. Pinning to the current `ProcessInfo.processIdentifier`
//      makes cold-start always miss (correct behavior).
//
//  Behavior preservation when `phase5DashboardCache` is OFF: the cache exists
//  in memory but `read(...)` always returns `nil` because every public read /
//  hit-attempt is gated on the flag. The notification observers ARE always
//  installed so a flag-flip mid-session doesn't leave a stale file behind —
//  observer fire is a cheap file-delete that is a no-op when the file
//  doesn't exist.
//
//  Cache-invalidation observers (registered once at first cache access):
//    • `Notification.Name.workoutCompleted`        — emitted by WorkoutManager.
//    • `Notification.Name.externalWorkoutSynced`   — Strava / Fitbit / HK sync-in.
//    • `Notification.Name.userDidSignOut`          — user logout / account switch.
//    • `Notification.Name.dashboardCacheInvalidate` — manual / external nuke.
//
//  See `PRODUCT_ENGINEER_AGENT.md` invariant 13 (every social write should
//  end with a notification flush) — this cache participates in that contract
//  by listening for the resulting state-change notifications and dropping
//  the stale snapshot.
//

import Foundation

// MARK: - Notification Names (added by Phase 5.A)

extension Notification.Name {
    /// Posted when the dashboard social-fanout cache has been refreshed in the
    /// background (stale-while-revalidate completion). Dashboard widgets that
    /// want to re-publish their `@Published` slots can observe this to know
    /// "the underlying RPC fanout just landed, you may have new data". The
    /// services that the fanout writes through (FriendService,
    /// ChallengeService, etc.) already publish their own `@Published` updates;
    /// this is a coarser "everything just refreshed" signal.
    static let dashboardWidgetsRefreshed = Notification.Name("Fit33.dashboardWidgetsRefreshed")

    /// Posted by `WorkoutManager.finishWorkout()` AFTER state cleanup, gated
    /// on `PerfFlags.phase5DashboardCache` (so behavior is byte-equivalent
    /// when the flag is OFF). Dashboard cache observes this to drop any
    /// 5-min-stale snapshot — a freshly-completed workout has bumped streak,
    /// XP, friend-feed, and challenge progress that the user expects to see
    /// immediately when they navigate to the dashboard.
    static let workoutCompleted = Notification.Name("Fit33.workoutCompleted")

    /// Posted by `SupabaseManager.signOut()` after auth state is cleared. The
    /// dashboard cache observes this to delete every cached file (defense-in-
    /// depth — `read(forUser:)` already enforces user-scoping via filename
    /// and payload, but a wholesale sweep at sign-out leaves no stale
    /// snapshot on disk for the next user to potentially read).
    static let userDidSignOut = Notification.Name("Fit33.userDidSignOut")

    /// Generic "drop the cache now" hook for callers that don't fit the
    /// other invalidation buckets (e.g. friend follow / unfollow, achievement
    /// unlocked) and don't want to wait 5 minutes for natural TTL expiry.
    /// Posting this is always safe — it's a single file delete.
    static let dashboardCacheInvalidate = Notification.Name("Fit33.dashboardCacheInvalidate")
}

// MARK: - Codable Payload

/// On-disk representation of a completed `dashboard.social_fanout`. Captures
/// only summary counts (not full DTOs) — the cache exists to gate re-fetching,
/// not to seed UI from disk. Service singletons hold the actual rendered
/// data in `@Published` arrays for the lifetime of the process.
struct DashboardSocialFanoutCachePayload: Codable, Equatable {
    let userId: UUID
    let cachedAt: Date
    /// `ProcessInfo.processIdentifier` of the process that wrote the file.
    /// A value mismatch on read = the writing process has exited (cold start
    /// after backgrounding), and the in-memory services that this cache
    /// referred to are now empty. Treat as a miss.
    let processId: Int
    let snapshot: ServiceSnapshot

    /// Per-service summary captured at fanout-completion time. None of the
    /// fields are required to render the dashboard — they exist so a future
    /// PR can do "did the snapshot drift since last write?" verification, and
    /// so unit tests can assert round-trip integrity beyond just `cachedAt`.
    struct ServiceSnapshot: Codable, Equatable {
        let friendCount: Int
        let activeChallengeCount: Int
        let pendingInviteCount: Int
        let activityFeedCount: Int
        let receivedWorkoutCount: Int
    }
}

// MARK: - Cache Singleton

@MainActor
final class DashboardSocialFanoutCache {

    static let shared = DashboardSocialFanoutCache()

    /// 5-minute TTL — chosen to match the `dashboard.social_fanout` 3000ms
    /// SLO budget. Within 5 min the user's friend/challenge/feed state is
    /// rarely meaningfully stale; outside that window we'd rather pay the
    /// fanout cost than risk missing an event the realtime channel dropped.
    static let ttl: TimeInterval = 5 * 60

    private var didRegisterObservers = false
    private var notificationTokens: [NSObjectProtocol] = []

    private init() {
        registerInvalidationObserversOnce()
    }

    // MARK: - Public Read / Write

    /// Reads the cached payload for `userId`. Returns `nil` when:
    ///   • The flag is OFF.
    ///   • No cache file exists for this user.
    ///   • The file's `cachedAt` is older than `ttl` (5 min).
    ///   • The file was written by a different process (cold-start guard).
    ///   • The file's payload `userId` mismatches the requested userId.
    /// Emits `perf.signpost.dashboard.cache_hit_rate` on every attempt.
    func read(forUser userId: UUID) -> DashboardSocialFanoutCachePayload? {
        guard PerfFlags.phase5DashboardCache else {
            // Flag OFF — no telemetry counter (we don't want to skew the hit
            // rate signal with no-op reads). Return nil so the caller falls
            // through to the fanout path.
            return nil
        }

        guard let url = cacheURL(forUser: userId),
              let data = try? Data(contentsOf: url) else {
            AppLogger.info("perf.signpost.dashboard.cache_hit_rate=0", category: .performance)
            return nil
        }

        guard let payload = try? PropertyListDecoder().decode(
            DashboardSocialFanoutCachePayload.self,
            from: data
        ) else {
            // Decoder failure (e.g. format change, partial write) — wipe the
            // bad file so the next write starts clean.
            try? FileManager.default.removeItem(at: url)
            AppLogger.warning(
                "[DASHBOARD CACHE] Decode failed — purged stale file at \(url.lastPathComponent)",
                category: .performance
            )
            AppLogger.info("perf.signpost.dashboard.cache_hit_rate=0", category: .performance)
            return nil
        }

        // Defense-in-depth: payload userId must match the filename's userId
        // (already guaranteed by `cacheURL(forUser:)`, but verify).
        guard payload.userId == userId else {
            try? FileManager.default.removeItem(at: url)
            AppLogger.warning(
                "[DASHBOARD CACHE] User mismatch (payload=\(payload.userId), requested=\(userId)) — purged",
                category: .performance
            )
            AppLogger.info("perf.signpost.dashboard.cache_hit_rate=0", category: .performance)
            return nil
        }

        let age = Date().timeIntervalSince(payload.cachedAt)
        guard age < Self.ttl else {
            // TTL miss — let the file linger; the next write overwrites it.
            // Don't delete here so a cold-start cache-write race can't trip
            // over us between read and write.
            AppLogger.info(
                "perf.signpost.dashboard.cache_hit_rate=0",
                category: .performance
            )
            AppLogger.debug(
                "[DASHBOARD CACHE] TTL miss — age=\(Int(age))s for \(url.lastPathComponent)",
                category: .performance
            )
            return nil
        }

        let currentPid = Int(ProcessInfo.processInfo.processIdentifier)
        guard payload.processId == currentPid else {
            // Different process wrote this — services in memory are empty
            // now (cold start). Treat as a miss; the upcoming fanout will
            // rewrite the file with the current PID.
            AppLogger.info(
                "perf.signpost.dashboard.cache_hit_rate=0",
                category: .performance
            )
            AppLogger.debug(
                "[DASHBOARD CACHE] Process mismatch (file=\(payload.processId), now=\(currentPid)) — cold-start miss",
                category: .performance
            )
            return nil
        }

        AppLogger.info("perf.signpost.dashboard.cache_hit_rate=1", category: .performance)
        AppLogger.debug(
            "[DASHBOARD CACHE] HIT — age=\(Int(age))s for user=\(userId)",
            category: .performance
        )
        return payload
    }

    /// Writes the payload to disk for `userId`. Idempotent and safe to call
    /// multiple times in a row (the encoder is deterministic + write is
    /// `.atomic`). When the flag is OFF this is a no-op so a flag toggle
    /// during a session can't accidentally leave a stale file behind.
    func write(forUser userId: UUID, snapshot: DashboardSocialFanoutCachePayload.ServiceSnapshot) {
        guard PerfFlags.phase5DashboardCache else { return }
        guard let url = cacheURL(forUser: userId) else { return }

        let payload = DashboardSocialFanoutCachePayload(
            userId: userId,
            cachedAt: Date(),
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            snapshot: snapshot
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)
            AppLogger.debug(
                "[DASHBOARD CACHE] WRITE — \(data.count)B for user=\(userId)",
                category: .performance
            )
        } catch {
            AppLogger.error(
                "[DASHBOARD CACHE] WRITE failed: \(error.localizedDescription)",
                category: .performance
            )
        }
    }

    /// Drops the cache file for `userId`. Idempotent.
    func invalidate(forUser userId: UUID) {
        guard let url = cacheURL(forUser: userId) else { return }
        try? FileManager.default.removeItem(at: url)
        AppLogger.debug(
            "[DASHBOARD CACHE] INVALIDATE — \(url.lastPathComponent)",
            category: .performance
        )
    }

    /// Drops every cache file under `Library/Caches` matching the
    /// `dashboard_social_fanout.*.plist` filename pattern. Used on sign-out
    /// (purge all signed-in users' files) and from tests for clean baselines.
    func invalidateAll() {
        guard let cachesDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: cachesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else { return }
        var purged = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(Self.filenamePrefix) && name.hasSuffix(".plist") {
                if (try? fm.removeItem(at: url)) != nil { purged += 1 }
            }
        }
        AppLogger.debug(
            "[DASHBOARD CACHE] INVALIDATE-ALL — purged \(purged) file(s)",
            category: .performance
        )
    }

    // MARK: - Snapshot Builder
    //
    // Convenience that walks the canonical 5 services the dashboard fanout
    // populates and captures their array sizes. Lives on the cache (instead
    // of inline at every call site) so any future fanout-shape change has a
    // single place to update.

    func snapshotFromCurrentServiceState() -> DashboardSocialFanoutCachePayload.ServiceSnapshot {
        DashboardSocialFanoutCachePayload.ServiceSnapshot(
            friendCount: FriendService.shared.friends.count,
            activeChallengeCount: ChallengeService.shared.activeChallenges.count,
            pendingInviteCount: ChallengeService.shared.pendingInvites.count,
            activityFeedCount: ActivityFeedService.shared.activities.count,
            receivedWorkoutCount: FriendService.shared.receivedWorkouts.count
        )
    }

    // MARK: - Internals

    private static let filenamePrefix = "dashboard_social_fanout."

    /// `Library/Caches/dashboard_social_fanout.<userId>.plist`. Returns nil
    /// only if the OS can't resolve the caches directory (extremely rare;
    /// silently disables caching for this session).
    private func cacheURL(forUser userId: UUID) -> URL? {
        guard let cachesDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDir.appendingPathComponent(
            "\(Self.filenamePrefix)\(userId.uuidString).plist"
        )
    }

    private func registerInvalidationObserversOnce() {
        guard !didRegisterObservers else { return }
        didRegisterObservers = true

        let center = NotificationCenter.default

        // Workout completion — drops cache for the current user so the next
        // dashboard visit shows fresh streak / XP / activity-feed state.
        notificationTokens.append(center.addObserver(
            forName: .workoutCompleted, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let userId = UserManager.shared.currentUser?.id else { return }
                self?.invalidate(forUser: userId)
                AppLogger.debug(
                    "[DASHBOARD CACHE] Invalidated by workoutCompleted",
                    category: .performance
                )
            }
        })

        // External-source workout (Strava / Fitbit / HK) — drops cache so
        // the recently-imported workout appears in the dashboard's recent
        // activity rail on the next visit. Same pattern as workoutCompleted.
        notificationTokens.append(center.addObserver(
            forName: .externalWorkoutSynced, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let userId = UserManager.shared.currentUser?.id else { return }
                self?.invalidate(forUser: userId)
                AppLogger.debug(
                    "[DASHBOARD CACHE] Invalidated by externalWorkoutSynced",
                    category: .performance
                )
            }
        })

        // Sign-out — purge ALL users' files (not just the current) so a
        // signed-out device with multiple historical accounts can't leak.
        notificationTokens.append(center.addObserver(
            forName: .userDidSignOut, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invalidateAll()
                AppLogger.debug(
                    "[DASHBOARD CACHE] Invalidated by userDidSignOut (all)",
                    category: .performance
                )
            }
        })

        // Generic invalidation hook (achievement unlock, friend follow /
        // unfollow, etc.) — drops cache for current user.
        notificationTokens.append(center.addObserver(
            forName: .dashboardCacheInvalidate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let userId = UserManager.shared.currentUser?.id else { return }
                self?.invalidate(forUser: userId)
                AppLogger.debug(
                    "[DASHBOARD CACHE] Invalidated by dashboardCacheInvalidate",
                    category: .performance
                )
            }
        })
    }

    deinit {
        // Singleton in practice never deallocs, but match the
        // OlympianPathService pattern for defensive symmetry.
        let center = NotificationCenter.default
        for token in notificationTokens {
            center.removeObserver(token)
        }
    }

    #if DEBUG
    /// Test seam — synchronously check whether a cache file currently exists
    /// on disk for `userId`. DEBUG-only.
    func _testHook_fileExists(forUser userId: UUID) -> Bool {
        guard let url = cacheURL(forUser: userId) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    #endif
}
