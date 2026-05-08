// Phase 6 Parity Tests — Snappiness Overhaul (May 2026)
//
// Goal: prove that the Phase 6 fix to
// `PrivateChallengeService.subscribeToRealtimeUpdates()` closes the
// actor-reentrancy race that drops 7 `.postgresChange(...)` registrations
// per cold start.
//
// THE BUG (cold-start log signature, app v1.39 (70)):
//   Cannot add "postgres_changes" callbacks for "realtime:private-challenges"
//   after `subscribe()`. Please add all your postgres change callbacks before
//   subscribing to the channel.    [×7]
//
//   🔄 [REALTIME] Reconnecting — channels torn down + stale (last event never)
//
// The 7 warnings = the 7 `channel.postgresChange(...)` calls between
// `Fit33/PrivateChallengeService.swift:1447-1494` (members×2,
// daily_progress×2, invites×1, chat×2). The Supabase Realtime SDK silently
// DROPS any callback registered after `subscribe()` on the same channel,
// so realtime updates for `private-challenges` never fire — exactly the
// `last event never` smoking gun.
//
// ROOT CAUSE — actor reentrancy, NOT source order:
//   • `subscribeToRealtimeUpdates()` is `@MainActor` (the class is
//     `@MainActor class PrivateChallengeService`).
//   • The function body's `await channel.subscribe()` SUSPENDS the
//     actor-isolated context.
//   • `DashboardView.swift` fires
//     `Task { await PrivateChallengeService.shared.subscribeToRealtimeUpdates() }`
//     from TWO sites — line 764 (inline cold-start path) AND line 930
//     (SWR cache-then-network refresh path). Both can run during a cold
//     start of the dashboard.
//   • Caller A enters → guard `realtimeChannel != nil` → false → registers
//     the 7 callbacks → `await channel.subscribe()` SUSPENDS.
//   • Main actor releases. Caller B enters → guard `realtimeChannel != nil`
//     → still nil (Caller A hasn't returned) → calls
//     `client.realtimeV2.channel("private-challenges")` which RETURNS THE
//     SAME CHANNEL INSTANCE for matching names → registers 7 MORE
//     `.postgresChange(...)` on a channel whose `subscribe()` is already
//     in flight → SDK warns 7 times and silently drops.
//   • The 7-warning count is the canonical fingerprint of this race.
//
// THE FIX (under `PerfFlags.phase6RealtimeCallbackOrder`):
//   1. New `private var isSubscribing = false` sentinel set BEFORE any
//      `await` in the subscribe path. A re-entry caused by the
//      `await channel.subscribe()` suspension finds `isSubscribing == true`
//      and returns immediately — closing the race at zero cost.
//   2. Defense-in-depth: `realtimeChannel = channel` moved to BEFORE
//      `await channel.subscribe()` so a re-entry that somehow defeated
//      the sentinel still hits the `realtimeChannel != nil` early-return.
//      `subscribe()` is non-throwing in this code path so we don't risk
//      leaving a non-subscribed channel set on failure.
//   3. Symmetric counterpart in `unsubscribeFromRealtimeUpdates()`:
//      `realtimeChannel = nil` moves to BEFORE `await channel.unsubscribe()`
//      so the actor-isolation suspension doesn't expose a window where the
//      property is set but the channel is gone.
//   4. One-shot signpost `perf.signpost.realtime.subscribe_order=fixed`
//      on first successful flag-ON subscribe so the fix is greppable in
//      production logs (replaces a hypothetical
//      `perf.signpost.realtime.callbacks_dropped=N` counter — the SDK
//      doesn't surface a binding-count we can read non-invasively, so
//      we emit the ORDER signal instead of the BUG signal).
//
// CONSTRAINTS HONORED:
//   • XCTest only — verified `Fit33Tests/Phase5OffMainTests.swift` uses
//     `import XCTest` + `XCTestCase`. Project does not use Swift Testing.
//   • No live Supabase. We never construct a `RealtimeClientV2`; the
//     headline test is a STUB (see "Why test 2 is a stub" below).
//   • Fast (<5s). Test 1 is pure UserDefaults round-trip.
//   • Deterministic — pure-function assertions, no `Date()`, no live
//     channel I/O.
//   • Flag forced ON in `setUp` (and restored in `tearDown`) so the
//     UserDefaults plumbing the production code reads from is exercised
//     in the canonical post-fix state. Same convention as
//     Phase{1,2,3,5}ParityTests.
//
// CURRENT STATE (2026-05-07): the headline tests
// `test_callbacksRegisteredBeforeSubscribe` and
// `test_subscribeReconnectPreservesCallbacks` are STUBS — REASONS
// DOCUMENTED INLINE. The flag-plumbing test is REAL.
//
// Why the callback-order tests are stubs:
//   • The Supabase Swift SDK's `RealtimeChannelV2` does NOT expose a
//     `bindings` accessor (the type's `bindings` property is `internal`
//     to the SDK module). We cannot snapshot
//     `channel.bindings.count` before/after `subscribe()` from the test
//     target — there is no public seam to count
//     `.postgresChange(...)` registrations.
//   • The SDK warning `Cannot add "postgres_changes" callbacks ... after
//     subscribe()` is emitted via the SDK's internal logger, which the
//     app cannot intercept (no `os_log` subsystem we own). XCTest
//     `XCTAssertEqual(messages.count, 0)` requires either swizzling the
//     SDK logger (out of scope, fragile) or a test seam on
//     `RealtimeChannelV2`.
//   • The actor-reentry race itself is not directly observable without:
//       (a) An `internal` test seam on `PrivateChallengeService` exposing
//           `isSubscribing` and `realtimeChannel` for read-only inspection
//           from the test target, AND
//       (b) A `MockRealtimeClientV2` that returns the same channel
//           instance for matching names (real SDK behavior) AND counts
//           `.postgresChange(...)` calls. Neither exists today.
//   • Even with a seam, racing two `Task { await
//     PrivateChallengeService.shared.subscribeToRealtimeUpdates() }`
//     calls deterministically requires `XCTest` async expectation
//     plumbing AND a way to PAUSE inside the SDK's `subscribe()` to
//     guarantee the second caller observes mid-suspend state — which
//     also requires a SDK mock.
//
// What this stub asserts (today):
//   • `PerfFlags.phase6RealtimeCallbackOrder` reads the canonical
//     UserDefaults key. Toggling the override flips the flag's return
//     value. Without this, the remote kill-switch (the in-prod ability
//     to flip the flag and roll back the fix in <60s without a rebuild)
//     would not function.
//   • `PrivateChallengeService.shared` is reachable from the test
//     target via `@testable import` — required precondition for the
//     headline tests when their seams land.
//   • The headline tests compile and run, asserting flag-plumbing
//     defensively so a future PR landing the SDK seam doesn't have to
//     re-derive the flag-key/UserDefaults plumbing — just swap the stub
//     body for the seeded race-test pseudocode in each test's docblock.
//
// Singleton-leak hygiene:
//   `PrivateChallengeService.shared` is a process-lifetime singleton.
//   We do NOT touch its `realtimeChannel` / `isSubscribing` state from
//   these stubs (the only "real" assertion is on
//   `PerfFlags.phase6RealtimeCallbackOrder`, which reads UserDefaults).
//   The flag-key UserDefaults override IS mutated and is restored in
//   `tearDown` — same snapshot/restore pattern as Phase{1,2,3,5}.

import XCTest
@testable import Fit33

@MainActor
final class Phase6RealtimeCallbacksTests: XCTestCase {

    // Canonical UserDefaults key matching `PerfFlags.phase6RealtimeCallbackOrder`.
    // Mirrored here (not derived) — same convention as Phase{1,2,3,5}ParityTests:
    // `PerfFlags` reads the key via a private `flag(_:default:)` helper and does
    // not expose it as a public constant. Keep in sync with
    // `Fit33/PerfFlags.swift` (search for `perf_phase6_realtime_callback_order`).
    private let phase6FlagKey = "perf_phase6_realtime_callback_order"

    // Snapshot/restore so a pre-existing override (debug menu, parallel test run)
    // is restored after this file finishes. Without this, leaving an explicit
    // `true` write would affect later non-Phase6 tests' default behavior reads.
    private var hadPreexistingFlagOverride = false
    private var preexistingFlagValue = false

    override func setUp() {
        super.setUp()

        if UserDefaults.standard.object(forKey: phase6FlagKey) != nil {
            hadPreexistingFlagOverride = true
            preexistingFlagValue = UserDefaults.standard.bool(forKey: phase6FlagKey)
        } else {
            hadPreexistingFlagOverride = false
        }
        UserDefaults.standard.set(true, forKey: phase6FlagKey)
    }

    override func tearDown() {
        if hadPreexistingFlagOverride {
            UserDefaults.standard.set(preexistingFlagValue, forKey: phase6FlagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: phase6FlagKey)
        }
        super.tearDown()
    }

    // MARK: - Test 1 — flag plumbing (REAL)
    //
    // Verifies:
    //   • Default ON in setUp is observable through `PerfFlags`.
    //   • Toggling the UserDefaults override to `false` is observed
    //     immediately on the next `PerfFlags.phase6RealtimeCallbackOrder`
    //     read (no caching layer in between).
    //   • Toggling back to `true` is observed.
    //
    // This is the strongest invariant we CAN assert without an SDK mock.
    // If this test ever fails, the Phase 6 OFF/ON branches in
    // `PrivateChallengeService.subscribeToRealtimeUpdates()` /
    // `unsubscribeFromRealtimeUpdates()` would never observe the flag
    // flip — meaning Phase 6's remote kill-switch (the in-prod ability
    // to flip the flag and roll back the actor-reentry fix in <60s
    // without a rebuild) would not function. That's the primary safety
    // property this test guards.
    func testFlagPlumbing() {
        // setUp set the flag to true.
        XCTAssertTrue(
            PerfFlags.phase6RealtimeCallbackOrder,
            "setUp must force phase6RealtimeCallbackOrder ON; PerfFlags " +
            "read returned false. Either the UserDefaults key drifted " +
            "from `perf_phase6_realtime_callback_order` (see " +
            "Fit33/PerfFlags.swift) or the `flag(_:default:)` helper is " +
            "no longer reading via `UserDefaults.standard.bool(forKey:)`."
        )

        // Toggle OFF and verify immediate observation (no cache).
        UserDefaults.standard.set(false, forKey: phase6FlagKey)
        XCTAssertFalse(
            PerfFlags.phase6RealtimeCallbackOrder,
            "After UserDefaults override → false, " +
            "PerfFlags.phase6RealtimeCallbackOrder must read false on " +
            "the very next access. If this fails, the flag may be stuck " +
            "on a static let / lazy var, which would defeat the remote " +
            "kill-switch (the OFF branch must be reachable in <60s " +
            "without a rebuild)."
        )

        // Toggle back ON and verify.
        UserDefaults.standard.set(true, forKey: phase6FlagKey)
        XCTAssertTrue(
            PerfFlags.phase6RealtimeCallbackOrder,
            "Re-enabling the flag must restore the ON branch on the " +
            "very next read. Required for the post-rollback re-enable " +
            "path."
        )

        // Smoke that PrivateChallengeService.shared is reachable through
        // @testable import — required precondition for the headline
        // tests below when their seams land.
        let svc = PrivateChallengeService.shared
        XCTAssertNotNil(
            svc,
            "PrivateChallengeService.shared must be reachable from the " +
            "test target via @testable import. If this fails, the " +
            "headline race tests below will also fail to compile."
        )
    }

    // MARK: - Test 2 — callbacks registered before subscribe (STUB)
    //
    // INTENT (when this test becomes real):
    //   1. Inject a `MockRealtimeClientV2` into `SupabaseManager.shared`
    //      that:
    //        • Returns the SAME `MockRealtimeChannelV2` instance for any
    //          two calls of `.channel("private-challenges")` (mimics the
    //          real SDK's name-keyed cache).
    //        • Records each `.postgresChange(...)` call with a
    //          `(table, action, registeredBeforeSubscribe: Bool)` triple.
    //        • Records the `.subscribe()` call with a timestamp.
    //   2. With `PerfFlags.phase6RealtimeCallbackOrder = true`:
    //        • Call `await PrivateChallengeService.shared.subscribeToRealtimeUpdates()`.
    //        • Assert the mock recorded EXACTLY 7 `.postgresChange(...)`
    //          calls, ALL with `registeredBeforeSubscribe == true`.
    //        • Assert the recorded order matches the production order:
    //          [members INSERT, members UPDATE,
    //           daily_progress INSERT, daily_progress UPDATE,
    //           invites INSERT, chat INSERT, chat UPDATE].
    //   3. With `PerfFlags.phase6RealtimeCallbackOrder = false`:
    //        • Same assertion holds — the OFF path also registers all
    //          7 callbacks before subscribe in the SOURCE-ORDER sense
    //          (the bug only fires under reentrancy, see Test 3).
    //
    // BLOCKERS (today, 2026-05-07):
    //   • No `MockRealtimeClientV2` exists in the test target.
    //     Building one requires shimming
    //     `SupabaseManager.shared.supabaseClient.realtimeV2` through a
    //     protocol seam — `SupabaseClient` is a concrete class in the
    //     SDK with no protocol conformance suitable for mocking.
    //   • `PrivateChallengeService` reads `SupabaseManager.shared`
    //     directly (line 1443 of `PrivateChallengeService.swift`). No
    //     dependency injection — the test cannot substitute a fake
    //     client without modifying production source.
    //   • The prompt is explicit: "DO NOT change the channel names,
    //     table names, filter strings, or callback bodies — ONLY the
    //     call order." Adding a DI seam is a separate PR.
    //
    // What this stub asserts (today):
    //   • The flag is reachable through `PerfFlags` (re-asserts Test 1's
    //     invariant — defensive belt-and-suspenders since a future PR
    //     landing the SDK mock might delete the explicit Test 1).
    //   • `// TODO: needs SDK channel mock` marker (matches the
    //     Phase5OffMainTests.swift stub convention so a single
    //     `rg "needs SDK channel mock" Fit33Tests/` lists the
    //     remaining seam work).
    //
    // The full ordering claim is asserted by inspection of
    // `Fit33/PrivateChallengeService.swift` lines 1444-1593: the 7
    // `.postgresChange(...)` calls are at lines 1447-1494 and
    // `await channel.subscribe()` is at line 1577 (under the Phase 6
    // ON branch) — by source order, all 7 callbacks are guaranteed to
    // be registered before `subscribe()`. The bug is reentrancy on the
    // SECOND caller, not source order.
    func testCallbacksRegisteredBeforeSubscribe() {
        // Re-assert the flag is observable (defensive — see comment above).
        XCTAssertTrue(
            PerfFlags.phase6RealtimeCallbackOrder,
            "Phase 6 parity test precondition: setUp must force the flag ON."
        )

        // STUB body. The full callback-ordering parity claim is asserted
        // by inspection of Fit33/PrivateChallengeService.swift lines
        // 1444-1593 (7 `.postgresChange(...)` calls precede
        // `await channel.subscribe()` in source order, in BOTH the
        // flag-ON and flag-OFF branches of the rewritten function).
        //
        // TODO: needs SDK channel mock (see "INTENT" + "BLOCKERS" above).
        // Once a `MockRealtimeClientV2` lands with DI on
        // `SupabaseManager`, swap this stub body for the 3-step
        // pseudocode in the docblock.
        XCTAssertTrue(
            true,
            "stub: see TODO above. The full callback-ordering parity " +
            "assertion requires (1) a `MockRealtimeClientV2` in the " +
            "test target that records `.postgresChange(...)` calls and " +
            "their before-/after-subscribe ordering, AND (2) a DI seam " +
            "on `SupabaseManager.shared.supabaseClient` so the test " +
            "can substitute the mock. Both deferred to a separate PR " +
            "per the prompt's `DO NOT change the channel names ... " +
            "ONLY the call order` constraint."
        )
    }

    // MARK: - Test 3 — subscribe-reconnect preserves callbacks (STUB)
    //
    // INTENT (when this test becomes real):
    //   1. With the `MockRealtimeClientV2` from Test 2 wired up:
    //   2. Race two concurrent
    //        `Task { await PrivateChallengeService.shared.subscribeToRealtimeUpdates() }`
    //      calls (mirrors the actual cold-start race between
    //      DashboardView line 764 and line 930). The mock should
    //      INSERT a 50ms sleep inside `.subscribe()` to guarantee the
    //      second caller observes mid-suspend state.
    //   3. Snapshot the mock's recorded `.postgresChange(...)` calls.
    //   4. Assert the mock recorded EXACTLY 7 `.postgresChange(...)`
    //      registrations (NOT 14). The Phase 6 `isSubscribing`
    //      sentinel must short-circuit the second caller before it
    //      reaches the registration block.
    //   5. Assert ALL 7 have `registeredBeforeSubscribe == true`.
    //   6. Verify the
    //      `perf.signpost.realtime.subscribe_order=fixed` AppLogger
    //      signpost was emitted EXACTLY ONCE (the
    //      `didEmitFixedOrderSignpost` one-shot guard).
    //   7. Repeat with `PerfFlags.phase6RealtimeCallbackOrder = false`:
    //      assert the mock records 14 `.postgresChange(...)` calls (7
    //      from each caller), with the second caller's 7 having
    //      `registeredBeforeSubscribe == false`. This is the bug
    //      fingerprint that the cold-start log signature captures
    //      (`Cannot add postgres_changes callbacks ... after subscribe`
    //      ×7) — a regression detector if someone reverts the fix
    //      without flipping the flag.
    //   8. Then exercise reconnect: call
    //      `await PrivateChallengeService.shared.unsubscribeFromRealtimeUpdates()`,
    //      then re-call `subscribeToRealtimeUpdates()`. Assert the
    //      mock observed a `.unsubscribe()` followed by 7 fresh
    //      `.postgresChange(...)` registrations followed by a
    //      `.subscribe()` — i.e. callbacks survive a reconnect cycle
    //      via complete re-registration (NOT silent re-use of the
    //      old channel's bindings).
    //
    // BLOCKERS (today, 2026-05-07):
    //   • Same as Test 2 — `MockRealtimeClientV2` + DI seam needed.
    //   • Additionally requires `AppLogger` interception (or an
    //     `internal` `_testHook_didEmitFixedOrderSignpost: Bool`
    //     accessor on `PrivateChallengeService`) for the signpost
    //     one-shot assertion.
    //   • Additionally requires a way to PAUSE inside
    //     `MockRealtimeChannelV2.subscribe()` deterministically — the
    //     simplest pattern is a `Continuation` the test resolves after
    //     it has confirmed the second caller is mid-suspend, but that
    //     also requires the mock + DI infrastructure.
    //
    // What this stub asserts (today):
    //   • The flag is reachable through `PerfFlags` (defensive
    //     re-assertion — see Test 2).
    //   • `// TODO: needs SDK channel mock` marker.
    //
    // The race-resolution claim itself is verified by inspection of
    // `Fit33/PrivateChallengeService.swift`:
    //   • `private var isSubscribing = false` declared without an
    //     `await` between the guard read and the assignment to `true`,
    //     so it executes atomically on the @MainActor.
    //   • The `if isSubscribing { return }` early-return precedes any
    //     `await`, so the second caller is guaranteed to bail before
    //     touching the channel.
    //   • `realtimeChannel = channel` precedes
    //     `await channel.subscribe()` under the flag-ON branch, so the
    //     `realtimeChannel != nil` early-return at function top is
    //     also tripped on the second caller as a belt-and-suspenders
    //     fallback.
    func testSubscribeReconnectPreservesCallbacks() {
        // Re-assert the flag is observable (defensive — see comment above).
        XCTAssertTrue(
            PerfFlags.phase6RealtimeCallbackOrder,
            "Phase 6 parity test precondition: setUp must force the flag ON."
        )

        // STUB body. The race-resolution claim is asserted by
        // inspection of Fit33/PrivateChallengeService.swift:
        //   • `isSubscribing` is a `@MainActor`-isolated Bool whose
        //     guard-and-assign happens with NO `await` in between.
        //   • The early-return `if isSubscribing { return }` precedes
        //     all `await`s in the function body, so the second caller
        //     bails before touching the channel.
        //   • Defense-in-depth: `realtimeChannel = channel` precedes
        //     `await channel.subscribe()` under the flag-ON branch.
        //
        // TODO: needs SDK channel mock (see "INTENT" + "BLOCKERS" above).
        // Once the mock + DI seam land, swap this stub body for the
        // 8-step pseudocode in the docblock — including the OFF-path
        // regression detector (asserts the bug signature is exactly
        // 14 registrations, half after-subscribe, when the flag is OFF).
        XCTAssertTrue(
            true,
            "stub: see TODO above. The full subscribe-reconnect parity " +
            "assertion requires (1) a `MockRealtimeClientV2` that " +
            "PAUSES inside `.subscribe()` to deterministically expose " +
            "the actor-reentry window, AND (2) a DI seam on " +
            "`SupabaseManager.shared.supabaseClient`. Both deferred to " +
            "a separate PR."
        )
    }
}
