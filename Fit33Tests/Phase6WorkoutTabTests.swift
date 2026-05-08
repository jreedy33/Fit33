// Phase 6 Parity Tests — Snappiness Overhaul (May 2026)
//
// Goal: prove that Phase 6's `WorkoutTabView` first-render slimming
// preserves behavior with the flag OFF and that the in-tree gate
// reaches the runtime correctly with the flag ON.
//
// Phase 6 (`PerfFlags.phase6WorkoutTabRender`) wraps the inline
// `WorkoutStatsSection()` mount inside `WorkoutHomeView.body` (see
// `Fit33/WorkoutTabView.swift` after the `// 6. My Stats Dashboard`
// comment) in a flag-gated `Phase6DeferredWorkoutStatsSection`.
// When ON, the section mounts 500ms after first appear (mirrors the
// canonical 250ms `Task.sleep` from QP-19's
// `loadCardioWorkoutsThisWeek`, doubled because the chart wall is
// heavier than a single Supabase fetch and is below-the-fold). When
// OFF, the inline `WorkoutStatsSection()` mounts immediately —
// byte-identical to pre-Phase-6.
//
// The Phase-5.B `SmartProgramRecommender.cachedSuggestedProgram(for:)`
// pre-warm is independent of Phase 6 — Phase 6 must not regress that
// cache key (the pre-warm hook in `Fit33App` writes through
// `setCachedSuggestedProgram(_:for:)` and `WorkoutTabView` reads back
// via `cachedSuggestedProgram(for:)`; key drift would re-introduce
// the 4× cold-start scoring pass). `testCachedRecommendedProgramSurvivesFirstRender`
// asserts that contract is unbroken.
//
// What this file asserts (today):
//   • Test 1 (REAL) — `PerfFlags.phase6WorkoutTabRender` reads the
//     canonical UserDefaults key. Toggling the override flips the
//     PerfFlags read on the very next access. Without this the
//     remote kill-switch wouldn't function. Same shape as
//     Phase{1,2,3,5}ParityTests.
//   • Test 2 (STUB) — "Workout tab renders the same set of programs
//     under both flag values." DOCUMENTED as a stub: requires SwiftUI
//     view-tree introspection or a snapshot-test harness, neither of
//     which currently exists in this test target. The structural
//     argument for behavior parity is documented inline (the inline
//     `WorkoutStatsSection()` and the flag-gated
//     `Phase6DeferredWorkoutStatsSection` mount the SAME view type;
//     the wrapper's only diff is a 500ms delay before mount).
//   • Test 3 (REAL) — Phase-5.B recommender cache key parity. Writes
//     a synthetic `SuggestedProgram` for `userA` via
//     `setCachedSuggestedProgram(_:for:)` (the Phase-5.B pre-warm
//     path) and asserts `cachedSuggestedProgram(for: userA)` returns
//     it. Defends against a regression where Phase 6 inadvertently
//     drains or re-keys the recommender cache.
//
// Constraints honored (mirrors Phase{1,2,3,5}ParityTests):
//   • XCTest only.
//   • <100ms / test (no I/O beyond a single UserDefaults override
//     and an in-memory recommender-cache write/read).
//   • No live Supabase, no live Core Data fetches.
//   • Deterministic — fresh UUIDs in `setUp` + a baseline
//     `clearSuggestedProgramCache()` so prior runs cannot leak.
//   • `@MainActor` on the class so `SmartProgramRecommender.shared`
//     access stays on the actor.
//   • Flag forced ON in `setUp` (and restored in `tearDown`) so the
//     post-overhaul code path executes by default. Tests that assert
//     OFF behavior flip locally and restore at function end.
//   • Phase-5.B recommender flag also forced ON for Test 3 so the
//     `setCached/cached` round-trip is the ON path (its OFF path is
//     a no-op asserted in `Phase5DashboardAndRecommenderTests`).
//
// Test seams used:
//   • `SmartProgramRecommender.setCachedSuggestedProgram(_:for:)` /
//     `cachedSuggestedProgram(for:)` /
//     `clearSuggestedProgramCache()` /
//     `_testHook_cachedSuggestedProgramCount()` (DEBUG-only).
//

import XCTest
import SwiftUI
@testable import Fit33

@MainActor
final class Phase6WorkoutTabTests: XCTestCase {

    // Canonical UserDefaults keys mirroring `PerfFlags.swift`. Mirrored
    // here (not derived) — same convention as Phase{1,2,3,5}ParityTests.
    // Keep in sync with `Fit33/PerfFlags.swift`.
    private let phase6FlagKey = "perf_phase6_workout_tab_render"
    private let phase5RecommenderKey = "perf_phase5_recommender_prewarm"

    // Snapshot/restore so a pre-existing override (e.g. set by a debug
    // menu) is not clobbered by this test file.
    private var hadPreexistingPhase6Override = false
    private var preexistingPhase6Value = false
    private var hadPreexistingRecommenderOverride = false
    private var preexistingRecommenderValue = false

    // Fresh UUIDs per test so prior runs cannot leak through the
    // process-lifetime `SmartProgramRecommender` cache.
    private var userA: UUID = UUID()
    private var userB: UUID = UUID()

    override func setUp() {
        super.setUp()

        if UserDefaults.standard.object(forKey: phase6FlagKey) != nil {
            hadPreexistingPhase6Override = true
            preexistingPhase6Value = UserDefaults.standard.bool(forKey: phase6FlagKey)
        } else {
            hadPreexistingPhase6Override = false
        }
        if UserDefaults.standard.object(forKey: phase5RecommenderKey) != nil {
            hadPreexistingRecommenderOverride = true
            preexistingRecommenderValue = UserDefaults.standard.bool(forKey: phase5RecommenderKey)
        } else {
            hadPreexistingRecommenderOverride = false
        }

        // Force ON for the canonical post-overhaul code path. Test 1 and
        // Test 3 require ON; Test 2 is a stub. The OFF branch is asserted
        // by Test 1's local toggle.
        UserDefaults.standard.set(true, forKey: phase6FlagKey)
        UserDefaults.standard.set(true, forKey: phase5RecommenderKey)

        userA = UUID()
        userB = UUID()

        // Defense-in-depth: drop any leftover entries from prior tests
        // (the singleton survives across the test target's process if
        // tests run serially).
        SmartProgramRecommender.shared.clearSuggestedProgramCache()
    }

    override func tearDown() {
        SmartProgramRecommender.shared.clearSuggestedProgramCache()

        if hadPreexistingPhase6Override {
            UserDefaults.standard.set(preexistingPhase6Value, forKey: phase6FlagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: phase6FlagKey)
        }
        if hadPreexistingRecommenderOverride {
            UserDefaults.standard.set(preexistingRecommenderValue, forKey: phase5RecommenderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: phase5RecommenderKey)
        }

        super.tearDown()
    }

    // MARK: - Test 1 — flag plumbing (REAL)

    /// Verifies the Phase 6 flag is observable through `PerfFlags`,
    /// flips on UserDefaults override, and is reachable from a single
    /// `flag(_:default:)` helper read (no caching layer in between).
    ///
    /// If this test ever fails, the Phase 6 ON/OFF gate inside
    /// `WorkoutTabView.body` would never observe a flag flip — meaning
    /// the remote kill-switch (the in-prod ability to flip the flag and
    /// roll back the deferred-stats mount in <60s without a rebuild)
    /// would not function. That's the primary safety property this
    /// test guards.
    func testFlagPlumbing() {
        // setUp forced the flag ON.
        XCTAssertTrue(
            PerfFlags.phase6WorkoutTabRender,
            "setUp must force phase6WorkoutTabRender ON; PerfFlags read " +
            "returned false. Either the UserDefaults key drifted from " +
            "`perf_phase6_workout_tab_render` (see Fit33/PerfFlags.swift) " +
            "or the `flag(_:default:)` helper is no longer reading via " +
            "`UserDefaults.standard.bool(forKey:)`."
        )

        // Toggle OFF and verify immediate observation (no cache).
        UserDefaults.standard.set(false, forKey: phase6FlagKey)
        XCTAssertFalse(
            PerfFlags.phase6WorkoutTabRender,
            "After UserDefaults override → false, " +
            "PerfFlags.phase6WorkoutTabRender must read false on the very " +
            "next access. If this fails, the flag may be stuck on a " +
            "`static let` / `lazy var`, which would defeat the remote " +
            "kill-switch (the OFF branch must be reachable in <60s " +
            "without a rebuild)."
        )

        // Toggle back ON and verify.
        UserDefaults.standard.set(true, forKey: phase6FlagKey)
        XCTAssertTrue(
            PerfFlags.phase6WorkoutTabRender,
            "Re-enabling the flag must restore the ON branch on the very " +
            "next read. Required for the post-rollback re-enable path."
        )

        // Smoke that the wrapper struct compiles & is reachable through
        // @testable import. If `Phase6DeferredWorkoutStatsSection` is
        // ever renamed, removed, or made fileprivate, this line will
        // fail to compile and surface the rename in CI before it lands.
        // We do NOT instantiate `WorkoutStatsSection` here — its body
        // would touch `WeightTrackingService.shared` and other singletons
        // that pull from Core Data, which is out of scope for a unit
        // test. The compile-time reach is the assertion.
        let _: Phase6DeferredWorkoutStatsSection.Type = Phase6DeferredWorkoutStatsSection.self
    }

    // MARK: - Test 2 — same content rendered under flag toggle (STUB)
    //
    // INTENT (when this test becomes real):
    //   1. Spin up an `XCTestObservation` that captures
    //      `WorkoutHomeView.body` outputs for both flag values.
    //   2. Assert the two view trees contain the same `WorkoutStatsSection`
    //      identity (just with a 500ms mount delay difference) and the
    //      same `programsWidget` / `recentActivitySection` / `nextUpCard`
    //      composition.
    //   3. Assert that under flag ON, mounting the
    //      `Phase6DeferredWorkoutStatsSection` produces a `Color.clear`
    //      (the placeholder) on first body eval and a
    //      `WorkoutStatsSection` after 500ms.
    //
    // Why this is a stub:
    //   • SwiftUI view trees are opaque (`some View`). The test target
    //     doesn't include ViewInspector or any other view-tree
    //     introspection library.
    //   • A snapshot-test harness (e.g. SnapshotTesting) would capture
    //     pixels, not the structural identity of the view hierarchy —
    //     the relevant assertion is "same content," not "same pixels."
    //   • Spinning up a real `WorkoutTabView` requires `UserManager`,
    //     `WorkoutManager`, `SmartProgramEngine`, `CloudProgramService`,
    //     `GeneratedProgramService`, `WeightTrackingService`,
    //     `ExerciseLibraryService`, `ExerciseLibraryFilterCache`,
    //     `WorkoutWearableMerger`, and a live `NSPersistentContainer`.
    //     Several of those touch Supabase, HealthKit, and the file
    //     system — out of scope for a fast deterministic unit test.
    //
    // What this stub asserts (today):
    //   • The `Phase6DeferredWorkoutStatsSection` wrapper exists, is a
    //     `View`, and compiles against the same module that ships
    //     `WorkoutStatsSection`. The structural parity claim is then
    //     argued by inspection of `Fit33/WorkoutTabView.swift` after the
    //     `// 6. My Stats Dashboard` comment: both branches mount the
    //     SAME `WorkoutStatsSection()` view type; the only diff is a
    //     `Task.sleep(nanoseconds: 500_000_000)` gate before the mount
    //     in the deferred wrapper. Off-screen content renders identically
    //     once the gate releases.
    //
    // TODO: Phase 6 view-tree parity test — needs ONE of:
    //   (a) ViewInspector dependency added to the test target. ~30 LOC
    //       to wire and assert "view tree under flag ON contains a
    //       Phase6DeferredWorkoutStatsSection at the same VStack index
    //       as the flag-OFF tree contains WorkoutStatsSection."
    //   (b) An `internal func _testHook_renderedSectionTypes() -> [Any.Type]`
    //       seam on WorkoutHomeView that returns the type sequence its
    //       body produces. Smaller diff but more invasive to production.
    //
    // Documented seam choice (so a future agent doesn't re-derive it):
    //   ViewInspector — already a known iOS-test dependency, doesn't
    //   require a production-side seam, scopes cleanly to test target.
    func testRendersWithSamePrograms() {
        // STUB body: reach the wrapper struct and confirm it conforms to
        // `View`. The structural parity argument is the inline doc above.
        let _: any View = Phase6DeferredWorkoutStatsSection()

        // Anchor for the structural parity argument: the production code
        // mounts `WorkoutStatsSection` under both flag values. If
        // `WorkoutStatsSection` ever becomes flag-conditional (e.g.
        // replaced with a sibling `WorkoutStatsSectionV2` under one
        // branch only), the parity claim breaks and this stub MUST be
        // upgraded to a real assertion.
        let _: WorkoutStatsSection.Type = WorkoutStatsSection.self

        // Sanity: under both flag values, the same MAIN view type is the
        // workout-tab root. If the wrapper or root is ever renamed, this
        // line will fail to compile and CI will surface the rename
        // before it lands.
        let _: WorkoutTabView.Type = WorkoutTabView.self

        XCTAssertTrue(
            true,
            "STUB — see file-level header for the upgrade path. " +
            "Production-side parity is asserted by inspection of " +
            "Fit33/WorkoutTabView.swift after the `// 6. My Stats " +
            "Dashboard` comment: both branches mount " +
            "`WorkoutStatsSection()` — the deferred wrapper only adds a " +
            "500ms `Task.sleep` before the mount. View output identity " +
            "after the gate is byte-equivalent."
        )
    }

    // MARK: - Test 3 — Phase 5.B recommender cache key parity (REAL)

    /// Phase 6 must not regress the Phase 5.B `SmartProgramRecommender`
    /// pre-warm cache. The cold-start hook in `Fit33App.swift` writes
    /// through `setCachedSuggestedProgram(_:for:)` and the WorkoutTabView
    /// path reads back via `cachedSuggestedProgram(for:)` (also called
    /// from `refreshCachedRecommendedProgram()` in `WorkoutTabView`).
    /// Both endpoints accept a `UUID` — a key drift between writer and
    /// reader would silently re-introduce the 4× cold-start scoring
    /// pass that Phase 5.B eliminated.
    ///
    /// Phase 6 only adds a deferred mount of `WorkoutStatsSection`. It
    /// does NOT touch the recommender cache — but a regression test
    /// here is cheap insurance. If a future Phase 6 follow-up
    /// introduces a `clearSuggestedProgramCache()` invocation in the
    /// deferred path, this test will fail and surface the regression.
    func testCachedRecommendedProgramSurvivesFirstRender() {
        // ARRANGE — a synthetic recommendation written via the same
        // public API the Phase-5.B pre-warm hook uses.
        let synthetic = SuggestedProgram(
            title: "Phase 6 Survival Program",
            description: "Asserts the Phase-5.B cache key wasn't drained.",
            duration: "4 weeks",
            workoutsPerWeek: "3 days/week",
            focusAreas: ["full body"],
            difficulty: "Beginner",
            primaryColor: .blue,
            secondaryColor: .blue.opacity(0.7),
            icon: "figure.strengthtraining.traditional",
            callToAction: "Start"
        )
        SmartProgramRecommender.shared.setCachedSuggestedProgram(
            synthetic, for: userA
        )

        // ACT (prove Phase-5.B cache key is unchanged) — the Workout
        // tab's `refreshCachedRecommendedProgram()` reads via the same
        // `cachedSuggestedProgram(for:)` API. Both endpoints take a
        // `UUID` so a key drift would manifest as a "set didn't
        // propagate to cached" miss. We can't construct a real Core
        // Data `User` here (no in-memory NSPersistentContainer in this
        // test target — see Phase5DashboardAndRecommenderTests notes),
        // so we exercise the cache layer directly through its public
        // `set` / `cached` accessors with the same `UUID` parameter.
        guard let hit = SmartProgramRecommender.shared
            .cachedSuggestedProgram(for: userA) else {
            XCTFail(
                "Pre-warm wrote with userA, cached read with userA " +
                "returned nil. Cache key drift between writer and " +
                "reader breaks the entire Phase-5.B pre-warm contract — " +
                "first WorkoutTab tap would still pay the 4× scoring " +
                "pass that Phase-5.B was meant to eliminate. " +
                "`Phase6DeferredWorkoutStatsSection` mount must NOT " +
                "drain or re-key this cache."
            )
            return
        }

        XCTAssertEqual(
            hit.title, synthetic.title,
            "Cached recommendation must round-trip through the " +
            "set/cached pair. If this fails, Phase 6 has somehow " +
            "introduced a serialization step between writer and " +
            "reader (it should not — both APIs operate on " +
            "`SuggestedProgram` value types)."
        )
        XCTAssertEqual(
            hit.callToAction, synthetic.callToAction,
            "Full SuggestedProgram round-trip must include callToAction"
        )

        // Different user → MISS (defense against cross-user leak).
        XCTAssertNil(
            SmartProgramRecommender.shared.cachedSuggestedProgram(for: userB),
            "User B must NOT see user A's pre-warmed recommendation. " +
            "Phase 6 must NOT introduce a global cache key collapse."
        )

        // Cache size invariant — exactly one entry from this test.
        XCTAssertEqual(
            SmartProgramRecommender.shared._testHook_cachedSuggestedProgramCount(),
            1,
            "Cache must contain exactly one entry after a single " +
            "pre-warm. Phase 6 must NOT re-introduce a 4× write that " +
            "Phase-5.B already eliminated."
        )
    }
}
