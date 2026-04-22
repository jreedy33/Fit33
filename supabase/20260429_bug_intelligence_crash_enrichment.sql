-- ============================================================================
-- Bug Intelligence Pipeline (Phase 3): Crash Enrichment + Log Correlation
-- Date: 2026-04-29
-- Sprint 8 (Q2-97)
--
-- PURPOSE
-- -------
-- Phase 2 produced 12 Claude reports in the first run but ZERO had a
-- file_path + code_diff, because:
--   1. The triage edge function was feeding crashes without `stack_trace`,
--      `breadcrumbs`, or `session_log_snippet` to Claude.
--   2. Crash <-> log fingerprint correlation required an O(N) in-memory
--      normalization pass (crash_reports.fingerprint is a client-side hash,
--      not the bug_intelligence hash).
--
-- This migration fixes both without touching Phase 1/2 tables:
--   a) Adds a STORED generated column `bi_fingerprint` on crash_reports so
--      the edge function can `WHERE bi_fingerprint = fp.fingerprint` in O(1).
--   b) Adds `fn_backfill_crash_session_snippet()` BEFORE INSERT trigger that
--      pulls the last ~100 relevant log entries (error / screen / tap /
--      warning) from dev_session_logs into `session_log_snippet` when the
--      crash has a session_id. Wrapped in EXCEPTION so a failed enrichment
--      NEVER blocks the crash insert itself.
--   c) One-shot backfill of session_log_snippet for existing crashes.
--
-- DEPENDENCIES
--   Phase 1 helpers: bug_intelligence_normalize(), bug_intelligence_fingerprint(),
--                    bug_intelligence_ensure_array().
--
-- ROLLBACK
--   DROP TRIGGER IF EXISTS trg_crash_session_snippet ON crash_reports;
--   DROP FUNCTION IF EXISTS fn_backfill_crash_session_snippet();
--   DROP INDEX IF EXISTS idx_crash_reports_bi_fingerprint;
--   ALTER TABLE crash_reports DROP COLUMN IF EXISTS bi_fingerprint;
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Generated column: crash_reports.bi_fingerprint
--    STORED = materialized on every INSERT/UPDATE and persisted to disk, so
--    the index is a regular btree. No app-side change required — generated
--    columns are auto-populated.
--    Because bug_intelligence_normalize() and bug_intelligence_fingerprint()
--    are both IMMUTABLE, PG accepts them in a GENERATED expression.
-- ============================================================================

ALTER TABLE crash_reports
  ADD COLUMN IF NOT EXISTS bi_fingerprint TEXT
  GENERATED ALWAYS AS (
    bug_intelligence_fingerprint(
      bug_intelligence_normalize(error_message),
      'crash',
      NULLIF(error_domain, '')
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_crash_reports_bi_fingerprint
  ON crash_reports(bi_fingerprint);

COMMENT ON COLUMN crash_reports.bi_fingerprint IS
  'Bug Intelligence hash (md5 of normalized_message + ''crash'' + error_domain). Joins crash_reports to bug_intelligence_fingerprints. Separate from crash_reports.fingerprint which is a client-side stack-trace hash.';

-- ============================================================================
-- 2. BEFORE INSERT trigger: backfill session_log_snippet
--    The column already exists on crash_reports (see 20260226_crash_reports.sql
--    line 51) but the iOS client doesn't always populate it. When session_id
--    is known we can stitch the last ~100 relevant log entries from
--    dev_session_logs for any crash that happens in-session.
--
--    SAFETY: wrapped in BEGIN/EXCEPTION/END so a failed enrichment never
--    blocks the crash itself from landing. The crash report is more
--    important than the snippet.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_backfill_crash_session_snippet()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snippet TEXT;
BEGIN
  IF NEW.session_id IS NULL OR COALESCE(NEW.session_log_snippet, '') <> '' THEN
    RETURN NEW;
  END IF;

  BEGIN
    WITH recent_entries AS (
      SELECT
        entry->>'type'   AS type,
        entry->>'screen' AS screen,
        entry->>'detail' AS detail,
        COALESCE((entry->>'ts')::BIGINT, 0) AS ts
      FROM dev_session_logs b,
           jsonb_array_elements(bug_intelligence_ensure_array(b.entries)) entry
      WHERE b.session_id = NEW.session_id
        AND entry->>'type' IN ('error', 'screen', 'tap', 'warning', 'api')
        AND b.created_at <= COALESCE(NEW.occurred_at, NEW.created_at) + INTERVAL '5 minutes'
      ORDER BY COALESCE((entry->>'ts')::BIGINT, 0) DESC
      LIMIT 100
    )
    SELECT string_agg(
             format('[%s] %s: %s',
                    type,
                    COALESCE(NULLIF(screen, ''), '-'),
                    COALESCE(NULLIF(detail, ''), '')),
             E'\n'
             ORDER BY ts ASC            -- chronological in the snippet
           )
    INTO v_snippet
    FROM recent_entries;

    IF v_snippet IS NOT NULL THEN
      NEW.session_log_snippet := v_snippet;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Defense: never block a crash insert because enrichment failed.
    RAISE NOTICE 'fn_backfill_crash_session_snippet: enrichment failed for session_id=%: %', NEW.session_id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_backfill_crash_session_snippet() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_backfill_crash_session_snippet() TO service_role;

DROP TRIGGER IF EXISTS trg_crash_session_snippet ON crash_reports;
CREATE TRIGGER trg_crash_session_snippet
  BEFORE INSERT ON crash_reports
  FOR EACH ROW
  EXECUTE FUNCTION fn_backfill_crash_session_snippet();

COMMENT ON TRIGGER trg_crash_session_snippet ON crash_reports IS
  'Backfills session_log_snippet from dev_session_logs when crash has a session_id. Non-fatal (wraps enrichment in BEGIN/EXCEPTION).';

-- ============================================================================
-- 3. One-shot backfill: existing crashes with session_id + empty snippet
--
--    Bounded: only crashes from the last 30 days where we still have the
--    matching log batches (dev_session_logs rolls off). Uses the same
--    query shape as the trigger.
-- ============================================================================

DO $$
DECLARE
  v_updated INTEGER;
BEGIN
  WITH targets AS (
    SELECT c.id, c.session_id, COALESCE(c.occurred_at, c.created_at) AS ref_ts
    FROM crash_reports c
    WHERE c.session_id IS NOT NULL
      AND COALESCE(c.session_log_snippet, '') = ''
      AND c.created_at >= NOW() - INTERVAL '30 days'
  ),
  snippets AS (
    SELECT
      t.id,
      (
        SELECT string_agg(
                 format('[%s] %s: %s',
                        ordered.type,
                        COALESCE(NULLIF(ordered.screen, ''), '-'),
                        COALESCE(NULLIF(ordered.detail, ''), '')),
                 E'\n'
                 ORDER BY ordered.ts ASC
               )
        FROM (
          SELECT
            entry->>'type'   AS type,
            entry->>'screen' AS screen,
            entry->>'detail' AS detail,
            COALESCE((entry->>'ts')::BIGINT, 0) AS ts
          FROM dev_session_logs b,
               jsonb_array_elements(bug_intelligence_ensure_array(b.entries)) entry
          WHERE b.session_id = t.session_id
            AND entry->>'type' IN ('error', 'screen', 'tap', 'warning', 'api')
            AND b.created_at <= t.ref_ts + INTERVAL '5 minutes'
          ORDER BY COALESCE((entry->>'ts')::BIGINT, 0) DESC
          LIMIT 100
        ) ordered
      ) AS snippet
    FROM targets t
  )
  UPDATE crash_reports c
  SET session_log_snippet = s.snippet
  FROM snippets s
  WHERE c.id = s.id
    AND s.snippet IS NOT NULL
    AND s.snippet <> '';

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RAISE NOTICE '✅ session_log_snippet backfilled for % historical crash(es)', v_updated;
END $$;

-- ============================================================================
-- 4. Sanity check + trigger notice
-- ============================================================================

DO $$
DECLARE
  v_crash_count INTEGER;
  v_with_bi_fp INTEGER;
  v_with_snippet INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_crash_count FROM crash_reports;
  SELECT COUNT(*) INTO v_with_bi_fp
    FROM crash_reports WHERE bi_fingerprint IS NOT NULL;
  SELECT COUNT(*) INTO v_with_snippet
    FROM crash_reports WHERE COALESCE(session_log_snippet, '') <> '';

  RAISE NOTICE '✅ crash_reports: % total, % with bi_fingerprint, % with session snippet',
    v_crash_count, v_with_bi_fp, v_with_snippet;
END $$;

COMMIT;
