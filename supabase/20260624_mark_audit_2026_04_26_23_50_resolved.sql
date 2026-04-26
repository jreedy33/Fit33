-- ════════════════════════════════════════════════════════════════════
-- Migration #126 — Mark fingerprints resolved from the
-- bug-intelligence-audit-2026-04-26T23-50-07 export.
-- 2026-04-26
--
-- CONTEXT
-- -------
-- Follow-up audit run minutes after migration #124 (the 23:01 audit
-- close-out) deployed. Total dropped 36 → 6 reports. The 6 residuals
-- are NOT new bugs — they are duplicate triage rows whose md5
-- fingerprints differ from their parents even though
-- `structural_fingerprint` matches. This is the known "collapse missed
-- a sibling" pattern documented in #120's header (R23 `e066c226`).
--
-- Mapping (parent already in terminal status):
--   bb21c7d4… → variant of R13 486b89c0… (daily-quest sig mismatch)
--                 → migration_resolved:20260605+20260607
--   e066c226… → variant of R6  e656ad7a… (sig mismatch comprehensive)
--                 → migration_resolved:20260605+20260607
--   808fa976… → variant of R24 7eef8124… (equipment-proficiency RLS)
--                 → code_fix:auth_uid_alignment+classifier_routing
--   89f70f48… → variant of R24 7eef8124… (same cluster)
--                 → code_fix:auth_uid_alignment+classifier_routing
--   7c2f1276… → variant of R15 f7481d09… (1v1 deadlock)
--                 → migration_resolved:20260618
--   b490d13c… → variant of R15 f7481d09… (same cluster, log)
--                 → migration_resolved:20260618
--
-- WHY THIS WAS PREDICTABLE
-- ------------------------
-- `compute_daily_bug_rollup`'s collapse logic groups by md5
-- (which keys off the normalized message text), not by
-- `structural_fingerprint` (md5 of source||op||error_class). Two log
-- statements that hit the same RPC overload but differ in their
-- parameter-list verbiage will fingerprint differently even though
-- they describe the same root cause. The export's TL;DR says it best:
-- "Collapsed: 29 duplicate triage rows merged into their canonical
-- structural_fingerprint (raw count was 35)."
--
-- A future improvement would be to UNION the canonical-collapse pass
-- with the structural_fingerprint pass and feed the result through
-- `mark_fingerprints_resolved_by_migration` for every sibling md5.
-- For now, hand-flushing these 6 is faster than redesigning the
-- pipeline. Tracked in BUG_INTEL_BACKLOG.md if needed.
--
-- ────────────────────────────────────────────────────────────────────
-- Idempotent: WHERE clauses filter by fingerprint, re-running is a
-- no-op. Wrapped in `BEGIN; … COMMIT;`.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- Bucket 1: migration_resolved:20260605+20260607
--   Daily-quest v3 cluster siblings.
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
    'bb21c7d496f2f08d64e49462958d021b', -- R1 daily quests sig mismatch (23 params variant)
    'e066c226e44877e375bada10bb3cd43e'  -- R6 daily quests sig mismatch (comprehensive variant)
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 2: code_fix:auth_uid_alignment+classifier_routing
--   Equipment-proficiency RLS cluster siblings (Barbell + Cables —
--   same root cause as Dumbbells, just different equipment_type).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status                          = 'resolved',
    auto_resolved_reason            = 'code_fix:auth_uid_alignment+classifier_routing',
    auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
    resolved_at                     = COALESCE(resolved_at, NOW()),
    latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
    latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id, '20260624_mark_audit_2026_04_26_23_50_resolved'),
    updated_at                      = NOW()
WHERE fingerprint IN (
    '808fa976c6e60e9f974fa683f78cca10', -- R2 equipment_proficiency RLS (Barbell)
    '89f70f48b3f67c418f0b2285c6ea5b50'  -- R4 equipment_proficiency RLS (Cables)
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Bucket 3: migration_resolved:20260618
--   1v1 challenge progress deadlock cluster siblings.
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
    '7c2f12761c3c5fb7f53faaa5e956491c', -- R3 group challenge deadlock
    'b490d13c4ffbfb5edcede806c6f1e0e7'  -- R5 group challenge deadlock (log)
)
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ────────────────────────────────────────────────────────────────────
-- Merge any pending bug_intelligence_reports rows for these
-- fingerprints with a paper-trail note (#120 / #124 convention).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-26 23:50 audit-export] '
                    || 'Auto-merged by 20260624_mark_audit_2026_04_26_23_50_resolved.sql — '
                    || 'duplicate triage rows of clusters already resolved by #124.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    'bb21c7d496f2f08d64e49462958d021b',
    'e066c226e44877e375bada10bb3cd43e',
    '808fa976c6e60e9f974fa683f78cca10',
    '89f70f48b3f67c418f0b2285c6ea5b50',
    '7c2f12761c3c5fb7f53faaa5e956491c',
    'b490d13c4ffbfb5edcede806c6f1e0e7'
  );

-- ────────────────────────────────────────────────────────────────────
-- Stamp last_exported_at on any unstamped reports for these
-- fingerprints (mode=all does NOT stamp by default).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET last_exported_at = COALESCE(last_exported_at, NOW())
WHERE r.last_exported_at IS NULL
  AND r.fingerprint IN (
    'bb21c7d496f2f08d64e49462958d021b',
    'e066c226e44877e375bada10bb3cd43e',
    '808fa976c6e60e9f974fa683f78cca10',
    '89f70f48b3f67c418f0b2285c6ea5b50',
    '7c2f12761c3c5fb7f53faaa5e956491c',
    'b490d13c4ffbfb5edcede806c6f1e0e7'
  );

-- ────────────────────────────────────────────────────────────────────
-- Verify — should print 6 fingerprints in terminal status.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
      FROM bug_intelligence_fingerprints
     WHERE fingerprint = ANY(ARRAY[
        'bb21c7d496f2f08d64e49462958d021b',
        'e066c226e44877e375bada10bb3cd43e',
        '808fa976c6e60e9f974fa683f78cca10',
        '89f70f48b3f67c418f0b2285c6ea5b50',
        '7c2f12761c3c5fb7f53faaa5e956491c',
        'b490d13c4ffbfb5edcede806c6f1e0e7'
     ])
       AND status = 'resolved';

    RAISE NOTICE '[20260624] Marked % fingerprint(s) resolved (expected 6 if all rows present).', v_resolved_count;

    IF v_resolved_count < 4 THEN
        RAISE WARNING '[20260624] Expected ≥4 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;

-- ────────────────────────────────────────────────────────────────────
-- Resolves directives — parsed by .github/workflows/bug-intel-resolves-deploy.yml
-- on the next push. This is the first migration shipping AFTER the
-- auto-deploy hook landed; the GitHub Action should call
-- mark_fingerprints_resolved_by_migration('20260624_mark_audit_2026_04_26_23_50_resolved', [...])
-- automatically when this commit pushes to main.
-- ────────────────────────────────────────────────────────────────────
-- Resolves: bb21c7d496f2f08d64e49462958d021b daily quests sig mismatch (23 params variant)
-- Resolves: e066c226e44877e375bada10bb3cd43e daily quests sig mismatch (comprehensive variant)
-- Resolves: 808fa976c6e60e9f974fa683f78cca10 equipment_proficiency RLS (Barbell)
-- Resolves: 89f70f48b3f67c418f0b2285c6ea5b50 equipment_proficiency RLS (Cables)
-- Resolves: 7c2f12761c3c5fb7f53faaa5e956491c group challenge progress deadlock
-- Resolves: b490d13c4ffbfb5edcede806c6f1e0e7 group challenge progress deadlock (log)
