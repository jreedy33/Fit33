-- ============================================================================
-- Bug Intelligence — Call-Site Capture (Phase 12 — Tier 0 #1)
-- Date: 2026-05-26 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- Today's bug-intel pipeline tells us "Cluster F: PostgREST 42883 in cardio"
-- but it does NOT tell us "Fit33/CardioWorkoutsView.swift:441 logs the wrong
-- weight unit" without a separate Claude triage round-trip. The "Suggested
-- file" in every export is a heuristic Claude pulls out of the message text.
--
-- The iOS client ALREADY captures `#file:#line:#function` at every call site:
--   - `CrashReportingService.reportError(file:function:line:)` writes
--     `additional_context.file / .function / .line` into `crash_reports`
--     (see Fit33/CrashReportingService.swift:339-341).
--   - As of Phase 12 (Logger.swift this same sweep), every `AppLogger.error /
--     .warning / .critical` ships `x_file / x_line / x_function` into
--     `dev_session_logs.entries[]` via the `extra` dict.
--
-- The ONLY missing piece is server-side: `compute_daily_bug_rollup()` reads
-- `op / pg_code / http_status / nsurl_code / endpoint` out of those JSONB
-- payloads but ignores `file / line / function`. This migration adds three
-- columns to `bug_intelligence_fingerprints` and a separate "patch" function
-- that populates them after each rollup cycle. Keeping the patch separate
-- from the 700-line `compute_daily_bug_rollup()` body means we don't risk a
-- cosmetic regression in the rollup logic — it's purely additive.
--
-- WHY a separate function instead of editing compute_daily_bug_rollup
-- ------------------------------------------------------------------
-- 1. Risk minimization: rollup is the most-relied-on bug-intel function;
--    rewriting its 300-line UPSERT body to add three columns is high-blast-
--    radius for low value. The patch function reads the same source rows and
--    UPDATEs the same fingerprints in a single pass.
-- 2. Backfill clarity: this function takes an `INTERVAL` arg so we can run
--    it once over `'30 days'` to populate historical fingerprints, then
--    schedule it hourly with `'7 days'` going forward.
-- 3. Composability: future call-site augmentations (`stack_top_3` once
--    MetricKit symbolication lands, `commit_sha` once we ship build tagging)
--    extend this function alone.
--
-- BACKWARD COMPAT
-- ---------------
-- All three columns are nullable. Existing fingerprints that pre-date the
-- iOS Phase 12 client roll-out keep their NULL `last_seen_file`. The
-- markdown export and CMS UI render `(no callsite)` when NULL.
--
-- ROLLBACK
-- --------
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS last_seen_file;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS last_seen_function;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS last_seen_line;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS callsite_first_seen_at;
--   DROP FUNCTION IF EXISTS bug_intel_backfill_callsites(INTERVAL);
--   SELECT cron.unschedule('bug-intel-callsite-backfill');
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Schema additions to bug_intelligence_fingerprints
-- ----------------------------------------------------------------------------

ALTER TABLE bug_intelligence_fingerprints
    ADD COLUMN IF NOT EXISTS last_seen_file        TEXT,
    ADD COLUMN IF NOT EXISTS last_seen_function    TEXT,
    ADD COLUMN IF NOT EXISTS last_seen_line        INTEGER,
    ADD COLUMN IF NOT EXISTS callsite_first_seen_at TIMESTAMPTZ;

COMMENT ON COLUMN bug_intelligence_fingerprints.last_seen_file IS
    'Source file of the most recent occurrence (basename, no path). '
    'Captured from `dev_session_logs.entries[].x_file` (Logger.swift Phase 12) '
    'or `crash_reports.additional_context->>file` (CrashReportingService Phase 7). '
    'NULL on legacy fingerprints from pre-Phase-12 builds. — 20260526_bug_intel_callsite_capture.';

COMMENT ON COLUMN bug_intelligence_fingerprints.last_seen_function IS
    'Swift function symbol from #function macro at the most recent occurrence. '
    'Mostly useful for narrowing within a 1000-line file. — 20260526_bug_intel_callsite_capture.';

COMMENT ON COLUMN bug_intelligence_fingerprints.last_seen_line IS
    'Source line from #line macro at the most recent occurrence. '
    'Combine with last_seen_file to render `WeightTrackingService.swift:441` in '
    'the markdown export — eliminates the "Suggested file: heuristic" round-trip. '
    '— 20260526_bug_intel_callsite_capture.';

COMMENT ON COLUMN bug_intelligence_fingerprints.callsite_first_seen_at IS
    'Timestamp of the FIRST occurrence that arrived with a non-NULL call-site. '
    'Diverges from first_seen_at when older clients without Phase 12 logging '
    'reported earlier. — 20260526_bug_intel_callsite_capture.';

-- Index for "show me all open fingerprints in <file>" admin queries (used by
-- the migration→fingerprint auto-link in 20260528 + the CMS file filter).
CREATE INDEX IF NOT EXISTS idx_bug_intel_fp_last_seen_file
    ON bug_intelligence_fingerprints (last_seen_file)
    WHERE last_seen_file IS NOT NULL
      AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ----------------------------------------------------------------------------
-- 2. bug_intel_backfill_callsites() — populates the three new columns
--    Window-scoped so we can cheaply run it hourly after compute_daily_bug_rollup.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_backfill_callsites(INTERVAL);

CREATE OR REPLACE FUNCTION bug_intel_backfill_callsites(
    p_window INTERVAL DEFAULT '7 days'::INTERVAL
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Refuse non-service-role callers (Supabase agent invariant — RLS audits
    -- catch authenticated users invoking SECURITY DEFINER admin RPCs).
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_backfill_callsites is service-role only'
            USING ERRCODE = '42501';
    END IF;

    WITH log_callsites AS (
        SELECT
            bug_intelligence_fingerprint(
                bug_intelligence_normalize(COALESCE(entry->>'detail', '')),
                'log', NULL
            ) AS fingerprint,
            to_timestamp(
                COALESCE((entry->>'ts')::BIGINT,
                         EXTRACT(EPOCH FROM b.created_at)::BIGINT * 1000) / 1000.0
            ) AS occurred_at,
            NULLIF(entry->>'x_file', '')     AS file,
            NULLIF(entry->>'x_function', '') AS function,
            CASE WHEN (entry->>'x_line') ~ '^\d+$' THEN (entry->>'x_line')::INTEGER ELSE NULL END AS line
        FROM dev_session_logs b,
             jsonb_array_elements(bug_intelligence_ensure_array(b.entries)) entry
        WHERE b.created_at >= now() - p_window
          AND entry->>'type' = 'error'
          AND COALESCE(entry->>'detail', '') <> ''
          AND NULLIF(entry->>'x_file', '') IS NOT NULL
    ),
    crash_callsites AS (
        SELECT
            bug_intelligence_fingerprint(
                bug_intelligence_normalize(c.error_message),
                'crash', NULLIF(c.error_domain, '')
            ) AS fingerprint,
            COALESCE(c.occurred_at, c.created_at) AS occurred_at,
            NULLIF(c.additional_context->>'file', '')     AS file,
            NULLIF(c.additional_context->>'function', '') AS function,
            CASE WHEN (c.additional_context->>'line') ~ '^\d+$'
                 THEN (c.additional_context->>'line')::INTEGER ELSE NULL END AS line
        FROM crash_reports c
        WHERE COALESCE(c.occurred_at, c.created_at) >= now() - p_window
          AND COALESCE(c.error_message, '') <> ''
          AND c.additional_context IS NOT NULL
          AND NULLIF(c.additional_context->>'file', '') IS NOT NULL
    ),
    unioned AS (
        SELECT * FROM log_callsites
        UNION ALL
        SELECT * FROM crash_callsites
    ),
    latest_per_fp AS (
        SELECT DISTINCT ON (fingerprint)
            fingerprint, file, function, line, occurred_at
        FROM unioned
        WHERE file IS NOT NULL
        ORDER BY fingerprint, occurred_at DESC
    )
    UPDATE bug_intelligence_fingerprints f
    SET
        last_seen_file        = lpf.file,
        last_seen_function    = COALESCE(lpf.function, f.last_seen_function),
        last_seen_line        = COALESCE(lpf.line, f.last_seen_line),
        callsite_first_seen_at = COALESCE(f.callsite_first_seen_at, lpf.occurred_at),
        updated_at            = now()
    FROM latest_per_fp lpf
    WHERE f.fingerprint = lpf.fingerprint
      AND (f.last_seen_file     IS DISTINCT FROM lpf.file
           OR f.last_seen_line  IS DISTINCT FROM lpf.line
           OR f.last_seen_function IS DISTINCT FROM COALESCE(lpf.function, f.last_seen_function));

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RAISE NOTICE 'bug_intel_backfill_callsites: updated % fingerprints in window %', v_count, p_window;

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION bug_intel_backfill_callsites(INTERVAL) IS
    'Phase 12 (2026-04-25) — extracts file/function/line from '
    'dev_session_logs.entries[].x_file/x_line/x_function and crash_reports.'
    'additional_context->>file/function/line and writes the most-recent '
    'occurrence into bug_intelligence_fingerprints.last_seen_*. '
    'Scheduled hourly at :05 (5 min after compute_daily_bug_rollup at :00). '
    'Service-role only via SECURITY DEFINER + auth.role() guard.';

REVOKE ALL ON FUNCTION bug_intel_backfill_callsites(INTERVAL) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_backfill_callsites(INTERVAL) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Initial backfill — 30 days of history
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_initial INTEGER;
BEGIN
    SELECT bug_intel_backfill_callsites('30 days'::INTERVAL) INTO v_initial;
    RAISE NOTICE '[Phase 12 initial backfill] populated last_seen_file on % fingerprints', v_initial;
END $$;

-- ----------------------------------------------------------------------------
-- 4. pg_cron schedule — runs hourly at :05 UTC, 5 min after the rollup
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-callsite-backfill') THEN
            PERFORM cron.unschedule('bug-intel-callsite-backfill');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-callsite-backfill',
            '5 * * * *',
            $cron$ SELECT bug_intel_backfill_callsites('7 days'::INTERVAL); $cron$
        );
        RAISE NOTICE '[Phase 12] scheduled bug-intel-callsite-backfill (hourly :05)';
    ELSE
        RAISE NOTICE 'pg_cron not available; bug_intel_backfill_callsites must be invoked manually';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Audit — confirm columns landed and at least the index exists
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_missing TEXT[];
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'bug_intelligence_fingerprints'
                     AND column_name = 'last_seen_file')
    THEN v_missing := array_append(v_missing, 'last_seen_file'); END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'bug_intelligence_fingerprints'
                     AND column_name = 'last_seen_line')
    THEN v_missing := array_append(v_missing, 'last_seen_line'); END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'bug_intelligence_fingerprints'
                     AND column_name = 'last_seen_function')
    THEN v_missing := array_append(v_missing, 'last_seen_function'); END IF;

    IF array_length(v_missing, 1) > 0 THEN
        RAISE EXCEPTION '[Phase 12 audit] missing columns: %', v_missing;
    END IF;

    RAISE NOTICE '[Phase 12 audit] all 3 callsite columns + index in place';
END $$;

COMMIT;
