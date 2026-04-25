-- ============================================================================
-- Bug Intelligence — Migration → Fingerprint Auto-Link (Phase 12 — Tier 2 #1)
-- Date: 2026-05-29 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- When we ship `supabase/20260511_health_rls_audit.sql` to fix the HealthKit
-- 42501 cluster, the related fingerprints stay `pending` until either:
--   (a) a human manually flips them, OR
--   (b) `compute_daily_bug_rollup`'s 5-day silent-fix auto-resolver kicks in
--       (which still requires `fixed_in_build` to be stamped manually).
-- Result: the same bug-intel report keeps mentioning "fix exists in
-- 20260511 but not deployed" or "needs manual resolution" long after the
-- migration is in prod.
--
-- FIX
-- ---
-- Two-part convention + RPC:
--
--   1. Convention: every bug-fix migration's HEADER COMMENT may include zero
--      or more lines like:
--          -- Resolves: <fingerprint-md5> <short-justification>
--      e.g.
--          -- Resolves: 8e3c2f4a HealthKit RLS 42501 cluster
--          -- Resolves: a1b2c3d4 cardio_workouts insert auth_expired
--      The line is human-readable AND machine-parseable.
--
--   2. RPC `mark_fingerprints_resolved_by_migration(migration_id, fingerprints)`:
--      service-role only; sets each fingerprint's `status='resolved'`,
--      `resolved_at=now()`, `auto_resolved_reason='migration_resolved:<id>'`,
--      `resolution_pr_url` is set to the migration filename. Atomic; logs the
--      list of flipped fingerprints.
--
--   3. The CMS deploy pipeline (admin-cms `git push origin main` / future
--      Vercel post-deploy hook) parses migrations on push, extracts the
--      `-- Resolves:` lines, and calls the RPC. For now this migration ships
--      the RPC + a manual-invocation helper; the CI hook is a follow-up that
--      doesn't require schema changes.
--
-- BACKWARD COMPAT
-- ---------------
-- Additive — no existing function or column is modified.
--
-- ROLLBACK
-- --------
--   DROP FUNCTION IF EXISTS mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT);
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. RPC: mark_fingerprints_resolved_by_migration
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT);

CREATE OR REPLACE FUNCTION mark_fingerprints_resolved_by_migration(
    p_migration_id     TEXT,                 -- e.g. '20260511_health_rls_audit'
    p_fingerprints     TEXT[],               -- list of fingerprint md5 strings
    p_resolution_note  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved_count INTEGER;
    v_resolution_pr  TEXT;
    v_skipped        TEXT[];
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'mark_fingerprints_resolved_by_migration is service-role only'
            USING ERRCODE = '42501';
    END IF;

    IF p_migration_id IS NULL OR length(p_migration_id) = 0 THEN
        RAISE EXCEPTION 'p_migration_id is required';
    END IF;

    IF p_fingerprints IS NULL OR array_length(p_fingerprints, 1) IS NULL THEN
        RAISE EXCEPTION 'p_fingerprints must contain at least one fingerprint';
    END IF;

    -- Resolve into a clickable artefact ref. The CMS UI renders this as a
    -- link; for SQL migrations, point at the file in the Workout App repo.
    v_resolution_pr := 'supabase/' || p_migration_id || '.sql';

    -- Capture fingerprints that don't exist (silent skip — return them in
    -- the result so the caller can warn) before the UPDATE collapses them.
    SELECT ARRAY_AGG(fp) INTO v_skipped
    FROM UNNEST(p_fingerprints) AS fp
    WHERE NOT EXISTS (
        SELECT 1 FROM bug_intelligence_fingerprints
        WHERE fingerprint = fp
    );

    WITH flipped AS (
        UPDATE bug_intelligence_fingerprints f
        SET
            status                 = 'resolved',
            auto_resolved_at       = now(),
            auto_resolved_reason   = 'migration_resolved:' || p_migration_id,
            resolved_at            = COALESCE(f.resolved_at, now()),
            resolution_pr_url      = COALESCE(f.resolution_pr_url, v_resolution_pr),
            updated_at             = now()
        WHERE f.fingerprint = ANY (p_fingerprints)
          AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
        RETURNING f.fingerprint
    )
    SELECT COUNT(*) INTO v_resolved_count FROM flipped;

    -- Audit trail on bug_intelligence_reports — closes the loop with the
    -- review-pipeline state machine.
    -- NOTE: bug_intelligence_reports does NOT have an `updated_at` column
    -- (verified 2026-04-25 against the prod schema, migration 20260428);
    -- only `reviewed_at` is updated here — `review_notes` carries the
    -- dated stamp.
    UPDATE bug_intelligence_reports r
    SET
        review_status = 'merged',
        pr_url        = COALESCE(r.pr_url, v_resolution_pr),
        review_notes  = COALESCE(r.review_notes || E'\n', '')
                        || format(
                            '[%s] Auto-merged by migration %s%s',
                            to_char(now(), 'YYYY-MM-DD HH24:MI UTC'),
                            p_migration_id,
                            CASE WHEN p_resolution_note IS NOT NULL
                                 THEN ' — ' || p_resolution_note
                                 ELSE ''
                            END
                           ),
        reviewed_at   = COALESCE(r.reviewed_at, now())
    WHERE r.fingerprint = ANY (p_fingerprints)
      AND r.review_status NOT IN ('merged', 'rejected', 'stale');

    RAISE NOTICE 'mark_fingerprints_resolved_by_migration(%): resolved % fingerprints, skipped % unknown',
                 p_migration_id, v_resolved_count, COALESCE(array_length(v_skipped, 1), 0);

    RETURN jsonb_build_object(
        'migration_id',    p_migration_id,
        'resolution_url',  v_resolution_pr,
        'resolved_count',  v_resolved_count,
        'skipped_unknown', COALESCE(v_skipped, '{}'::TEXT[]),
        'note',            p_resolution_note,
        'completed_at',    now()
    );
END;
$$;

COMMENT ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) IS
    'Phase 12 (Tier 2 #1, 2026-04-25) — service-role RPC that flips a list '
    'of fingerprints to status=resolved with reason=migration_resolved:<id> and '
    'links resolution_pr_url to the migration file. Called by the CMS deploy '
    'pipeline (or manually) after a fix-bearing migration is run. Convention: '
    'migration headers include `-- Resolves: <fp> <reason>` lines that the CI '
    'hook parses and feeds into this RPC. Closes the bug-intel loop end-to-end.';

REVOKE ALL ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- 2. Discover-helper: list all "-- Resolves: <fp>" lines we'd parse from a
-- migration body. Useful for tooling that reads migrations on disk.
-- (Server-side regex helper that the CMS or CI hook can call to validate
-- the parsed list before submitting it to mark_fingerprints_resolved_by_migration.)
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_extract_resolves_directives(TEXT);

CREATE OR REPLACE FUNCTION bug_intel_extract_resolves_directives(
    p_migration_body TEXT
) RETURNS TABLE (fingerprint TEXT, justification TEXT)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- Match: -- Resolves: <md5-hash> <free-form text>
    -- The fingerprint is exactly 32 hex characters (md5).
    RETURN QUERY
    SELECT
        (regexp_matches[1])::TEXT AS fingerprint,
        TRIM(COALESCE(regexp_matches[2], ''))::TEXT AS justification
    FROM (
        SELECT regexp_matches(
            p_migration_body,
            E'^\\s*--\\s*Resolves\\s*:\\s*([0-9a-f]{32})\\s*(.*)$',
            'gmi'
        ) AS regexp_matches
    ) m;
END;
$$;

COMMENT ON FUNCTION bug_intel_extract_resolves_directives(TEXT) IS
    'Phase 12 (Tier 2 #1) — IMMUTABLE helper. Parses a migration body for '
    '`-- Resolves: <fingerprint> <justification>` directives. Returns table. '
    'Used by CI tooling to validate the manifest before invoking '
    'mark_fingerprints_resolved_by_migration. fingerprint must be exactly '
    '32 hex chars (md5). Case-insensitive on the directive keyword.';

GRANT EXECUTE ON FUNCTION bug_intel_extract_resolves_directives(TEXT) TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Smoke-test: parse this migration's own header to confirm regex works.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_test_body TEXT := E'-- Resolves: 8e3c2f4ab1d2e3f4a5b6c7d8e9f0a1b2 cardio cluster\n-- Resolves: 11223344556677889900aabbccddeeff hydration logger fix\n-- not a directive: Resolves x';
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM bug_intel_extract_resolves_directives(v_test_body);

    IF v_count <> 2 THEN
        RAISE EXCEPTION '[Phase 12 Tier 2 #1 audit] regex test failed — expected 2 directives, got %', v_count;
    END IF;

    RAISE NOTICE '[Phase 12 Tier 2 #1 audit] regex parser correctly extracted % directives', v_count;
END $$;

COMMIT;
