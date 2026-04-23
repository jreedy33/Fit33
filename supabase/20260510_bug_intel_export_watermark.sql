-- ============================================================================
-- Bug Intelligence — Export Watermark + Auto-Cleanup
-- Date: 2026-05-10 (migration order), authored 2026-04-23
-- Sprint 8 follow-up (Q2-97)
--
-- PROBLEM
-- -------
-- The admin CMS /bug-intelligence "Export for Cursor (.md)" action re-exports
-- every pending report every time. Last night's export and today's were
-- effectively identical — 108 reports each — because nothing tracks which
-- reports have already been handed to Cursor. That makes the .md grow
-- forever and hides genuinely new signals under old, already-triaged work.
--
-- FIX
-- ---
-- Add per-report + per-fingerprint export watermarks:
--   bug_intelligence_reports.last_exported_at / export_count
--   bug_intelligence_fingerprints.last_exported_at
--
-- The admin API's `get_bug_intelligence_export` flips its default to
-- mode='new': only return reports where last_exported_at IS NULL OR the
-- fingerprint has had new activity since the last export (regression
-- after a fix). After a successful export, the API stamps both tables
-- via `mark_bug_reports_exported(UUID[])`.
--
-- Terminal noise ages out via a nightly pg_cron: reports that have been
-- in terminal review states (merged / rejected / stale) for >14 days
-- are deleted, along with orphaned terminal fingerprints that have no
-- remaining open reports. GitHub PR URLs on the Claude report rows have
-- already been archived in PR bodies, so this is non-destructive in the
-- engineering sense.
--
-- This migration is pure additive + backfill-safe. The CMS keeps
-- working without the new columns (it just has no watermark until the
-- first export after deploy).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Columns — idempotent ADD
-- ============================================================================

ALTER TABLE bug_intelligence_reports
  ADD COLUMN IF NOT EXISTS last_exported_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS export_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE bug_intelligence_fingerprints
  ADD COLUMN IF NOT EXISTS last_exported_at TIMESTAMPTZ;

COMMENT ON COLUMN bug_intelligence_reports.last_exported_at IS
  'Set to now() by mark_bug_reports_exported() after a Cursor handoff export. The admin CMS default "Export NEW only" filters on (last_exported_at IS NULL OR fingerprint.last_seen_at > last_exported_at).';
COMMENT ON COLUMN bug_intelligence_reports.export_count IS
  'Increments on every export call that includes this report. Useful for debugging "why does this keep showing up in exports?".';
COMMENT ON COLUMN bug_intelligence_fingerprints.last_exported_at IS
  'Set to now() when any report bound to this fingerprint is included in an export. Used to detect "regression after fix": if fingerprint.last_seen_at > last_exported_at, new occurrences have arrived since we handed it to Cursor.';

-- ============================================================================
-- 2. Partial index for the "NEW since last export" query
--    Hot path: a.review_status IN ('pending','approved') AND last_exported_at IS NULL
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_bug_reports_unexported
  ON bug_intelligence_reports(created_at DESC)
  WHERE last_exported_at IS NULL
    AND review_status IN ('pending', 'approved');

CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_last_exported
  ON bug_intelligence_fingerprints(last_exported_at DESC NULLS FIRST)
  WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ============================================================================
-- 3. mark_bug_reports_exported(p_report_ids UUID[])
--    Called by the admin API after a successful export. Stamps both tables.
--    Service-role only — no IDOR guard needed because there is no user_id
--    parameter and the policy enforces service_role.
-- ============================================================================

DROP FUNCTION IF EXISTS mark_bug_reports_exported(UUID[]);

CREATE OR REPLACE FUNCTION mark_bug_reports_exported(p_report_ids UUID[])
RETURNS TABLE(reports_stamped INT, fingerprints_stamped INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reports_stamped INT := 0;
  v_fps_stamped INT := 0;
  v_fps TEXT[];
BEGIN
  IF p_report_ids IS NULL OR array_length(p_report_ids, 1) IS NULL THEN
    RETURN QUERY SELECT 0, 0;
    RETURN;
  END IF;

  -- Stamp reports + collect the fingerprints we touched.
  WITH upd AS (
    UPDATE bug_intelligence_reports
    SET
      last_exported_at = now(),
      export_count = export_count + 1
    WHERE id = ANY(p_report_ids)
    RETURNING fingerprint
  )
  SELECT COUNT(*)::INT, ARRAY_AGG(DISTINCT fingerprint)
  INTO v_reports_stamped, v_fps
  FROM upd;

  -- Stamp the parent fingerprints in one shot.
  IF v_fps IS NOT NULL AND array_length(v_fps, 1) IS NOT NULL THEN
    UPDATE bug_intelligence_fingerprints
    SET last_exported_at = now()
    WHERE fingerprint = ANY(v_fps);
    GET DIAGNOSTICS v_fps_stamped = ROW_COUNT;
  END IF;

  RETURN QUERY SELECT COALESCE(v_reports_stamped, 0), COALESCE(v_fps_stamped, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION mark_bug_reports_exported(UUID[]) TO service_role;
REVOKE EXECUTE ON FUNCTION mark_bug_reports_exported(UUID[]) FROM anon, authenticated;

COMMENT ON FUNCTION mark_bug_reports_exported(UUID[]) IS
  'Stamps last_exported_at on every provided report id AND their parent fingerprints. Called by the admin CMS API after a successful Cursor-handoff .md export. Service-role only.';

-- ============================================================================
-- 4. cleanup_stale_bug_reports()
--    Deletes terminal reports (merged / rejected / stale) older than 14 days,
--    then deletes any terminal fingerprints (resolved / wont_fix / duplicate)
--    left with zero remaining reports. GitHub PR URLs preserved on the
--    Claude report rows in pr_url archive any fix history externally.
-- ============================================================================

DROP FUNCTION IF EXISTS cleanup_stale_bug_reports();

CREATE OR REPLACE FUNCTION cleanup_stale_bug_reports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reports_deleted INT := 0;
  v_fps_deleted INT := 0;
BEGIN
  -- 1) Delete terminal reports older than 14 days.
  WITH del AS (
    DELETE FROM bug_intelligence_reports
    WHERE review_status IN ('merged', 'rejected', 'stale')
      AND created_at < now() - INTERVAL '14 days'
    RETURNING id
  )
  SELECT COUNT(*)::INT INTO v_reports_deleted FROM del;

  -- 2) Delete terminal fingerprints that have no remaining reports.
  --    (After step 1 + manual triage, these are inbox clutter only.)
  WITH del AS (
    DELETE FROM bug_intelligence_fingerprints f
    WHERE f.status IN ('resolved', 'wont_fix', 'duplicate')
      AND NOT EXISTS (
        SELECT 1 FROM bug_intelligence_reports r
        WHERE r.fingerprint = f.fingerprint
      )
    RETURNING fingerprint
  )
  SELECT COUNT(*)::INT INTO v_fps_deleted FROM del;

  RETURN jsonb_build_object(
    'reports_deleted', v_reports_deleted,
    'fingerprints_deleted', v_fps_deleted,
    'ran_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_stale_bug_reports() TO service_role;
REVOKE EXECUTE ON FUNCTION cleanup_stale_bug_reports() FROM anon, authenticated;

COMMENT ON FUNCTION cleanup_stale_bug_reports() IS
  'Nightly pg_cron: ages out bug_intelligence_reports in terminal review states (merged/rejected/stale) older than 14 days, then drops orphaned terminal fingerprints. Non-destructive — PR URLs preserve fix history in GitHub.';

-- ============================================================================
-- 5. pg_cron schedule — nightly cleanup at 04:15 UTC (after retention cron)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('bug-intel-cleanup-stale')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-cleanup-stale');

SELECT cron.schedule(
  'bug-intel-cleanup-stale',
  '15 4 * * *',
  $$ SELECT cleanup_stale_bug_reports(); $$
);

-- ============================================================================
-- 6. Prime: run once so the MIGRATION_INDEX reader sees an immediate effect
--    on any existing terminal noise >14d old.
-- ============================================================================

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := cleanup_stale_bug_reports();
  RAISE NOTICE 'Initial cleanup_stale_bug_reports: %', v_result;
END $$;

DO $$ BEGIN
  RAISE NOTICE '✅ Bug Intelligence export watermark installed: last_exported_at columns + mark_bug_reports_exported() + nightly cleanup_stale_bug_reports() cron at 04:15 UTC.';
END $$;

COMMIT;
