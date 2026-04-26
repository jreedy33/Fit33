-- ════════════════════════════════════════════════════════════════════
-- Migration #120 — Mark fingerprints resolved from the
-- bug-intelligence-NEW-2026-04-26T17-32-20 export.
-- 2026-04-26
--
-- Companion to:
--   #116 (20260616_mark_new_2026_04_25_20_34_resolved.sql) — flushed the
--        20 build-1.38 cohort recurrences whose fixes were already
--        deployed.
--   #115 (20260615_fix_nudge_group_challenge_member_column_drift.sql)
--        — server-side RPC fix for d8fe113b. DEPLOYED 2026-04-26.
--   #117 (20260617_fix_get_daily_quests_int_overflow.sql) — server-side
--        BIGINT cast for hashtext() overflow. DEPLOYED 2026-04-26.
--   #119 (20260618_log_challenge_progress_deadlock_retry.sql) —
--        deterministic lock order + 40P01 retry on the 1v1 RPC.
--        (Note: shares date prefix with #118 wake_diagnostics_rpc.sql
--        — both are 20260618_*; release-train number disambiguates.)
--
-- This export ran with mode=`new`. After triage (review by Cursor agent
-- in plan mode), the 30 reports break into:
--
--   • 20 fingerprints — STALE recurrences from build-1.38 cohort that
--                       pre-date already-deployed fixes. Already
--                       flushed by #117.
--   • 4 fingerprints  — Daily quests int overflow, RESOLVED by
--                       #117 (deployed 2026-04-26):
--                         R6  64e1ccf7…  (crash version)
--                         R7  265848d4…  (line 1310 variant)
--                         R14 2d865e51…  (medium variant)
--                         R18 c70b931f…  (log version)
--   • 1 fingerprint   — log_challenge_progress 1v1 deadlock, RESOLVED
--                       by #119 (deploys with this sprint):
--                         R21 281382da…
--   • 2 fingerprints  — Cascade noise from R21, RESOLVED by combination
--                       of #119 + paired iOS log-level downgrade in
--                       Fit33/ChallengeService.swift:2235:
--                         R16 bb8962ac…  ("Failed to sync progress for
--                                          ⚔️ 👣 …")
--                         R24 0d1100de…  (same string, product-engineer
--                                          triage)
--   • 2 fingerprints  — WorkoutManager classifier-bypass, RESOLVED by
--                       paired iOS log-level downgrade in
--                       Fit33/WorkoutManager.swift:1199 (`.error` →
--                       `.warning`):
--                         R15 50e7a9a7…
--                         R29 cf3a4a8b…
--   • 1 fingerprint   — Daily quests sig mismatch (comprehensive params).
--                       Same root cause as e656ad7a (already in #117).
--                       Pre-existing migration 20260605 covers this; the
--                       fingerprint is a duplicate triage row that the
--                       collapse logic missed:
--                         R23 e066c226…
--   • 5 fingerprints  — Pre-classifier-build cohort noise (builds 1.29.0,
--                       1.32.0, 1.37 — pre-dating the
--                       CrashReportingService.shouldSuppressMessage
--                       denylist for rate-limit / offline). No code
--                       change needed; just flush:
--                         R10 1edfaad0… (pwd reset rate limit, regressed)
--                         R25 1e8bef49… (pwd reset rate limit dup #1)
--                         R26 a7fc10fa… (pwd reset rate limit dup #2)
--                         R27 0080557f… (pwd reset rate limit, 1.32.0)
--                         R30 18a4b0fc… (insights streak offline, 1.37)
--
-- Pairs with paired iOS code changes shipped THIS sprint (2026-04-26 PM,
-- single commit referencing each fingerprint):
--
--   1. Fit33/WorkoutManager.swift (cancelWorkout)
--      Downgraded `AppLogger.error("❌ WorkoutManager: Cancelling current
--      workout")` to `AppLogger.warning(...)`. Cancellation is expected
--      user / auto-end behavior, not an error. The previous `.error`
--      level double-reported through CrashReportingService and created a
--      fingerprint per cancel (50e7a9a7 / cf3a4a8b). `.warning` keeps
--      the dev/TF breadcrumb without the crash-row upload.
--      Resolves R15 + R29.
--
--   2. Fit33/ChallengeService.swift (syncHealthKitDataToChallenges loop)
--      Downgraded the cascade `AppLogger.error("Failed to sync progress
--      for '<title>'")` to `.warning`. The underlying `logProgress`
--      method already routes the real failure through
--      `NetworkErrorClassifier.log(...)` with op + endpoint + pg_code at
--      ChallengeService.swift:2115, so the outer `.error` was duplicate
--      noise that produced the bb8962ac / 0d1100de cascade fingerprints.
--      Resolves R16 + R24 (in addition to the server-side fix in #119
--      taking out the underlying 281382da deadlock).
--
-- ────────────────────────────────────────────────────────────────────
-- Idempotent: WHERE clauses filter by fingerprint, re-running is a
-- no-op. Wrapped in `BEGIN; … COMMIT;`.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- Bucket 1: migration_resolved (NEW this sprint, deploys today)
--   R6 / R7 / R14 / R18 → #117
--     `20260617_fix_get_daily_quests_int_overflow.sql` — BIGINT cast
--     prevents abs(hashtext(...)) from overflowing INT_MIN.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260617',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '64e1ccf7bf450c9d591fab6d80f41847', -- R6  daily quests int overflow (crash)
    '265848d4ecf46ff84e247d8b572af43b', -- R7  daily quests int overflow (line 1310)
    '2d865e51c4cf99a5b3a05d17e1d5bce0', -- R14 daily quests int overflow (medium)
    'c70b931f12e33e65a564d5935d43b2d1'  -- R18 daily quests int overflow (log)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 2: migration_resolved (NEW this sprint, deploys today)
--   R21 → #119
--     `20260618_log_challenge_progress_deadlock_retry.sql` —
--     deterministic lock order on challenge_participants + 40P01 retry
--     mirrors the 20260524 private-challenge fix recipe.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260618',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint = '281382daef477e9d9e74d517737aca99' -- R21 1v1 chal deadlock
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 3: code_fix (paired iOS changes shipped this sprint)
--   R15 / R29 → WorkoutManager.swift:1199 .error → .warning
--   R16 / R24 → ChallengeService.swift:2235 .error → .warning
--               (also drains once #119 lands — belt-and-suspenders)
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix:classifier_routing',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '50e7a9a7b37ec927f6ff3fe6db3b3134', -- R15 WorkoutManager cancellation
    'cf3a4a8b356b8152ea83e6e7bf96c9e9', -- R29 same, no-callsite variant
    'bb8962ac8f2dd3ef51f12bddb04cabde', -- R16 chal sync cascade ("Failed to sync …")
    '0d1100deb68ce4cac3662968aa11c15c'  -- R24 same string, product-engineer triage
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 4: migration_resolved (already deployed, dup of #117 entry)
--   R23 e066c226 — same root cause as e656ad7a / ec1a155414 (sig
--                  mismatch). #117 marked the canonical pair resolved;
--                  this row is a triage variant the collapse missed.
--                  Pre-existing migration 20260605 covers it.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260605+20260607',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint = 'e066c226e44877e375bada10bb3cd43e' -- R23 sig mismatch (comp params)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 5: code_fix (pre-classifier-build cohort noise — already
--   shipped denylist in CrashReportingService.shouldSuppressMessage,
--   the new fingerprints are from cohorts on builds that pre-date that
--   ship: 1.29.0, 1.32.0, 1.37). Same convention as #116 R12+R17+R18+
--   R19+R20.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix:crash_reporter_denylist_pre_cohort',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '1edfaad0c87c90a26f1fb59fb5cbc983', -- R10 pwd reset rate limit (regressed)
    '1e8bef4991bef4fbdb0ba8791829d8ed', -- R25 pwd reset rate limit (dup #1)
    'a7fc10fa68ed89100ad8fbced66a0ed7', -- R26 pwd reset rate limit (dup #2)
    '0080557f0dc278d22c345638b8e7d280', -- R27 pwd reset rate limit (1.32.0)
    '18a4b0fc76b0cf6a17702443b82feb15'  -- R30 insights streak offline (1.37)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Merge any pending bug_intelligence_reports rows for these
-- fingerprints with a paper-trail note (matches migration #116
-- convention).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-26 17:32 new-export] '
                    || 'Auto-merged by 20260619_mark_new_2026_04_26_resolved.sql — '
                    || 'see migration header for per-fingerprint bucket.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    '64e1ccf7bf450c9d591fab6d80f41847',
    '265848d4ecf46ff84e247d8b572af43b',
    '2d865e51c4cf99a5b3a05d17e1d5bce0',
    'c70b931f12e33e65a564d5935d43b2d1',
    '281382daef477e9d9e74d517737aca99',
    '50e7a9a7b37ec927f6ff3fe6db3b3134',
    'cf3a4a8b356b8152ea83e6e7bf96c9e9',
    'bb8962ac8f2dd3ef51f12bddb04cabde',
    '0d1100deb68ce4cac3662968aa11c15c',
    'e066c226e44877e375bada10bb3cd43e',
    '1edfaad0c87c90a26f1fb59fb5cbc983',
    '1e8bef4991bef4fbdb0ba8791829d8ed',
    'a7fc10fa68ed89100ad8fbced66a0ed7',
    '0080557f0dc278d22c345638b8e7d280',
    '18a4b0fc76b0cf6a17702443b82feb15'
  );

-- ────────────────────────────────────────────────────────────────────
-- Verify — should print 15 fingerprints in terminal status.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
      FROM bug_intelligence_fingerprints
     WHERE fingerprint IN (
        '64e1ccf7bf450c9d591fab6d80f41847',
        '265848d4ecf46ff84e247d8b572af43b',
        '2d865e51c4cf99a5b3a05d17e1d5bce0',
        'c70b931f12e33e65a564d5935d43b2d1',
        '281382daef477e9d9e74d517737aca99',
        '50e7a9a7b37ec927f6ff3fe6db3b3134',
        'cf3a4a8b356b8152ea83e6e7bf96c9e9',
        'bb8962ac8f2dd3ef51f12bddb04cabde',
        '0d1100deb68ce4cac3662968aa11c15c',
        'e066c226e44877e375bada10bb3cd43e',
        '1edfaad0c87c90a26f1fb59fb5cbc983',
        '1e8bef4991bef4fbdb0ba8791829d8ed',
        'a7fc10fa68ed89100ad8fbced66a0ed7',
        '0080557f0dc278d22c345638b8e7d280',
        '18a4b0fc76b0cf6a17702443b82feb15'
     )
       AND status = 'resolved';

    SELECT COUNT(*) INTO v_merged_count
      FROM bug_intelligence_reports
     WHERE review_status = 'merged'
       AND review_notes LIKE '%2026-04-26 17:32 new-export%';

    RAISE NOTICE '[20260619] Marked % fingerprint(s) resolved (expected 15).', v_resolved_count;
    RAISE NOTICE '[20260619] Merged % report(s) with new-export-17:32 paper trail.', v_merged_count;

    IF v_resolved_count < 15 THEN
        RAISE WARNING '[20260619] Expected 15 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;
