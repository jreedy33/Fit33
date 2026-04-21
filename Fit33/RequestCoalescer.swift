//
//  RequestCoalescer.swift
//  Sprint 5 (M-8): dedupe concurrent fetches keyed by a caller-supplied string.
//
//  Problem
//  -------
//  Multiple dashboard widgets (challenge list, friend feed, health sync tick)
//  can fire the SAME network request within a few hundred milliseconds of each
//  other. Each returns a separate in-flight `Task` → redundant Supabase RPC,
//  redundant JSON decode, redundant downstream `@Published` churn, and on
//  flaky networks, cascading retry storms.
//
//  Solution
//  --------
//  A tiny `actor` keyed store: when a caller asks for key `"friend_feed"`, we
//  check if a `Task<Output, Error>` already exists. If yes, both callers
//  `await` the same task and get the same result; if no, we spin up a fresh
//  task, store it, and remove it when it finishes. This is strictly a
//  concurrency-dedupe primitive — no TTL cache, no invalidation semantics —
//  callers must still decide whether their result is fresh.
//
//  Usage
//  -----
//  ```swift
//  let result: [FriendActivity] = try await RequestCoalescer.shared.coalesce(
//      key: "friend_feed_page_0"
//  ) {
//      try await SupabaseManager.shared.supabaseClient
//          .rpc("get_friend_activity_feed", params: …)
//          .execute()
//          .value
//  }
//  ```
//
//  Integration sites (wired by this same commit)
//  --------------------------------------------
//  - `ChallengeService.fetchActiveChallenges` / `fetchActiveGroupChallenges`
//  - `FriendActivityFeedView`'s feed loader via `ActivityFeedService`
//  - `HealthKitService.syncAllData` force-sync entry point
//
//  Thread safety
//  -------------
//  Being an `actor`, all mutation of the internal `inflight` dictionary is
//  serialized by the actor's executor. The wrapped `operation` closure runs
//  OFF the actor (Task body) so it does not block other coalesce calls.

import Foundation

actor RequestCoalescer {
    static let shared = RequestCoalescer()

    /// In-flight task per key. Erased to `Any` because Swift generics cannot
    /// live inside a heterogeneous dictionary. Callers provide the concrete
    /// `Output` type at the call site; we `as!`-cast back after the actor
    /// handoff — safe because only `coalesce<Output>` writes to this key, so
    /// the stored task's generic parameter is always the same `Output`.
    private var inflight: [String: Any] = [:]

    init() {}

    /// Deduplicate concurrent fetches. Callers with the same `key` share the
    /// single underlying `operation` Task and await the same result.
    /// - Parameters:
    ///   - key: Opaque identifier for the request. Include any parameters
    ///     that distinguish it (page number, filter, user id) so distinct
    ///     fetches don't accidentally coalesce.
    ///   - operation: Async work to run when there's no in-flight task for
    ///     this key. Failures propagate to every waiter on this key.
    func coalesce<Output>(
        key: String,
        operation: @Sendable @escaping () async throws -> Output
    ) async throws -> Output {
        if let existing = inflight[key] as? Task<Output, Error> {
            return try await existing.value
        }

        let task = Task<Output, Error> {
            try await operation()
        }
        inflight[key] = task

        defer { inflight[key] = nil }
        return try await task.value
    }

    /// Non-throwing variant for endpoints whose failure is already recoverable
    /// upstream (e.g. `fetchActiveChallenges` which just keeps cached data on
    /// error). Returns `nil` to every waiter if the operation throws.
    func coalesce<Output>(
        key: String,
        operation: @Sendable @escaping () async -> Output?
    ) async -> Output? {
        if let existing = inflight[key] as? Task<Output?, Never> {
            return await existing.value
        }

        let task = Task<Output?, Never> {
            await operation()
        }
        inflight[key] = task

        defer { inflight[key] = nil }
        return await task.value
    }

    /// `Void` convenience: for side-effect-only fetchers (e.g. functions that
    /// mutate `@Published` state directly rather than returning a value).
    /// Concurrent callers share one Task and therefore one side-effect run.
    func coalesceVoid(
        key: String,
        operation: @Sendable @escaping () async -> Void
    ) async {
        if let existing = inflight[key] as? Task<Void, Never> {
            await existing.value
            return
        }

        let task = Task<Void, Never> {
            await operation()
        }
        inflight[key] = task

        defer { inflight[key] = nil }
        await task.value
    }

    /// Clear every in-flight entry. Intended for sign-out / testing. NOT for
    /// general invalidation — individual callers own that concern.
    func reset() {
        inflight.removeAll()
    }
}
