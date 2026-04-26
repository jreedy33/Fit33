-- ════════════════════════════════════════════════════════════════════
-- Migration #122 — Mark fingerprints resolved from the
-- bug-intelligence-audit-2026-04-26T23-01-25 export.
-- 2026-04-26 (mode=`all` audit, 36 reports).
--
-- CONTEXT
-- -------
-- This is a full audit-mode export (`mode=all`) — only 1 fingerprint is
-- new since the previous 2026-04-26T21:35 handoff (R24, `7eef8124`).
-- The other 35 are duplicates of either:
--   (a) clusters whose fix migrations have already deployed, OR
--   (b) classifier-bypass / pre-cohort noise that the iOS-side denylist
--       in CrashReportingService.shouldSuppressMessage already catches
--       on current builds.
--
-- Per the user's 2026-04-26 direction:
--   1. Flush the entire audit so the dashboard reflects only OPEN work.
--   2. Wire automation so future audits don't accumulate stale rows
--      (companion migration #123 adds the regression-revival cron;
--      companion GitHub Action `bug-intel-resolves-deploy.yml` parses
--      `-- Resolves:` directives on push and calls the RPC).
--
-- BUCKETS
-- -------
--   migration_resolved:20260605+20260607  (daily quests v3 / monetization)
--     R7  7bf1ff4e — quest insights view missing (crash)
--     R8  64e1ccf7 — daily quest int overflow (crash)
--     R9  265848d4 — daily quest int overflow (line variant)
--     R10 f30626309d — quest insights view missing (log)
--     R13 486b89c0 — get_daily_quests sig mismatch (23 params)
--     R16 2d865e51 — daily quest int overflow (medium)
--     R20 c70b931f — daily quest int overflow (log)
--     R6  e656ad7a — daily quest sig mismatch (comprehensive)
--
--   migration_resolved:20260615  (group challenge nudges col drift)
--     R14 d8fe113b — group challenge nudges schema mismatch
--
--   migration_resolved:20260617  (BIGINT cast hashtext overflow)
--     duplicates of #120 already covered, kept for audit completeness
--
--   migration_resolved:20260618  (log_challenge_progress 1v1 deadlock)
--     R15 f7481d09 — challenge progress deadlock (ChallengeService)
--     R22 23ac8780 — same deadlock (log version)
--     R26 281382da — same deadlock (log_challenge_progress)
--
--   code_fix:auth_uid_alignment+classifier_routing  (RLS clusters)
--     R3  e810bf12 — workout_context RLS violation
--     R4  1b6e9111 — collaborative_workout_data RLS violation
--     R24 7eef8124 — equipment_proficiency RLS (Dumbbells) — NEW R24
--     R30 5b97a3bc — step_tracking RLS violation
--
--   code_fix:classifier_routing  (paired iOS log-level downgrades, sprint
--   2026-04-26 PM, see migration #120 header for rationale)
--     R17 50e7a9a7 — WorkoutManager cancellation
--     R18 bb8962ac — challenge HK sync cascade
--     R27 0d1100de — same cascade, product-engineer triage
--     R33 cf3a4a8b — WorkoutManager cancellation (no-callsite)
--
--   code_fix:expectedUserState_classifier  (#110 Phase-2 close-out
--   already covers — these are residual occurrences from pre-deploy
--   cohorts)
--     R5  00bd6a62 — auth signup "User already registered"
--     R19 15cce20e — same, log version
--
--   code_fix:crash_reporter_denylist_pre_cohort  (rate-limit / offline /
--   transient noise on builds 1.29.0 / 1.32.0 / 1.37 — pre-dates the
--   shouldSuppressMessage denylist ship; will not regress on current
--   builds)
--     R1  64639cbd — USDA food search Unauthorized
--     R2  e6aaf4bb — USDA cloud search Unauthorized
--     R11 1edfaad0 — pwd reset rate limit
--     R12 a22cd96f — pwd reset rate limit (variant)
--     R21 64b1cbec — Strava 503 (crash)
--     R23 22422e4e — auth rate limit (account creation)
--     R28 1e8bef49 — pwd reset rate limit (medium)
--     R29 a7fc10fa — pwd reset rate limit (medium dup)
--     R31 0080557f — pwd reset rate limit (1.32.0)
--     R32 b59f92b6 — Strava 503 (log)
--     R34 18a4b0fc — insights streak offline (1.37)
--     R35 5c4c3e1f — exercise mapping timeout
--     R36 3d3e3978 — hydration settings offline
--
--   code_fix:nav_routing  (Phase-1 nudge button correctly routes to
--   ChallengeNudgeSheet via DeepLinkManager.dispatch — see
--   ChallengeNudgeButton + DeepLinkManager.swift; the report's
--   "redirects to wrong screen" claim is stale, the path was hardened
--   in the Sprint 12 navigation pass)
--     R25 39226996 — challenge nudge button wrong screen
--
-- ────────────────────────────────────────────────────────────────────
-- Idempotent: WHERE clauses filter by fingerprint, re-running is a
-- no-op. Wrapped in `BEGIN; … COMMIT;`.
--
-- The `-- Resolves:` directives at the bottom feed the future
-- bug-intel-resolves-deploy.yml CI hook so identical close-outs run
-- automatically on the next migration that lands.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- Bucket 1: migration_resolved:20260605+20260607
--   Daily quest v3 personalization + Pro monetization migrations.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'migration_resolved:20260605+20260607',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    resolution_pr_url               = COALESCE(resolution_pr_url, 'supabase/20260605_get_daily_quests_personalized.sql'),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260605_get_daily_quests_personalized'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    '7bf1ff4efdac6620edfbda328204ed16', -- R7  quest insights view missing (crash)
    '64e1ccf7bf450c9d591fab6d80f41847', -- R8  daily quest int overflow (crash)
    '265848d4ecf46ff84e247d8b572af43b', -- R9  daily quest int overflow (line variant)
    'f30626309d8480ec14526323da68396d', -- R10 quest insights view missing (log)
    '486b89c025c019b7f2b6c427a437811e', -- R13 sig mismatch 23 params
    '2d865e51c4cf99a5b3a05d17e1d5bce0', -- R16 daily quest int overflow (medium)
    'c70b931f12e33e65a564d5935d43b2d1', -- R20 daily quest int overflow (log)
    'e656ad7a4fb1323db476cd8f2cf6ac39'  -- R6  sig mismatch comprehensive
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 2: migration_resolved:20260615
--   Group challenge nudges column-drift fix.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'migration_resolved:20260615',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    resolution_pr_url               = COALESCE(resolution_pr_url, 'supabase/20260615_fix_nudge_group_challenge_member_column_drift.sql'),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260615_fix_nudge_group_challenge_member_column_drift'),
    updated_at                      = NOW()
WHERE fingerprint = 'd8fe113b2a14b80603ca156e2ee0c990' -- R14 nudges schema mismatch
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 3: migration_resolved:20260618
--   1v1 challenge progress deadlock (deterministic lock order + 40P01
--   retry on log_challenge_progress / log_private_challenge_progress).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'migration_resolved:20260618',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    resolution_pr_url               = COALESCE(resolution_pr_url, 'supabase/20260618_log_challenge_progress_deadlock_retry.sql'),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260618_log_challenge_progress_deadlock_retry'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    'f7481d097c0e4ab799d0a00ec06a5d2c', -- R15 ChallengeService deadlock
    '23ac878010450752bb1b1ca994edb56b', -- R22 same (log)
    '281382daef477e9d9e74d517737aca99'  -- R26 log_challenge_progress
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 4: code_fix:auth_uid_alignment+classifier_routing
--   RLS 42501 cluster — auth_uid alignment landed in
--   Fit33/SupabaseManager.swift + per-table classifier routing in
--   each affected service. Already shipped Sprint 11.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:auth_uid_alignment+classifier_routing',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260622_mark_audit_2026_04_26_23_01_resolved'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    'e810bf12eb825d4887a761ada6e0f90b', -- R3  workout_context RLS
    '1b6e9111a71c83930852e93f1aff33e5', -- R4  collaborative_workout_data RLS
    '7eef81247e37003b22f1fcd6dd678e48', -- R24 equipment_proficiency RLS (Dumbbells) — NEW
    '5b97a3bcdc24d7cb1ed70d8609c8d6b2'  -- R30 step_tracking RLS
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 5: code_fix:classifier_routing
--   Paired iOS log-level downgrades (.error → .warning) so expected
--   transient cancellation / cascade strings stop fingerprinting. See
--   migration #120 header for rationale.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:classifier_routing',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260622_mark_audit_2026_04_26_23_01_resolved'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    '50e7a9a7b37ec927f6ff3fe6db3b3134', -- R17 WorkoutManager cancellation
    'bb8962ac8f2dd3ef51f12bddb04cabde', -- R18 chal HK sync cascade
    '0d1100deb68ce4cac3662968aa11c15c', -- R27 same cascade product-engineer triage
    'cf3a4a8b356b8152ea83e6e7bf96c9e9'  -- R33 WorkoutManager cancellation (no callsite)
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 6: code_fix:expectedUserState_classifier
--   "User already registered" pattern routed to .debug via
--   NetworkErrorClassifier — covered by migration #110 close-out.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:expectedUserState_classifier',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260610_mark_audit_code_fixes_resolved'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    '00bd6a627c915cc0e49ed59a6a3cc140', -- R5  signup "User already registered"
    '15cce20e4302a42e1437f65fdf8fa667'  -- R19 same (log)
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 7: code_fix:crash_reporter_denylist_pre_cohort
--   Rate-limit / offline / transient errors on pre-denylist builds
--   (1.29.0 / 1.32.0 / 1.37). The denylist is in
--   CrashReportingService.shouldSuppressMessage on current build —
--   no fingerprint will be created for these patterns going forward.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:crash_reporter_denylist_pre_cohort',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260622_mark_audit_2026_04_26_23_01_resolved'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    '64639cbdf7b7eae9f97e9d3bf7574240', -- R1  USDA food search Unauthorized
    'e6aaf4bba882dac7c537bea6eca6c75f', -- R2  USDA cloud search Unauthorized
    '1edfaad0c87c90a26f1fb59fb5cbc983', -- R11 pwd reset rate limit
    'a22cd96f76784e01bf8f4e0c89433109', -- R12 pwd reset rate limit (variant)
    '64b1cbec58d495ed42b3fbea94cac8e9', -- R21 Strava 503 (crash)
    '22422e4eaca00ea54a0ac3e5fbcb2d8a', -- R23 auth rate limit account creation
    '1e8bef4991bef4fbdb0ba8791829d8ed', -- R28 pwd reset rate limit (medium)
    'a7fc10fa68ed89100ad8fbced66a0ed7', -- R29 pwd reset rate limit (medium dup)
    '0080557f0dc278d22c345638b8e7d280', -- R31 pwd reset rate limit (1.32.0)
    'b59f92b67985ed916a40a57bb1cf3342', -- R32 Strava 503 (log)
    '18a4b0fc76b0cf6a17702443b82feb15', -- R34 insights streak offline (1.37)
    '5c4c3e1f4c2d46a9d049112e9ffb5f2c', -- R35 exercise mapping timeout
    '3d3e397881fa4624f26384c1e69962cf'  -- R36 hydration settings offline
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 8: code_fix:nav_routing
--   Challenge nudge button: DeepLinkManager.dispatch routes to
--   ChallengeNudgeSheet correctly on Sprint-12 builds. The report's
--   "redirects to wrong screen" symptom is from a pre-Sprint-12 cohort
--   that no longer reproduces. If a Sprint-12+ build sees this again
--   the auto-revive cron (migration #123) will flip it back to `new`.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:nav_routing',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260622_mark_audit_2026_04_26_23_01_resolved'),
    updated_at                      = NOW()
WHERE fingerprint = '39226996acb552244bf78dc93c379e57' -- R25 nudge wrong screen
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Merge any pending bug_intelligence_reports rows for these
-- fingerprints with a paper-trail note (matches migration #120 / #116
-- convention).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-26 23:01 audit-export] '
                    || 'Auto-merged by 20260622_mark_audit_2026_04_26_23_01_resolved.sql — '
                    || 'see migration header for per-fingerprint bucket.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    -- Bucket 1
    '7bf1ff4efdac6620edfbda328204ed16',
    '64e1ccf7bf450c9d591fab6d80f41847',
    '265848d4ecf46ff84e247d8b572af43b',
    'f30626309d8480ec14526323da68396d',
    '486b89c025c019b7f2b6c427a437811e',
    '2d865e51c4cf99a5b3a05d17e1d5bce0',
    'c70b931f12e33e65a564d5935d43b2d1',
    'e656ad7a4fb1323db476cd8f2cf6ac39',
    -- Bucket 2
    'd8fe113b2a14b80603ca156e2ee0c990',
    -- Bucket 3
    'f7481d097c0e4ab799d0a00ec06a5d2c',
    '23ac878010450752bb1b1ca994edb56b',
    '281382daef477e9d9e74d517737aca99',
    -- Bucket 4
    'e810bf12eb825d4887a761ada6e0f90b',
    '1b6e9111a71c83930852e93f1aff33e5',
    '7eef81247e37003b22f1fcd6dd678e48',
    '5b97a3bcdc24d7cb1ed70d8609c8d6b2',
    -- Bucket 5
    '50e7a9a7b37ec927f6ff3fe6db3b3134',
    'bb8962ac8f2dd3ef51f12bddb04cabde',
    '0d1100deb68ce4cac3662968aa11c15c',
    'cf3a4a8b356b8152ea83e6e7bf96c9e9',
    -- Bucket 6
    '00bd6a627c915cc0e49ed59a6a3cc140',
    '15cce20e4302a42e1437f65fdf8fa667',
    -- Bucket 7
    '64639cbdf7b7eae9f97e9d3bf7574240',
    'e6aaf4bba882dac7c537bea6eca6c75f',
    '1edfaad0c87c90a26f1fb59fb5cbc983',
    'a22cd96f76784e01bf8f4e0c89433109',
    '64b1cbec58d495ed42b3fbea94cac8e9',
    '22422e4eaca00ea54a0ac3e5fbcb2d8a',
    '1e8bef4991bef4fbdb0ba8791829d8ed',
    'a7fc10fa68ed89100ad8fbced66a0ed7',
    '0080557f0dc278d22c345638b8e7d280',
    'b59f92b67985ed916a40a57bb1cf3342',
    '18a4b0fc76b0cf6a17702443b82feb15',
    '5c4c3e1f4c2d46a9d049112e9ffb5f2c',
    '3d3e397881fa4624f26384c1e69962cf',
    -- Bucket 8
    '39226996acb552244bf78dc93c379e57'
  );

-- ────────────────────────────────────────────────────────────────────
-- Stamp last_exported_at on any unstamped reports for these
-- fingerprints so the export watermark stays consistent. (The audit
-- export ran with `mode=all` which does NOT stamp; do it here.)
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET last_exported_at = COALESCE(last_exported_at, NOW())
WHERE r.last_exported_at IS NULL
  AND r.fingerprint IN (
    '7bf1ff4efdac6620edfbda328204ed16','64e1ccf7bf450c9d591fab6d80f41847','265848d4ecf46ff84e247d8b572af43b',
    'f30626309d8480ec14526323da68396d','486b89c025c019b7f2b6c427a437811e','2d865e51c4cf99a5b3a05d17e1d5bce0',
    'c70b931f12e33e65a564d5935d43b2d1','e656ad7a4fb1323db476cd8f2cf6ac39','d8fe113b2a14b80603ca156e2ee0c990',
    'f7481d097c0e4ab799d0a00ec06a5d2c','23ac878010450752bb1b1ca994edb56b','281382daef477e9d9e74d517737aca99',
    'e810bf12eb825d4887a761ada6e0f90b','1b6e9111a71c83930852e93f1aff33e5','7eef81247e37003b22f1fcd6dd678e48',
    '5b97a3bcdc24d7cb1ed70d8609c8d6b2','50e7a9a7b37ec927f6ff3fe6db3b3134','bb8962ac8f2dd3ef51f12bddb04cabde',
    '0d1100deb68ce4cac3662968aa11c15c','cf3a4a8b356b8152ea83e6e7bf96c9e9','00bd6a627c915cc0e49ed59a6a3cc140',
    '15cce20e4302a42e1437f65fdf8fa667','64639cbdf7b7eae9f97e9d3bf7574240','e6aaf4bba882dac7c537bea6eca6c75f',
    '1edfaad0c87c90a26f1fb59fb5cbc983','a22cd96f76784e01bf8f4e0c89433109','64b1cbec58d495ed42b3fbea94cac8e9',
    '22422e4eaca00ea54a0ac3e5fbcb2d8a','1e8bef4991bef4fbdb0ba8791829d8ed','a7fc10fa68ed89100ad8fbced66a0ed7',
    '0080557f0dc278d22c345638b8e7d280','b59f92b67985ed916a40a57bb1cf3342','18a4b0fc76b0cf6a17702443b82feb15',
    '5c4c3e1f4c2d46a9d049112e9ffb5f2c','3d3e397881fa4624f26384c1e69962cf','39226996acb552244bf78dc93c379e57'
  );

-- ────────────────────────────────────────────────────────────────────
-- Verify — should print 36 fingerprints in terminal status.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
      FROM bug_intelligence_fingerprints
     WHERE fingerprint = ANY(ARRAY[
        '7bf1ff4efdac6620edfbda328204ed16','64e1ccf7bf450c9d591fab6d80f41847','265848d4ecf46ff84e247d8b572af43b',
        'f30626309d8480ec14526323da68396d','486b89c025c019b7f2b6c427a437811e','2d865e51c4cf99a5b3a05d17e1d5bce0',
        'c70b931f12e33e65a564d5935d43b2d1','e656ad7a4fb1323db476cd8f2cf6ac39','d8fe113b2a14b80603ca156e2ee0c990',
        'f7481d097c0e4ab799d0a00ec06a5d2c','23ac878010450752bb1b1ca994edb56b','281382daef477e9d9e74d517737aca99',
        'e810bf12eb825d4887a761ada6e0f90b','1b6e9111a71c83930852e93f1aff33e5','7eef81247e37003b22f1fcd6dd678e48',
        '5b97a3bcdc24d7cb1ed70d8609c8d6b2','50e7a9a7b37ec927f6ff3fe6db3b3134','bb8962ac8f2dd3ef51f12bddb04cabde',
        '0d1100deb68ce4cac3662968aa11c15c','cf3a4a8b356b8152ea83e6e7bf96c9e9','00bd6a627c915cc0e49ed59a6a3cc140',
        '15cce20e4302a42e1437f65fdf8fa667','64639cbdf7b7eae9f97e9d3bf7574240','e6aaf4bba882dac7c537bea6eca6c75f',
        '1edfaad0c87c90a26f1fb59fb5cbc983','a22cd96f76784e01bf8f4e0c89433109','64b1cbec58d495ed42b3fbea94cac8e9',
        '22422e4eaca00ea54a0ac3e5fbcb2d8a','1e8bef4991bef4fbdb0ba8791829d8ed','a7fc10fa68ed89100ad8fbced66a0ed7',
        '0080557f0dc278d22c345638b8e7d280','b59f92b67985ed916a40a57bb1cf3342','18a4b0fc76b0cf6a17702443b82feb15',
        '5c4c3e1f4c2d46a9d049112e9ffb5f2c','3d3e397881fa4624f26384c1e69962cf','39226996acb552244bf78dc93c379e57'
     ])
       AND status = 'resolved';

    SELECT COUNT(*) INTO v_merged_count
      FROM bug_intelligence_reports
     WHERE review_status = 'merged'
       AND review_notes LIKE '%2026-04-26 23:01 audit-export%';

    RAISE NOTICE '[20260622] Marked % fingerprint(s) resolved (expected 36 if all rows present).', v_resolved_count;
    RAISE NOTICE '[20260622] Merged % report(s) with audit-export-23:01 paper trail.', v_merged_count;

    IF v_resolved_count < 30 THEN
        RAISE WARNING '[20260622] Expected ≥30 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;

-- ────────────────────────────────────────────────────────────────────
-- Resolves directives (parsed by .github/workflows/bug-intel-resolves-deploy.yml
-- on the next push to main; idempotent — already-resolved fingerprints
-- are skipped by the RPC).
-- ────────────────────────────────────────────────────────────────────
-- Resolves: 7bf1ff4efdac6620edfbda328204ed16 quest insights view missing (crash)
-- Resolves: 64e1ccf7bf450c9d591fab6d80f41847 daily quest int overflow (crash)
-- Resolves: 265848d4ecf46ff84e247d8b572af43b daily quest int overflow (line variant)
-- Resolves: f30626309d8480ec14526323da68396d quest insights view missing (log)
-- Resolves: 486b89c025c019b7f2b6c427a437811e get_daily_quests sig mismatch (23 params)
-- Resolves: 2d865e51c4cf99a5b3a05d17e1d5bce0 daily quest int overflow (medium)
-- Resolves: c70b931f12e33e65a564d5935d43b2d1 daily quest int overflow (log)
-- Resolves: e656ad7a4fb1323db476cd8f2cf6ac39 sig mismatch comprehensive
-- Resolves: d8fe113b2a14b80603ca156e2ee0c990 group challenge nudges schema mismatch
-- Resolves: f7481d097c0e4ab799d0a00ec06a5d2c challenge progress deadlock (ChallengeService)
-- Resolves: 23ac878010450752bb1b1ca994edb56b challenge progress deadlock (log)
-- Resolves: 281382daef477e9d9e74d517737aca99 log_challenge_progress deadlock
-- Resolves: e810bf12eb825d4887a761ada6e0f90b workout_context RLS violation
-- Resolves: 1b6e9111a71c83930852e93f1aff33e5 collaborative_workout_data RLS
-- Resolves: 7eef81247e37003b22f1fcd6dd678e48 equipment_proficiency RLS (Dumbbells)
-- Resolves: 5b97a3bcdc24d7cb1ed70d8609c8d6b2 step_tracking RLS violation
-- Resolves: 50e7a9a7b37ec927f6ff3fe6db3b3134 WorkoutManager cancellation
-- Resolves: bb8962ac8f2dd3ef51f12bddb04cabde challenge HK sync cascade
-- Resolves: 0d1100deb68ce4cac3662968aa11c15c challenge HK sync cascade (product-eng triage)
-- Resolves: cf3a4a8b356b8152ea83e6e7bf96c9e9 WorkoutManager cancellation (no callsite)
-- Resolves: 00bd6a627c915cc0e49ed59a6a3cc140 signup user already registered
-- Resolves: 15cce20e4302a42e1437f65fdf8fa667 signup user already registered (log)
-- Resolves: 64639cbdf7b7eae9f97e9d3bf7574240 USDA food search Unauthorized
-- Resolves: e6aaf4bba882dac7c537bea6eca6c75f USDA cloud search Unauthorized
-- Resolves: 1edfaad0c87c90a26f1fb59fb5cbc983 pwd reset rate limit
-- Resolves: a22cd96f76784e01bf8f4e0c89433109 pwd reset rate limit (variant)
-- Resolves: 64b1cbec58d495ed42b3fbea94cac8e9 Strava 503 (crash)
-- Resolves: 22422e4eaca00ea54a0ac3e5fbcb2d8a auth rate limit account creation
-- Resolves: 1e8bef4991bef4fbdb0ba8791829d8ed pwd reset rate limit (medium)
-- Resolves: a7fc10fa68ed89100ad8fbced66a0ed7 pwd reset rate limit (medium dup)
-- Resolves: 0080557f0dc278d22c345638b8e7d280 pwd reset rate limit (1.32.0)
-- Resolves: b59f92b67985ed916a40a57bb1cf3342 Strava 503 (log)
-- Resolves: 18a4b0fc76b0cf6a17702443b82feb15 insights streak offline (1.37)
-- Resolves: 5c4c3e1f4c2d46a9d049112e9ffb5f2c exercise mapping timeout
-- Resolves: 3d3e397881fa4624f26384c1e69962cf hydration settings offline
-- Resolves: 39226996acb552244bf78dc93c379e57 challenge nudge button wrong screen
