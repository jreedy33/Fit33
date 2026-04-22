-- ============================================================================
-- Bug Intelligence Pipeline (Phase 1): Daily Rollup + Regression Detection
-- Date: 2026-04-27
-- Sprint 8 (Q2-97)
--
-- PURPOSE
-- -------
-- Turn raw dev_session_logs + crash_reports into fingerprinted, daily
-- rolled-up regression signals that a scheduled Claude triage agent (Phase 2)
-- can reason over instead of re-reading raw logs every call.
--
-- ARCHITECTURE
-- ------------
--   dev_session_logs.entries[type=error] --\
--                                           +-> fingerprint (md5)
--   crash_reports (all)                  --/          |
--                                                     v
--                              bug_intelligence_daily_rollup
--                              (fingerprint, day, screen, app_version)
--                                                     |
--                                                     v
--                              bug_intelligence_trends
--                              ('new' | 'regression' signals, append-only)
--
-- SCHEDULING
-- ----------
--   * compute_daily_bug_rollup()  — pg_cron hourly, full recompute of last 5d.
--   * cleanup_bug_intelligence_rollup() — pg_cron daily at 03:30 UTC (retention).
--
-- FORWARD-COMPAT
-- --------------
-- dev_logging_users gains a `cohort` TEXT column (default 'beta'). Today every
-- user is cohort='beta' (TestFlight-era). At GA we can introduce
-- 'production_sampled' / 'internal' / etc. and gate ingest without any schema
-- change — the pipeline reads raw events regardless of cohort, but a future
-- sampler upstream can limit which users write.
--
-- COHORT POLICY
-- -------------
-- This migration:
--   1. Enables dev logging for EVERY existing user_profiles row (user_id
--      inserted with enabled=true, cohort='beta'). This is the user-confirmed
--      policy for TestFlight: all current users OK to track.
--   2. Installs `trg_auto_enroll_dev_logging` so every future signup joins
--      cohort='beta' automatically. At GA, either disable the trigger or
--      change the cohort default to a sampled value.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Forward-compat column on dev_logging_users
-- ============================================================================

ALTER TABLE dev_logging_users
  ADD COLUMN IF NOT EXISTS cohort TEXT NOT NULL DEFAULT 'beta';

CREATE INDEX IF NOT EXISTS idx_dev_logging_users_cohort
  ON dev_logging_users(cohort);

COMMENT ON COLUMN dev_logging_users.cohort IS
  'Logging cohort. Today: all users = ''beta'' (TestFlight). At GA, swap to sampling tiers (production_sampled, internal, etc.) without schema change.';

-- ============================================================================
-- 2. One-shot backfill: enroll every existing user_profiles row
-- ============================================================================

INSERT INTO dev_logging_users (user_id, enabled, enabled_by, cohort)
SELECT up.id, TRUE, 'migration_20260427_bug_intel', 'beta'
FROM user_profiles up
ON CONFLICT (user_id) DO UPDATE
SET
  enabled = TRUE,
  cohort = COALESCE(dev_logging_users.cohort, 'beta'),
  updated_at = now();

-- ============================================================================
-- 3. Auto-enroll future signups via trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_enroll_dev_logging()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO dev_logging_users (user_id, enabled, enabled_by, cohort)
  VALUES (NEW.id, TRUE, 'auto_enroll_trigger', 'beta')
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_enroll_dev_logging ON user_profiles;
CREATE TRIGGER trg_auto_enroll_dev_logging
  AFTER INSERT ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION auto_enroll_dev_logging();

COMMENT ON FUNCTION auto_enroll_dev_logging() IS
  'Auto-adds new signups to dev_logging_users with cohort=beta. At GA swap for a sampled version or drop the trigger.';

-- ============================================================================
-- 4. bug_intelligence_fingerprints — one row per unique error signature
--    Populated by compute_daily_bug_rollup(). Status / assigned_agent /
--    pain_point_id / resolution_* fields are managed by Phase 2 triage + CMS.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bug_intelligence_fingerprints (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fingerprint TEXT NOT NULL UNIQUE,
  source TEXT NOT NULL,                           -- 'log' | 'crash'
  normalized_message TEXT NOT NULL,
  sample_message TEXT NOT NULL,
  error_domain TEXT,

  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  first_seen_app_version TEXT,
  first_seen_build TEXT,
  last_seen_app_version TEXT,
  last_seen_build TEXT,

  occurrence_count INTEGER NOT NULL DEFAULT 0,    -- derived from 5-day window
  unique_user_count INTEGER NOT NULL DEFAULT 0,
  affected_screens TEXT[] NOT NULL DEFAULT '{}',

  -- Phase 2+ fields (writable by triage agent / admin CMS)
  assigned_agent TEXT,                            -- matches ENGINEERING_TEAM.md
  status TEXT NOT NULL DEFAULT 'new',             -- 'new' | 'triaged' | 'in_progress' | 'resolved' | 'wont_fix' | 'duplicate'
  resolution_pr_url TEXT,
  resolved_at TIMESTAMPTZ,
  resolved_commit_sha TEXT,
  pain_point_id TEXT,                             -- 'PP-XXX' from SUPPORT_AGENT.md
  duplicate_of TEXT REFERENCES bug_intelligence_fingerprints(fingerprint),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_status
  ON bug_intelligence_fingerprints(status);
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_assigned
  ON bug_intelligence_fingerprints(assigned_agent);
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_last_seen
  ON bug_intelligence_fingerprints(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_source
  ON bug_intelligence_fingerprints(source);
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_unresolved
  ON bug_intelligence_fingerprints(last_seen_at DESC)
  WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

ALTER TABLE bug_intelligence_fingerprints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages bug fingerprints" ON bug_intelligence_fingerprints;
CREATE POLICY "Service role manages bug fingerprints"
  ON bug_intelligence_fingerprints FOR ALL
  USING (true)
  WITH CHECK (true);

COMMENT ON TABLE bug_intelligence_fingerprints IS
  'De-duplicated bug signatures across logs + crashes. Populated hourly by compute_daily_bug_rollup(). Status / assigned_agent / pain_point_id are managed by Phase 2 triage agent + admin CMS.';

-- ============================================================================
-- 5. bug_intelligence_daily_rollup — per (fingerprint, day, screen, version)
-- ============================================================================

CREATE TABLE IF NOT EXISTS bug_intelligence_daily_rollup (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fingerprint TEXT NOT NULL REFERENCES bug_intelligence_fingerprints(fingerprint) ON DELETE CASCADE,
  day DATE NOT NULL,
  screen TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  occurrence_count INTEGER NOT NULL DEFAULT 0,
  unique_user_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_bug_daily_rollup UNIQUE (fingerprint, day, screen, app_version)
);

CREATE INDEX IF NOT EXISTS idx_bug_rollup_fingerprint_day
  ON bug_intelligence_daily_rollup(fingerprint, day DESC);
CREATE INDEX IF NOT EXISTS idx_bug_rollup_day
  ON bug_intelligence_daily_rollup(day DESC);

ALTER TABLE bug_intelligence_daily_rollup ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Service role manages bug rollup" ON bug_intelligence_daily_rollup;
CREATE POLICY "Service role manages bug rollup"
  ON bug_intelligence_daily_rollup FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- 6. bug_intelligence_trends — regression / new-bug signals (append-only)
--    trend_type: 'new' | 'regression' | 'resolved' ('resolved' reserved for Phase 4)
-- ============================================================================

CREATE TABLE IF NOT EXISTS bug_intelligence_trends (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fingerprint TEXT NOT NULL REFERENCES bug_intelligence_fingerprints(fingerprint) ON DELETE CASCADE,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  trend_type TEXT NOT NULL,
  today_count INTEGER NOT NULL DEFAULT 0,
  baseline_mean NUMERIC,
  spike_ratio NUMERIC,
  affected_users INTEGER NOT NULL DEFAULT 0,
  sample_window TEXT NOT NULL DEFAULT '5d',
  reviewed_at TIMESTAMPTZ,
  reviewed_by TEXT,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_bug_trends_detected
  ON bug_intelligence_trends(detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_trends_fingerprint
  ON bug_intelligence_trends(fingerprint);
CREATE INDEX IF NOT EXISTS idx_bug_trends_unreviewed
  ON bug_intelligence_trends(detected_at DESC) WHERE reviewed_at IS NULL;

ALTER TABLE bug_intelligence_trends ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Service role manages bug trends" ON bug_intelligence_trends;
CREATE POLICY "Service role manages bug trends"
  ON bug_intelligence_trends FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- 7. Helper: bug_intelligence_normalize(text)
--    Masks IDs / numbers so "user abc12345 failed" and "user def67890 failed"
--    share a fingerprint. Mirrors the JS normalizer on the admin CMS
--    (admin-cms/src/app/dev-logs/page.tsx → sharedErrors block).
-- ============================================================================

CREATE OR REPLACE FUNCTION bug_intelligence_normalize(msg TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    regexp_replace(
      regexp_replace(
        COALESCE(msg, ''),
        '\m[0-9a-fA-F]{8,}\M', '<id>', 'g'
      ),
      '\d+(\.\d+)?', '<n>', 'g'
    )
$$;

-- ============================================================================
-- 8. Helper: bug_intelligence_fingerprint(normalized, source, domain)
-- ============================================================================

CREATE OR REPLACE FUNCTION bug_intelligence_fingerprint(
  p_normalized TEXT,
  p_source TEXT,
  p_domain TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT md5(
    COALESCE(p_source, '') || '|' ||
    COALESCE(p_domain, '')  || '|' ||
    COALESCE(p_normalized, '')
  )
$$;

-- ============================================================================
-- 9. Main worker: compute_daily_bug_rollup()
--    Runs via pg_cron every hour. On each run:
--      a) Scans dev_session_logs (type=error entries) last 5 days
--      b) Scans crash_reports last 5 days
--      c) UPSERTs fingerprints (preserves status / assigned_agent / pain_point_id)
--      d) Rewrites the rolling 5-day rollup
--      e) Appends new/regression signals to trends (de-duped per fingerprint per day)
--    Returns a jsonb summary of the run.
-- ============================================================================

CREATE OR REPLACE FUNCTION compute_daily_bug_rollup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start TIMESTAMPTZ := now();
  v_window INTERVAL := INTERVAL '5 days';
  v_today DATE := (now() AT TIME ZONE 'UTC')::DATE;
  v_fp_upserts INTEGER := 0;
  v_rollup_written INTEGER := 0;
  v_new_trends INTEGER := 0;
  v_regression_trends INTEGER := 0;
BEGIN
  -- Temp event stream (logs + crashes, both sources unified).
  CREATE TEMP TABLE IF NOT EXISTS _bug_events_tmp (
    user_id UUID,
    occurred_at TIMESTAMPTZ,
    raw_message TEXT,
    normalized_message TEXT,
    source TEXT,
    error_domain TEXT,
    screen TEXT,
    app_version TEXT,
    build_number TEXT,
    fingerprint TEXT
  ) ON COMMIT DROP;

  DELETE FROM _bug_events_tmp;

  -- 9a) Errors from dev_session_logs (entries is a JSONB array of events).
  INSERT INTO _bug_events_tmp (
    user_id, occurred_at, raw_message, normalized_message,
    source, error_domain, screen, app_version, build_number, fingerprint
  )
  SELECT
    b.user_id,
    to_timestamp(
      COALESCE((entry->>'ts')::BIGINT, EXTRACT(EPOCH FROM b.created_at)::BIGINT * 1000)
      / 1000.0
    ),
    COALESCE(entry->>'detail', ''),
    bug_intelligence_normalize(COALESCE(entry->>'detail', '')),
    'log',
    NULL,
    NULLIF(entry->>'screen', ''),
    NULLIF(b.device_info->>'appVersion', ''),
    NULLIF(b.device_info->>'buildNumber', ''),
    bug_intelligence_fingerprint(
      bug_intelligence_normalize(COALESCE(entry->>'detail', '')),
      'log',
      NULL
    )
  FROM dev_session_logs b,
       jsonb_array_elements(COALESCE(b.entries, '[]'::jsonb)) entry
  WHERE b.created_at >= now() - v_window
    AND entry->>'type' = 'error'
    AND COALESCE(entry->>'detail', '') <> '';

  -- 9b) Crashes.
  INSERT INTO _bug_events_tmp (
    user_id, occurred_at, raw_message, normalized_message,
    source, error_domain, screen, app_version, build_number, fingerprint
  )
  SELECT
    c.user_id,
    COALESCE(c.occurred_at, c.created_at),
    c.error_message,
    bug_intelligence_normalize(c.error_message),
    'crash',
    NULLIF(c.error_domain, ''),
    NULLIF(c.current_screen, ''),
    NULLIF(c.app_version, ''),
    NULLIF(c.build_number, ''),
    bug_intelligence_fingerprint(
      bug_intelligence_normalize(c.error_message),
      'crash',
      NULLIF(c.error_domain, '')
    )
  FROM crash_reports c
  WHERE COALESCE(c.occurred_at, c.created_at) >= now() - v_window
    AND COALESCE(c.error_message, '') <> '';

  -- 9c) UPSERT fingerprints. Preserve admin-managed fields (status / assigned_agent /
  --     pain_point_id / resolution_* / duplicate_of); update counts + seen metadata.
  WITH agg AS (
    SELECT
      e.fingerprint,
      MAX(e.source) AS source,
      MAX(e.normalized_message) AS normalized_message,
      (ARRAY_AGG(e.raw_message ORDER BY e.occurred_at DESC))[1] AS sample_message,
      MAX(e.error_domain) AS error_domain,
      MIN(e.occurred_at) AS first_seen_at,
      MAX(e.occurred_at) AS last_seen_at,
      (ARRAY_AGG(e.app_version ORDER BY e.occurred_at ASC)
         FILTER (WHERE e.app_version IS NOT NULL))[1] AS first_app_version,
      (ARRAY_AGG(e.build_number ORDER BY e.occurred_at ASC)
         FILTER (WHERE e.build_number IS NOT NULL))[1] AS first_build,
      (ARRAY_AGG(e.app_version ORDER BY e.occurred_at DESC)
         FILTER (WHERE e.app_version IS NOT NULL))[1] AS last_app_version,
      (ARRAY_AGG(e.build_number ORDER BY e.occurred_at DESC)
         FILTER (WHERE e.build_number IS NOT NULL))[1] AS last_build,
      COUNT(*)::INT AS occurrence_count,
      COUNT(DISTINCT e.user_id)::INT AS unique_user_count,
      ARRAY_AGG(DISTINCT e.screen) FILTER (WHERE e.screen IS NOT NULL) AS screens
    FROM _bug_events_tmp e
    GROUP BY e.fingerprint
  )
  INSERT INTO bug_intelligence_fingerprints AS f (
    fingerprint, source, normalized_message, sample_message, error_domain,
    first_seen_at, last_seen_at,
    first_seen_app_version, first_seen_build,
    last_seen_app_version, last_seen_build,
    occurrence_count, unique_user_count, affected_screens
  )
  SELECT
    a.fingerprint, a.source, a.normalized_message, a.sample_message, a.error_domain,
    a.first_seen_at, a.last_seen_at,
    a.first_app_version, a.first_build,
    a.last_app_version, a.last_build,
    a.occurrence_count, a.unique_user_count,
    COALESCE(a.screens, '{}')
  FROM agg a
  ON CONFLICT (fingerprint) DO UPDATE
  SET
    first_seen_at = LEAST(f.first_seen_at, EXCLUDED.first_seen_at),
    first_seen_app_version = COALESCE(f.first_seen_app_version, EXCLUDED.first_seen_app_version),
    first_seen_build = COALESCE(f.first_seen_build, EXCLUDED.first_seen_build),
    last_seen_at = GREATEST(f.last_seen_at, EXCLUDED.last_seen_at),
    last_seen_app_version = COALESCE(EXCLUDED.last_seen_app_version, f.last_seen_app_version),
    last_seen_build = COALESCE(EXCLUDED.last_seen_build, f.last_seen_build),
    occurrence_count = EXCLUDED.occurrence_count,
    unique_user_count = EXCLUDED.unique_user_count,
    sample_message = EXCLUDED.sample_message,
    affected_screens = ARRAY(
      SELECT DISTINCT UNNEST(
        COALESCE(f.affected_screens, '{}') || COALESCE(EXCLUDED.affected_screens, '{}')
      )
    ),
    updated_at = now();

  GET DIAGNOSTICS v_fp_upserts = ROW_COUNT;

  -- 9d) Rewrite the rolling 5-day daily rollup.
  DELETE FROM bug_intelligence_daily_rollup
  WHERE day >= v_today - INTERVAL '5 days';

  INSERT INTO bug_intelligence_daily_rollup (
    fingerprint, day, screen, app_version,
    occurrence_count, unique_user_count
  )
  SELECT
    e.fingerprint,
    (e.occurred_at AT TIME ZONE 'UTC')::DATE AS day,
    COALESCE(e.screen, ''),
    COALESCE(e.app_version, ''),
    COUNT(*)::INT,
    COUNT(DISTINCT e.user_id)::INT
  FROM _bug_events_tmp e
  GROUP BY 1, 2, 3, 4;

  GET DIAGNOSTICS v_rollup_written = ROW_COUNT;

  -- 9e) Trend detection: new + regression.
  --   new        : fingerprint's first_seen_at IS today (UTC)  AND today_count >= 3
  --   regression : today_count >= 3 AND today_count > 3 * mean(days 1-4 ago)
  --   Skip if a trend row already exists for that fingerprint+type today.
  --   Skip if the fingerprint is already resolved / wont_fix / duplicate.
  WITH daily_totals AS (
    SELECT
      r.fingerprint,
      r.day,
      SUM(r.occurrence_count)::INT AS n,
      SUM(r.unique_user_count)::INT AS u
    FROM bug_intelligence_daily_rollup r
    WHERE r.day >= v_today - INTERVAL '5 days'
    GROUP BY r.fingerprint, r.day
  ),
  today_vs_baseline AS (
    SELECT
      t.fingerprint,
      MAX(CASE WHEN t.day = v_today THEN t.n ELSE 0 END) AS today_count,
      MAX(CASE WHEN t.day = v_today THEN t.u ELSE 0 END) AS today_users,
      AVG(CASE
            WHEN t.day < v_today AND t.day >= v_today - INTERVAL '4 days'
            THEN t.n
          END) AS baseline_mean
    FROM daily_totals t
    GROUP BY t.fingerprint
  ),
  candidates AS (
    SELECT
      tvb.fingerprint,
      tvb.today_count,
      tvb.today_users,
      tvb.baseline_mean,
      CASE
        WHEN tvb.today_count >= 3
             AND f.first_seen_at >= v_today::TIMESTAMPTZ
          THEN 'new'
        WHEN tvb.today_count >= 3
             AND COALESCE(tvb.baseline_mean, 0) > 0
             AND tvb.today_count > 3 * tvb.baseline_mean
          THEN 'regression'
        ELSE NULL
      END AS trend_type
    FROM today_vs_baseline tvb
    JOIN bug_intelligence_fingerprints f USING (fingerprint)
    WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
  )
  INSERT INTO bug_intelligence_trends (
    fingerprint, trend_type, today_count, baseline_mean,
    spike_ratio, affected_users, sample_window
  )
  SELECT
    c.fingerprint,
    c.trend_type,
    c.today_count,
    c.baseline_mean,
    CASE WHEN COALESCE(c.baseline_mean, 0) > 0
         THEN (c.today_count::NUMERIC / c.baseline_mean)
         ELSE NULL END,
    c.today_users,
    '5d'
  FROM candidates c
  WHERE c.trend_type IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM bug_intelligence_trends t
      WHERE t.fingerprint = c.fingerprint
        AND t.trend_type = c.trend_type
        AND t.detected_at >= v_today::TIMESTAMPTZ
    );

  SELECT
    COUNT(*) FILTER (WHERE trend_type = 'new'),
    COUNT(*) FILTER (WHERE trend_type = 'regression')
  INTO v_new_trends, v_regression_trends
  FROM bug_intelligence_trends
  WHERE detected_at >= v_start;

  RETURN jsonb_build_object(
    'started_at', v_start,
    'completed_at', now(),
    'duration_seconds', EXTRACT(EPOCH FROM (now() - v_start)),
    'fingerprints_upserted', v_fp_upserts,
    'rollup_rows_written', v_rollup_written,
    'new_trend_signals', v_new_trends,
    'regression_trend_signals', v_regression_trends
  );
END;
$$;

GRANT EXECUTE ON FUNCTION compute_daily_bug_rollup() TO service_role;

COMMENT ON FUNCTION compute_daily_bug_rollup() IS
  'Hourly worker (pg_cron): scans dev_session_logs + crash_reports last 5 days, upserts fingerprints, rewrites rollup, emits new/regression trend signals. Returns JSONB run summary.';

-- ============================================================================
-- 10. Retention cleanup (runs daily)
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_bug_intelligence_rollup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rollup_deleted INT;
  v_trends_deleted INT;
BEGIN
  DELETE FROM bug_intelligence_daily_rollup
  WHERE day < (now() AT TIME ZONE 'UTC')::DATE - INTERVAL '30 days';
  GET DIAGNOSTICS v_rollup_deleted = ROW_COUNT;

  DELETE FROM bug_intelligence_trends
  WHERE detected_at < now() - INTERVAL '90 days';
  GET DIAGNOSTICS v_trends_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'rollup_rows_deleted', v_rollup_deleted,
    'trends_rows_deleted', v_trends_deleted
  );
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_bug_intelligence_rollup() TO service_role;

-- ============================================================================
-- 11. pg_cron schedules
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule('bug-intel-compute-rollup')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-compute-rollup');

SELECT cron.schedule(
  'bug-intel-compute-rollup',
  '0 * * * *',
  $$ SELECT compute_daily_bug_rollup(); $$
);

SELECT cron.unschedule('bug-intel-retention-cleanup')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-retention-cleanup');

SELECT cron.schedule(
  'bug-intel-retention-cleanup',
  '30 3 * * *',
  $$ SELECT cleanup_bug_intelligence_rollup(); $$
);

-- ============================================================================
-- 12. Prime the pipeline once (so MIGRATION_INDEX readers see data immediately)
-- ============================================================================

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := compute_daily_bug_rollup();
  RAISE NOTICE 'Initial bug-intel rollup summary: %', v_result;
END $$;

DO $$ BEGIN
  RAISE NOTICE '✅ Phase 1 bug intelligence pipeline installed: dev_logging_users.cohort, bug_intelligence_{fingerprints,daily_rollup,trends} + pg_cron hourly rollup + pg_cron daily retention + auto-enroll trigger.';
END $$;

COMMIT;
