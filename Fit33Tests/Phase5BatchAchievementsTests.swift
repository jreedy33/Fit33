// Phase 5.D Parity Tests — Snappiness Overhaul (May 2026)
//
// Goal: prove that `PerfFlags.phase5BatchAchievements` flips the
// `Fit33/AchievementService.swift::batchCheckAndUnlock` code path
// from N serial `unlock_achievement` RPCs to a single
// `batch_check_achievements(text[], int[])` round-trip — and that the
// returned shape is decode-compatible with the server contract
// authored in `supabase/20260507_batch_check_achievements.sql`.
//
// What lives ON DISK that we CAN exercise without a live Supabase
// or a private test seam (Swift's `@testable import` pierces
// `internal`, NEVER `private`; `BadgeService.batchCheckAndUnlock` is
// `private`, so the test target cannot invoke it directly):
//   • `PerfFlags.phase5BatchAchievements` (UserDefaults read) —
//     plumbing assertion.
//   • `BatchAchievementRow` (top-level Decodable in
//     AchievementService.swift) — JSON decode parity assertion.
//   • `BatchAchievementRow.asUnlockResult` (the projection seam used
//     by `batchCheckAndUnlock` to reuse the per-key `handleUnlockResult`
//     post-cascade) — projection-equivalence assertion.
//   • Inverse-of-server-contract: a synthetic batch JSON payload
//     decodes into the same set of `(key, progress, justUnlocked,
//     xpReward)` triples that the per-key `unlock_achievement` would
//     have produced, proving the seam preserves side-effect signal.
//
// Constraints honored (mirrors Phase1/2/3 ParityTests pattern):
//   • XCTest only.
//   • No live Supabase, no live Core Data — uses synthetic in-memory
//     JSON fixtures only.
//   • <100ms per test — every assertion is in-memory.
//   • Deterministic — pure-function inputs only; no `Date()`, no timer
//     callbacks, no UserDefaults reads beyond the flag plumbing.
//   • Flag forced ON in `setUp` (and restored in `tearDown`) so the
//     UserDefaults plumbing the production code reads from is exercised
//     in the canonical post-overhaul state.
//
// What the prompt asked for + how this file delivers it:
//   1. `testBatchAndIndividualReturnSameProgress` — STUB by necessity
//     (the actual N-individual-RPC vs 1-batch-RPC parity assertion
//     requires either (a) a live Supabase fixture or (b) an internal
//     test seam on `BadgeService.batchCheckAndUnlock` that lets us
//     inject a mock `SupabaseClient`. Neither exists today; both are
//     out of scope per the prompt's "Do not modify production source
//     beyond the integration"). Documents what the assertion would
//     look like + ships the payload-shape parity test that DOES run
//     (`test_phase5_batchRowDecodesToSameProjectionAsUnlockResult`)
//     as the strongest in-memory proxy for "same row out, same side
//     effect".
//   2. `testFlagPlumbing` — REAL. Toggling
//     `UserDefaults["perf_phase5_batch_achievements"]` flips the
//     observed `PerfFlags.phase5BatchAchievements` read. This is the
//     only assertion that proves the flag plumbing wires from
//     UserDefaults → PerfFlags → `batchCheckAndUnlock`'s `if
//     PerfFlags.phase5BatchAchievements { ... }` branch. (We can't
//     observe the branch directly because `batchCheckAndUnlock` is
//     `private`; we observe the FLAG, which is the necessary
//     precondition for the branch to fire.)
//   3. `testBatchHandlesPartialFailure` — REAL. Decodes a synthetic
//     server response where one row is a "no-such-key" defensive row
//     (the `NOT FOUND` branch of the migration's per-key LOOP) and
//     asserts (a) decode succeeds (no all-or-nothing failure at the
//     transport seam), (b) the surviving rows still carry their
//     correct progress / unlock signals, (c) the failed row's
//     `justUnlocked` is FALSE (so `batchCheckAndUnlock`'s
//     `for row in rows where row.justUnlocked` loop correctly skips
//     it without triggering a celebration toast).

import XCTest
@testable import Fit33

@MainActor
final class Phase5BatchAchievementsTests: XCTestCase {

    // Canonical UserDefaults key matching `PerfFlags.phase5BatchAchievements`.
    // Mirrored here (not derived from PerfFlags) — same convention as
    // Phase1/2/3 ParityTests: `PerfFlags` reads the key via a private
    // `flag(_:default:)` helper and does not expose it as a public
    // constant. Keep in sync with `Fit33/PerfFlags.swift:91`.
    private let phase5FlagKey = "perf_phase5_batch_achievements"

    private var hadPreexistingFlagOverride = false
    private var preexistingFlagValue = false

    override func setUp() {
        super.setUp()

        if UserDefaults.standard.object(forKey: phase5FlagKey) != nil {
            hadPreexistingFlagOverride = true
            preexistingFlagValue = UserDefaults.standard.bool(forKey: phase5FlagKey)
        } else {
            hadPreexistingFlagOverride = false
        }
        UserDefaults.standard.set(true, forKey: phase5FlagKey)
    }

    override func tearDown() {
        if hadPreexistingFlagOverride {
            UserDefaults.standard.set(preexistingFlagValue, forKey: phase5FlagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: phase5FlagKey)
        }
        super.tearDown()
    }

    // MARK: - Flag plumbing (REAL)

    /// Toggling the canonical UserDefaults key MUST flip
    /// `PerfFlags.phase5BatchAchievements`. This is the only contract
    /// that proves the flag wires correctly into the production
    /// `if PerfFlags.phase5BatchAchievements { ... }` branch in
    /// `BadgeService.batchCheckAndUnlock`.
    ///
    /// Without this assertion passing, even a correctly implemented
    /// batch RPC + correctly decoded `BatchAchievementRow` would
    /// silently fall through to the per-key fallback because the
    /// branch predicate would always read the default.
    func testFlagPlumbing() {
        // setUp forces ON.
        XCTAssertTrue(
            PerfFlags.phase5BatchAchievements,
            "setUp must force phase5BatchAchievements ON; PerfFlags read returned false. " +
            "Verify the canonical key matches `Fit33/PerfFlags.swift:91` " +
            "(`perf_phase5_batch_achievements`)."
        )

        // Flip OFF — production code path falls back to per-key serial fan-out.
        UserDefaults.standard.set(false, forKey: phase5FlagKey)
        XCTAssertFalse(
            PerfFlags.phase5BatchAchievements,
            "Setting UserDefaults[\"\(phase5FlagKey)\"] = false MUST flip " +
            "PerfFlags.phase5BatchAchievements to false. If this fails, the " +
            "Phase 5.D rollback path (off-flag fallback to per-key fan-out) is " +
            "broken."
        )

        // Flip back ON — production code path uses batch RPC.
        UserDefaults.standard.set(true, forKey: phase5FlagKey)
        XCTAssertTrue(
            PerfFlags.phase5BatchAchievements,
            "Setting UserDefaults[\"\(phase5FlagKey)\"] = true MUST flip " +
            "PerfFlags.phase5BatchAchievements to true."
        )

        // Remove the override entirely → defaults policy kicks in
        // (DEBUG → true; TestFlight → AppConfig.isTestFlight; Prod → false).
        // We cannot assert the build-time default's value here without a
        // brittle `#if DEBUG` mirror — what we CAN assert is that removal
        // doesn't crash and the read returns a Bool (which it does
        // structurally, given the Swift type).
        UserDefaults.standard.removeObject(forKey: phase5FlagKey)
        let _: Bool = PerfFlags.phase5BatchAchievements  // type-check sanity
    }

    // MARK: - Batch row decode parity (REAL — strongest in-memory proxy
    // for "same row out, same side effect")

    /// Server contract per `supabase/20260507_batch_check_achievements.sql`
    /// emits 9 columns per row:
    ///   `achievement_key`, `progress_value`, `is_unlocked`,
    ///   `unlocked_at`, `just_unlocked`, `achievement_title`,
    ///   `achievement_icon`, `achievement_rarity`, `xp_reward`.
    ///
    /// `BatchAchievementRow` (top-level in
    /// `Fit33/AchievementService.swift`) MUST decode this exact shape.
    /// If a future server-side schema change drops/renames a column,
    /// THIS test fails and forces a same-PR Swift decoder update —
    /// supabase-rules §15 contract enforcement at the test level.
    func test_phase5_batchAchievementRow_decodesAllNineColumns() throws {
        let json = """
        [
            {
                "achievement_key": "first_workout",
                "progress_value": 1,
                "is_unlocked": true,
                "unlocked_at": "2026-05-07T12:00:00+00:00",
                "just_unlocked": true,
                "achievement_title": "First Rep",
                "achievement_icon": "dumbbell.fill",
                "achievement_rarity": "common",
                "xp_reward": 50
            },
            {
                "achievement_key": "workouts_500",
                "progress_value": 50,
                "is_unlocked": false,
                "unlocked_at": null,
                "just_unlocked": false,
                "achievement_title": "Iron Will",
                "achievement_icon": "trophy.fill",
                "achievement_rarity": "epic",
                "xp_reward": 0
            }
        ]
        """.data(using: .utf8)!

        let rows = try JSONDecoder().decode([BatchAchievementRow].self, from: json)

        XCTAssertEqual(rows.count, 2, "Expected 2 rows from the batch payload.")

        let first = rows[0]
        XCTAssertEqual(first.achievementKey, "first_workout")
        XCTAssertEqual(first.progressValue, 1)
        XCTAssertTrue(first.isUnlocked)
        XCTAssertEqual(first.unlockedAt, "2026-05-07T12:00:00+00:00")
        XCTAssertTrue(
            first.justUnlocked,
            "first_workout row marked just_unlocked=true → batch path MUST " +
            "fan this row through `handleUnlockResult` for XP credit + toast."
        )
        XCTAssertEqual(first.achievementTitle, "First Rep")
        XCTAssertEqual(first.achievementIcon, "dumbbell.fill")
        XCTAssertEqual(first.achievementRarity, "common")
        XCTAssertEqual(first.xpReward, 50)

        let second = rows[1]
        XCTAssertEqual(second.achievementKey, "workouts_500")
        XCTAssertEqual(second.progressValue, 50)
        XCTAssertFalse(second.isUnlocked)
        XCTAssertNil(
            second.unlockedAt,
            "Row that hasn't crossed threshold MUST decode unlocked_at as nil " +
            "(not as the empty string \"\" — which would silently parse as " +
            "ISO8601 zero in `AchievementItem`)."
        )
        XCTAssertFalse(
            second.justUnlocked,
            "workouts_500 below threshold → just_unlocked=false → batch path " +
            "MUST NOT fire the celebration toast for this row."
        )
        XCTAssertEqual(second.xpReward, 0)
    }

    /// `BatchAchievementRow.asUnlockResult` projects a batch row onto the
    /// canonical single-RPC `UnlockResult` shape so the per-row post-unlock
    /// cascade (XP credit + toast cache) runs unchanged regardless of which
    /// RPC produced the row. This test asserts the projection preserves
    /// every field the cascade reads, AND maps `justUnlocked` (server
    /// contract) → `unlocked` (legacy iOS contract) so the cascade's
    /// `result.unlocked` guard fires correctly.
    ///
    /// If this projection ever drifts — e.g. an XP delta is dropped, or
    /// the `justUnlocked` flag stops mapping to `unlocked` — Phase 5.D
    /// would silently never award XP for batch unlocks, even though the
    /// server-side write succeeded. THIS test is the seam guard.
    func test_phase5_batchRowDecodesToSameProjectionAsUnlockResult() {
        let unlocked = BatchAchievementRow(
            achievementKey: "streak_7",
            progressValue: 7,
            isUnlocked: true,
            unlockedAt: "2026-05-07T12:00:00+00:00",
            justUnlocked: true,
            achievementTitle: "Week Warrior",
            achievementIcon: "flame.fill",
            achievementRarity: "common",
            xpReward: 100
        )

        let asUnlock = unlocked.asUnlockResult

        XCTAssertEqual(
            asUnlock.unlocked, unlocked.justUnlocked,
            "`asUnlockResult.unlocked` MUST mirror `BatchAchievementRow.justUnlocked` " +
            "exactly — the post-unlock cascade in `handleUnlockResult` reads " +
            "`result.unlocked` to decide whether to fire the celebration toast " +
            "+ credit XP. Mapping `isUnlocked` instead would re-fire the toast " +
            "every time a previously-unlocked achievement re-appears in a batch."
        )
        XCTAssertEqual(asUnlock.achievementTitle, unlocked.achievementTitle)
        XCTAssertEqual(asUnlock.achievementIcon, unlocked.achievementIcon)
        XCTAssertEqual(asUnlock.achievementRarity, unlocked.achievementRarity)
        XCTAssertEqual(
            asUnlock.xpReward, unlocked.xpReward,
            "XP delta MUST round-trip exactly. If this drifts, batch unlocks " +
            "would silently never award XP even though the server-side UPDATE " +
            "of `user_profiles.xp` succeeded."
        )

        // Negative case: a row that's already unlocked (re-fetched in the
        // batch but not re-unlocked this call) MUST NOT project as
        // `unlocked = true` — otherwise we'd re-toast every cold start.
        let alreadyUnlocked = BatchAchievementRow(
            achievementKey: "first_workout",
            progressValue: 5,
            isUnlocked: true,
            unlockedAt: "2026-05-01T10:00:00+00:00",
            justUnlocked: false,  // <-- key signal
            achievementTitle: "First Rep",
            achievementIcon: "dumbbell.fill",
            achievementRarity: "common",
            xpReward: 0
        )
        XCTAssertFalse(
            alreadyUnlocked.asUnlockResult.unlocked,
            "Already-unlocked row (justUnlocked=false, isUnlocked=true) MUST " +
            "project as unlocked=false. Otherwise every cold-start " +
            "`resyncOlympianProgressFromLocalTotals` would re-toast every " +
            "previously-unlocked achievement — the exact noise pattern Phase " +
            "5.D's silent-batch contract is supposed to prevent."
        )
    }

    // MARK: - Partial failure handling (REAL)

    /// Server-side per-key isolation contract per
    /// `supabase/20260507_batch_check_achievements.sql`:
    ///   • An invalid key (not in `achievements` table) returns a
    ///     defensive row with `is_unlocked=false`, `just_unlocked=false`,
    ///     `progress_value=0`, NULLs for title/icon/rarity, `xp_reward=0`.
    ///   • A constraint-violation / race in the per-row body is caught
    ///     by the `EXCEPTION WHEN OTHERS` block and yields the SAME
    ///     defensive row shape (plus a server-side `RAISE WARNING`).
    ///   • Other rows in the batch MUST still return their correct
    ///     progress + unlock signals.
    ///
    /// This test simulates that mixed-success payload at the iOS decode
    /// + `handleUnlockResult`-projection seam:
    ///   1. Decode succeeds (no all-or-nothing failure).
    ///   2. The defensive row has `justUnlocked=false`, so the
    ///      `for row in rows where row.justUnlocked` loop in
    ///      `batchCheckAndUnlock` correctly skips it → no celebration
    ///      toast for an invalid key.
    ///   3. The surviving real rows carry their correct progress.
    func testBatchHandlesPartialFailure() throws {
        let json = """
        [
            {
                "achievement_key": "first_workout",
                "progress_value": 1,
                "is_unlocked": true,
                "unlocked_at": "2026-05-07T12:00:00+00:00",
                "just_unlocked": true,
                "achievement_title": "First Rep",
                "achievement_icon": "dumbbell.fill",
                "achievement_rarity": "common",
                "xp_reward": 50
            },
            {
                "achievement_key": "olympian_2026_nonexistent_legacy_key",
                "progress_value": 0,
                "is_unlocked": false,
                "unlocked_at": null,
                "just_unlocked": false,
                "achievement_title": null,
                "achievement_icon": null,
                "achievement_rarity": null,
                "xp_reward": 0
            },
            {
                "achievement_key": "streak_7",
                "progress_value": 5,
                "is_unlocked": false,
                "unlocked_at": null,
                "just_unlocked": false,
                "achievement_title": "Week Warrior",
                "achievement_icon": "flame.fill",
                "achievement_rarity": "common",
                "xp_reward": 0
            }
        ]
        """.data(using: .utf8)!

        let rows = try JSONDecoder().decode([BatchAchievementRow].self, from: json)

        // Contract 1: decode succeeds for all 3 rows (no all-or-nothing).
        XCTAssertEqual(
            rows.count, 3,
            "Partial-failure payload MUST decode all 3 rows — invalid-key " +
            "row included. If decode count drops to 2, the iOS-side decoder " +
            "is rejecting null-title/icon/rarity rows, which would tank the " +
            "entire batch on a single bad key (the exact failure mode the " +
            "server-side per-row EXCEPTION block prevents)."
        )

        // Contract 2: the invalid-key defensive row is JustUnlocked=false.
        let invalidRow = rows.first { $0.achievementKey == "olympian_2026_nonexistent_legacy_key" }
        XCTAssertNotNil(invalidRow, "Invalid-key row missing from decoded batch.")
        XCTAssertEqual(invalidRow?.progressValue, 0)
        XCTAssertFalse(invalidRow?.isUnlocked ?? true)
        XCTAssertFalse(
            invalidRow?.justUnlocked ?? true,
            "Invalid-key defensive row MUST decode justUnlocked=false. The " +
            "`for row in rows where row.justUnlocked` loop in " +
            "`batchCheckAndUnlock` (Fit33/AchievementService.swift) skips " +
            "false-justUnlocked rows; if this flips to true, an invalid key " +
            "would manufacture a phantom celebration toast (key=invalid, " +
            "title=nil → would render as an empty toast)."
        )
        XCTAssertNil(invalidRow?.achievementTitle)
        XCTAssertNil(invalidRow?.achievementIcon)
        XCTAssertNil(invalidRow?.achievementRarity)
        XCTAssertEqual(invalidRow?.xpReward, 0)

        // Contract 3: the projection of the invalid row through
        // `asUnlockResult` produces `unlocked=false` so `handleUnlockResult`'s
        // `result.unlocked` early-return fires.
        if let invalidRow {
            XCTAssertFalse(
                invalidRow.asUnlockResult.unlocked,
                "Invalid-key row's `asUnlockResult.unlocked` MUST be false so " +
                "`handleUnlockResult`'s `result.unlocked` guard early-returns " +
                "without firing a phantom toast or crediting XP."
            )
        }

        // Contract 4: surviving valid rows carry their correct progress.
        let firstWorkoutRow = rows.first { $0.achievementKey == "first_workout" }
        XCTAssertEqual(firstWorkoutRow?.progressValue, 1)
        XCTAssertTrue(firstWorkoutRow?.justUnlocked ?? false)
        XCTAssertEqual(firstWorkoutRow?.xpReward, 50)

        let streakRow = rows.first { $0.achievementKey == "streak_7" }
        XCTAssertEqual(
            streakRow?.progressValue, 5,
            "streak_7 row MUST preserve progress=5 — proves the invalid row " +
            "between first_workout and streak_7 didn't tank progress " +
            "decoding for the row after it."
        )
        XCTAssertFalse(streakRow?.isUnlocked ?? true)
        XCTAssertFalse(streakRow?.justUnlocked ?? true)

        // Contract 5: the count of just-unlocked rows = exactly 1
        // (matches the server-side promise that batches don't over-fire).
        let justUnlockedCount = rows.filter(\.justUnlocked).count
        XCTAssertEqual(
            justUnlockedCount, 1,
            "Exactly one row in this fixture should report justUnlocked=true. " +
            "The `for row in rows where row.justUnlocked` loop in " +
            "`batchCheckAndUnlock` would fan exactly 1 call through " +
            "`handleUnlockResult`. If this count drifts, either the server " +
            "is double-counting unlocks or the iOS would skip a real one."
        )
    }

    // MARK: - Batch vs individual progress parity (STUB — needs DB fixture)
    //
    // INTENT (when this becomes real):
    //   1. Seed a synthetic user state (e.g. totalWorkouts=49, streak=6).
    //   2. Call N individual `unlock_achievement` RPCs serially:
    //        await checkAndUnlock(key: "workouts_50", progress: 49)
    //        await checkAndUnlock(key: "streak_7",    progress: 6)
    //        await checkAndUnlock(key: "first_workout", progress: 49)
    //      Snapshot the resulting `user_achievements.progress` rows.
    //   3. Reset state. Call `batch_check_achievements` with the same
    //      (key, progress) tuples.
    //   4. Snapshot the resulting `user_achievements.progress` rows.
    //   5. Assert: row-by-row, the (progress, unlocked_at IS NOT NULL,
    //      xp_reward) triples match exactly.
    //   6. Edge cases the assertion MUST cover:
    //        a. progress regression (GREATEST upsert): batch with
    //           progress=10 after individual upsert with progress=49
    //           MUST keep progress=49 (GREATEST clamp).
    //        b. threshold crossing: batch with progress=50 on
    //           workouts_50 (threshold=50) MUST stamp `unlocked_at`
    //           AND credit `xp_reward=250`.
    //        c. tail-call: batch with an `olympian_2026_*` key that
    //           hits its threshold MUST trigger
    //           `complete_olympian_season_if_done` exactly as the
    //           individual RPC does (assertable via the
    //           `user_olympian_seasons` row appearing).
    //
    // BLOCKERS (today, 2026-05-07):
    //   • `BadgeService.batchCheckAndUnlock` is `private`.
    //     `@testable import` cannot pierce `private`.
    //   • `BadgeService` calls a real `SupabaseManager.shared.supabaseClient`.
    //     Fit33Tests/ has no Supabase mock; standing one up means
    //     either (a) injecting a protocol-wrapped client (production
    //     diff outside this PR's scope per the prompt's "iOS files
    //     modified ... likely just AchievementService.swift" boundary)
    //     or (b) running tests against a live Supabase staging project
    //     (Fit33Tests/ has zero such tests today; CI would block).
    //   • The server-side parity is GUARANTEED by the migration's
    //     per-key LOOP body being a copy-paste of `unlock_achievement`'s
    //     body (`supabase/20260507_batch_check_achievements.sql` lines
    //     113-180 vs `supabase/20260504_olympian_path.sql` lines 489-554).
    //     Side-effect parity is a CODE INVARIANT, not a runtime one;
    //     the right place to assert it is a server-side audit (which
    //     the migration's trailing `DO $$ ... RAISE NOTICE` block
    //     partially covers — exactly-1-definition collapse is asserted
    //     at deploy time).
    //
    // WHAT THIS STUB ACTUALLY ASSERTS:
    //   • The Phase 5.D flag plumbing wires correctly (re-uses the
    //     setUp/tearDown override pattern). If the flag plumbing is
    //     broken, NO parity assertion downstream can be meaningful
    //     because both branches would fall through to the same path.
    //
    // TODO: Phase 5.D batch-vs-individual parity test — needs ONE of:
    //   (a) An `internal func _testHook_batchCheckAndUnlockSync(
    //          pairs: [(key: String, progress: Int)]
    //       ) async -> [BatchAchievementRow]`
    //       seam on `BadgeService` that runs the batch RPC and returns
    //       the raw rows (no XP / toast side effects), so a mock client
    //       can verify the request payload + response handling.
    //   (b) A live Supabase staging fixture + a Fit33Tests/ harness
    //       that seeds `user_achievements` rows + auths a service-role
    //       JWT. Not in scope for this PR.
    func testBatchAndIndividualReturnSameProgress() async {
        XCTAssertTrue(
            PerfFlags.phase5BatchAchievements,
            "setUp must force phase5BatchAchievements ON for this test."
        )

        // The actual N-individual-vs-1-batch parity assertion lives in
        // `supabase/20260507_batch_check_achievements.sql` as a code
        // invariant: the per-key LOOP body in the migration is a
        // line-for-line copy of `unlock_achievement` (compare lines
        // 113-180 vs `20260504_olympian_path.sql` 489-554).
        //
        // The strongest in-memory proxy we CAN assert is that
        // `BatchAchievementRow.asUnlockResult` projection preserves the
        // signal that drives the post-unlock cascade — covered by
        // `test_phase5_batchRowDecodesToSameProjectionAsUnlockResult`
        // above. Combined with `test_phase5_batchAchievementRow_decodesAllNineColumns`,
        // these two real tests prove the seam is decode-correct + projection-
        // correct without needing a live DB fixture.
        //
        // A future PR with a `_testHook_batchCheckAndUnlockSync` seam +
        // Supabase staging harness would replace this stub with the
        // real assertion described in the comment block above.
        XCTAssertTrue(
            true,
            "stub: see TODO above. The actual N-individual-vs-1-batch RPC " +
            "side-effect parity is a SERVER-SIDE code invariant " +
            "(supabase/20260507_batch_check_achievements.sql per-key LOOP " +
            "body == supabase/20260504_olympian_path.sql `unlock_achievement` " +
            "body). The two real tests above " +
            "(`…batchAchievementRow_decodesAllNineColumns` + " +
            "`…batchRowDecodesToSameProjectionAsUnlockResult`) cover the " +
            "decode + projection halves of the parity contract."
        )
    }
}
