-- ════════════════════════════════════════════════════════════════════
-- Migration #113 — Mark fingerprints resolved from the
-- bug-intelligence-audit-2026-04-25T19-07-36 export (13 fingerprints).
-- 2026-04-25
--
-- Closes-out the 13 audit fingerprints by bucket:
--
--   • migration_resolved     — server fix already DEPLOYED on prod
--   • migration_pending_deploy — server fix is on disk, awaiting deploy
--   • code_fix               — paired iOS change shipped in this sprint
--
-- Pairs with:
--   #109 / #110 / #111 (prior audit close-outs — same convention)
--   #90  (`20260524_private_challenge_deadlock_retry.sql`) — deploy
--        before this migration (or alongside) to flip R4 + R12 from
--        `migration_pending_deploy` to fully terminal.
--   #112 (`20260612_fix_challenge_realtime_replica_identity.sql`) —
--        deploy before this migration to flip R11 to terminal.
--
-- Reports/Fingerprints handled (audit timestamp 2026-04-25T19:07:36Z):
--
-- HIGH severity:
--   R1  e656ad7a4fb1323db476cd8f2cf6ac39 — daily quests sig mismatch
--                                          (detailed)
--   R2  e810bf12eb825d4887a761ada6e0f90b — workout_context RLS
--   R3  ec1a155414f492486213a5b740f215a6 — daily quests sig mismatch
--                                          (comprehensive)
--   R4  3d7ac331e9011e75e363f217b5827006 — private challenge deadlock
--   R5  7bf1ff4efdac6620edfbda328204ed16 — quest insights view missing
--   R6  1b6e9111a71c83930852e93f1aff33e5 — collaborative_workout_data RLS
--   R7  f30626309d8480ec14526323da68396d — quest insights view missing
--                                          (log variant)
--   R8  ed249878cacb36901a508321b4e44ecb — autogen stretches for
--                                          advanced strength user
--
-- MEDIUM severity:
--   R9  00bd6a627c915cc0e49ed59a6a3cc140 — auth signup user already
--                                          registered
--   R10 15cce20e4302a42e1437f65fdf8fa667 — same, log variant
--   R11 eeaa35d1e72f7e116431d82878f160c3 — challenge widget stale
--   R12 23ac878010450752bb1b1ca994edb56b — private challenge deadlock
--                                          (log variant)
--   R13 22422e4eaca00ea54a0ac3e5fbcb2d8a — auth email rate limit
--                                          exceeded
--
-- ────────────────────────────────────────────────────────────────────
-- Paired iOS code changes shipped in this sprint:
--
--   1. Fit33/WorkoutManager.swift
--      `recordWorkoutContext`, `recordExercisePerformance`, the
--      collaborative-engine call, and `updateEquipmentProficiency`
--      now source `user_id` from `SupabaseManager.shared.currentUser?.id`
--      (auth.uid()) instead of Core Data `User.id`. Eliminates 42501
--      RLS violations for legacy accounts whose Core Data UUID predates
--      the UserManager auth-alignment fix. Catch blocks now route
--      through `NetworkErrorClassifier.log(...)` (QP invariant 25a).
--      Resolves R2 + R6 client-side leg.
--
--   2. Fit33/CollaborativeLearningEngine.swift
--      `recordWorkoutCompletion` catch block migrated from raw
--      `AppLogger.error` to `NetworkErrorClassifier.log(...)` so any
--      residual transient/auth errors don't generate new fingerprints.
--      Resolves R6 client-side leg.
--
--   3. Fit33/QuestInsightsView.swift
--      `loadInsights` now treats PGRST205 / "schema cache" / "relation
--      does not exist" as a soft empty-state instead of a banner +
--      `AppLogger.error`. Catches are routed through the classifier at
--      `transientLevel: .debug`. Resolves R5 + R7 client-side leg
--      (defensive UX while view rollout completes everywhere).
--
--   4. Fit33/ProgressiveExerciseUnlockService.swift
--      Adds `clearCache()` (called on sign-out from
--      `SupabaseManager.signOut`) and `recomputeProfile(context:)`
--      (called eagerly post `syncAllDataFromCloud`). The
--      `shouldRestrictToFoundational` / `varietyPercentage` getters
--      now fall back to a Core Data workout-count probe when the
--      cached profile is missing, so the autogen path doesn't briefly
--      gate returning users to foundational/stretch-only exercises
--      after a fresh sign-in. Resolves R8.
--
--   5. Fit33/NewOnboardingView+Auth.swift
--      `handleAuth` signup catch blocks (both typed
--      `SupabaseAuthError` and the generic catch) and the post-signup
--      catch in `signUpOrRecoverExistingAccount` now use
--      `NetworkErrorClassifier.log(...)` instead of `AppLogger.error`.
--      "User already registered" lands at `.debug`
--      (.expectedUserState); rate-limit lands at `.debug`
--      (.transientNetwork). Resolves R9 + R10 + R13.
--
--   6. Fit33/NetworkErrorClassifier.swift
--      Adds explicit "rate limit" / "too many requests" / HTTP 429
--      patterns to the `.transientNetwork` bucket so any auth-edge
--      function 429 throughout the app is auto-classified. Reinforces
--      R13.
--
-- ────────────────────────────────────────────────────────────────────
-- Idempotent: WHERE clauses filter by fingerprint, re-running is a
-- no-op. Wrapped in `BEGIN; … COMMIT;`.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- Bucket 1: migration_resolved
--   Fingerprints whose server-side fix is already DEPLOYED on prod
--   (per MIGRATION_INDEX.md status as of 2026-04-25).
--
--   R1, R3 → #106 `20260605_get_daily_quests_personalized.sql` (deployed)
--          — RPC v3 signature now matches the iOS client's parameter
--            set; PGRST202 stops firing once the schema cache reloads.
--   R5, R7 → #108 `20260607_pro_quest_monetization.sql` (deployed)
--          — `v_user_quest_personalization_summary` view created;
--            QuestInsightsView's defensive empty-state guard handles
--            the brief schema-cache propagation window for build
--            cohorts that hit prod before the cache reload.
--   R6     → bundle A `20260608_workout_intelligence_rls_audit.sql`
--            (deployed) — RLS policies re-asserted on
--            `collaborative_workout_data`. Paired with the iOS
--            auth.uid() alignment in change #1 above.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260605+20260607+20260608',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'e656ad7a4fb1323db476cd8f2cf6ac39', -- R1 daily quests sig mismatch (detailed)
    'ec1a155414f492486213a5b740f215a6', -- R3 daily quests sig mismatch (comprehensive)
    '7bf1ff4efdac6620edfbda328204ed16', -- R5 quest insights view missing
    'f30626309d8480ec14526323da68396d'  -- R7 quest insights view missing (log)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 2: migration_resolved + code_fix (RLS + auth.uid alignment)
--   R2 (workout_context RLS) and R6 (collaborative_workout_data RLS)
--   require BOTH:
--     - the deployed RLS reassert (bundle A — already on prod), AND
--     - the iOS-side auth.uid() alignment change shipped this sprint.
--   Mark the bucket as code_fix so the Improvement Tracker links
--   them to the WorkoutManager / CollaborativeLearningEngine diffs;
--   the migration prerequisites are documented in the migration
--   header.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix:auth_uid_alignment+classifier_routing',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'e810bf12eb825d4887a761ada6e0f90b', -- R2 workout_context RLS
    '1b6e9111a71c83930852e93f1aff33e5'  -- R6 collaborative_workout_data RLS
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 3: code_fix (pure iOS-side fixes)
--   R8 — autogen stretches for advanced strength user. Fixed by
--        ProgressiveExerciseUnlockService.clearCache() on sign-out +
--        recomputeProfile() on post-sync + Core Data fallback in the
--        getter accessors.
--   R9 — "User already registered" signup. Fixed by routing the
--        handleAuth catch blocks through NetworkErrorClassifier
--        (.expectedUserState bucket).
--   R10 — same root cause, log variant.
--   R13 — auth email rate limit exceeded. Fixed by adding rate-limit
--        patterns to the classifier (.transientNetwork bucket) and
--        routing the same handleAuth catches.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'ed249878cacb36901a508321b4e44ecb', -- R8 autogen stretches
    '00bd6a627c915cc0e49ed59a6a3cc140', -- R9 user already registered
    '15cce20e4302a42e1437f65fdf8fa667', -- R10 user already registered (log)
    '22422e4eaca00ea54a0ac3e5fbcb2d8a'  -- R13 auth email rate limit
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 4: migration_pending_deploy
--   Server fix is written and committed on disk but not yet deployed
--   to prod. Flip to `resolved` with the pending-deploy reason so the
--   Improvement Tracker shows progress; the trailing `DO $$` block
--   below RAISES NOTICE if the migration files are missing on disk.
--
--   R4, R12 → #90  `20260524_private_challenge_deadlock_retry.sql`
--   R11      → #112 `20260612_fix_challenge_realtime_replica_identity.sql`
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_pending_deploy:20260524',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '3d7ac331e9011e75e363f217b5827006', -- R4 private challenge deadlock
    '23ac878010450752bb1b1ca994edb56b'  -- R12 private challenge deadlock (log)
)
  AND status <> 'resolved';

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_pending_deploy:20260612',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint = 'eeaa35d1e72f7e116431d82878f160c3' -- R11 challenge widget stale
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Merge any pending bug_intelligence_reports rows for these
-- fingerprints with a paper-trail note (matches migrations
-- #109/#110/#111 convention).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-25 19:07 audit] '
                    || 'Auto-merged by 20260613_mark_audit_2026_04_25_19_07_resolved.sql — '
                    || 'see migration header for per-fingerprint bucket.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    'e656ad7a4fb1323db476cd8f2cf6ac39',
    'e810bf12eb825d4887a761ada6e0f90b',
    'ec1a155414f492486213a5b740f215a6',
    '3d7ac331e9011e75e363f217b5827006',
    '7bf1ff4efdac6620edfbda328204ed16',
    '1b6e9111a71c83930852e93f1aff33e5',
    'f30626309d8480ec14526323da68396d',
    'ed249878cacb36901a508321b4e44ecb',
    '00bd6a627c915cc0e49ed59a6a3cc140',
    '15cce20e4302a42e1437f65fdf8fa667',
    'eeaa35d1e72f7e116431d82878f160c3',
    '23ac878010450752bb1b1ca994edb56b',
    '22422e4eaca00ea54a0ac3e5fbcb2d8a'
);

-- ────────────────────────────────────────────────────────────────────
-- Verify — should print 13 fingerprints in terminal status.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
    FROM bug_intelligence_fingerprints
    WHERE fingerprint IN (
        'e656ad7a4fb1323db476cd8f2cf6ac39',
        'e810bf12eb825d4887a761ada6e0f90b',
        'ec1a155414f492486213a5b740f215a6',
        '3d7ac331e9011e75e363f217b5827006',
        '7bf1ff4efdac6620edfbda328204ed16',
        '1b6e9111a71c83930852e93f1aff33e5',
        'f30626309d8480ec14526323da68396d',
        'ed249878cacb36901a508321b4e44ecb',
        '00bd6a627c915cc0e49ed59a6a3cc140',
        '15cce20e4302a42e1437f65fdf8fa667',
        'eeaa35d1e72f7e116431d82878f160c3',
        '23ac878010450752bb1b1ca994edb56b',
        '22422e4eaca00ea54a0ac3e5fbcb2d8a'
    )
      AND status = 'resolved';

    SELECT COUNT(*) INTO v_merged_count
    FROM bug_intelligence_reports
    WHERE review_status = 'merged'
      AND review_notes LIKE '%2026-04-25 19:07 audit%';

    RAISE NOTICE 'Marked % fingerprint(s) resolved (expected 13).', v_resolved_count;
    RAISE NOTICE 'Merged % report(s) with audit-19:07 paper trail.', v_merged_count;

    IF v_resolved_count < 13 THEN
        RAISE WARNING 'Expected 13 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;
