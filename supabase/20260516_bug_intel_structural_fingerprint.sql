-- ============================================================================
-- Bug Intelligence — Structural Fingerprints, Noise Filter, Regression Alerts,
-- Auto-Resolve (Sprint 8 Phase 9 / Tier 1 + Tier 2.4)
-- Date: 2026-05-16 (migration order), authored 2026-04-23
--
-- PROBLEM
-- -------
-- Bug-intel today fingerprints on md5(source|domain|normalize(message)).
-- `bug_intelligence_normalize` masks digits and hex-ids, which is better
-- than nothing, but it still splinters root-causes across N fingerprints
-- because the normalized message varies on:
--   - different error prefixes for the same RPC ("Failed to fetch" vs
--     "[INSIGHTS] Failed to fetch streaks")
--   - different localized descriptions for the same NSURLError code
--   - different Postgres HINT / DETAIL bodies for the same SQLSTATE
--
-- The Swift client already ships structural fields on every error log via
-- `DiagnosticContext` (see Fit33/DiagnosticContext.swift + Fit33/Logger.swift
-- lines 100-144). Specifically, on each entry in `dev_session_logs.entries`:
--   entry->>'api_endpoint'   -> DiagnosticContext.endpoint
--   entry->>'api_status'     -> DiagnosticContext.httpStatus
--   entry->>'error'          -> DiagnosticContext.pgCode (Logger.swift:113)
--   entry->>'duration_ms'    -> DiagnosticContext.elapsedMs
--   entry->>'x_op'           -> DiagnosticContext.op (AdvancedSessionLogger
--                                prefixes every extra-dict key with `x_`)
--   entry->>'x_pg_code'
--   entry->>'x_http_status'
--   entry->>'x_retry_attempt'
-- Plus the compact summary is appended to entry->>'detail', so `[op=... pg=...]`
-- also sits in raw text as a belt-and-suspenders fallback.
--
-- FIX
-- ---
-- Five things, one migration, everything idempotent & additive:
--   1. Add `op`, `error_class`, `pg_code`, `http_status`, `nsurl_code`,
--      `endpoint`, `is_classified`, `structural_fingerprint`, `fixed_in_build`,
--      `regressed_after_fix` columns to `bug_intelligence_fingerprints`.
--   2. Add `bug_intel_noise_filter` table — configurable deny-list so we can
--      silence transient classes (op=quests.fetch + nsurl_code=-999) without
--      redeploying the Swift client.
--   3. Rewrite `compute_daily_bug_rollup()` to extract structural fields,
--      apply the noise filter BEFORE fingerprinting, compute
--      `structural_fingerprint` for clean collapse of root-cause siblings.
--   4. Auto-resolve: fingerprints that have been silent for ≥5 days and have
--      a `fixed_in_build` stamp flip to status='resolved' automatically.
--   5. Regression alert: when a fingerprint with `fixed_in_build` sees a
--      `last_seen_build > fixed_in_build`, flip `regressed_after_fix=true` and
--      emit a `bug_intelligence_trends` row with type='regression_after_fix'
--      so the admin CMS can surface it prominently.
--
-- BACKWARD COMPAT
-- ---------------
-- The legacy `fingerprint` column stays the primary key for everything that
-- already references it (`bug_intelligence_daily_rollup.fingerprint`,
-- `bug_intelligence_reports.fingerprint`, `bug_intelligence_trends.fingerprint`,
-- `crash_reports.bi_fingerprint`). We add `structural_fingerprint` as a
-- NULLABLE sibling column — old unstructured errors stay grouped by message,
-- new classifier-routed errors also carry a structural key that the CMS /
-- export layer can group on. Nothing is renamed, nothing cascades.
--
-- ROLLBACK
-- --------
-- This migration is safe to leave in place even if the downstream consumers
-- don't use the new columns yet. Explicit rollback:
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS op;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS error_class;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS pg_code;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS http_status;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS nsurl_code;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS endpoint;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS is_classified;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS structural_fingerprint;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS fixed_in_build;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS regressed_after_fix;
--   DROP TABLE IF EXISTS bug_intel_noise_filter;
--   DROP FUNCTION IF EXISTS bug_intel_classify_error(TEXT, TEXT, INT, INT);
--   DROP FUNCTION IF EXISTS bug_intel_compare_semver(TEXT, TEXT);
--   DROP FUNCTION IF EXISTS bug_intel_extract_nsurl_code(TEXT);
--   -- then re-install the pre-20260516 compute_daily_bug_rollup() body from
--   -- supabase/20260427_bug_intelligence.sql (it is the canonical prior version).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Structural columns on bug_intelligence_fingerprints (idempotent)
-- ============================================================================

ALTER TABLE bug_intelligence_fingerprints
  ADD COLUMN IF NOT EXISTS op TEXT,
  ADD COLUMN IF NOT EXISTS error_class TEXT,
  ADD COLUMN IF NOT EXISTS pg_code TEXT,
  ADD COLUMN IF NOT EXISTS http_status INT,
  ADD COLUMN IF NOT EXISTS nsurl_code INT,
  ADD COLUMN IF NOT EXISTS endpoint TEXT,
  ADD COLUMN IF NOT EXISTS is_classified BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS structural_fingerprint TEXT,
  ADD COLUMN IF NOT EXISTS fixed_in_build TEXT,
  ADD COLUMN IF NOT EXISTS regressed_after_fix BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_resolved_at TIMESTAMPTZ;

COMMENT ON COLUMN bug_intelligence_fingerprints.op IS
  'Signpost operation from DiagnosticContext.op (e.g. "quests.fetch", "challenges.log_private_progress"). Populated by compute_daily_bug_rollup from entry->>''x_op''. NULL for pre-classifier logs.';
COMMENT ON COLUMN bug_intelligence_fingerprints.error_class IS
  'Compact root-cause class: pg:23505, http:401, nsurl:-999, auth:expired, cancelled, offline, rls:42501, unknown. Computed by bug_intel_classify_error(). Use for "3 fingerprints, same class" collapse.';
COMMENT ON COLUMN bug_intelligence_fingerprints.pg_code IS 'PostgreSQL SQLSTATE code (entry->>''error'' or entry->>''x_pg_code'').';
COMMENT ON COLUMN bug_intelligence_fingerprints.http_status IS 'HTTP status code from PostgREST / Edge function (entry->>''api_status'').';
COMMENT ON COLUMN bug_intelligence_fingerprints.nsurl_code IS 'NSURLError code extracted from message or entry->>''x_nsurl_code''. Negative for Foundation errors (-999=cancelled, -1005=connection lost, -1009=offline).';
COMMENT ON COLUMN bug_intelligence_fingerprints.endpoint IS 'Most common endpoint (entry->>''api_endpoint'') seen for this fingerprint.';
COMMENT ON COLUMN bug_intelligence_fingerprints.is_classified IS 'TRUE when at least one event carried DiagnosticContext (op is non-null). FALSE for legacy AppLogger.error calls that bypassed NetworkErrorClassifier — those are the ones QUALITY_PERFORMANCE_AGENT invariant 25a forbids.';
COMMENT ON COLUMN bug_intelligence_fingerprints.structural_fingerprint IS 'md5(source || op || error_class). NULLable. Siblings with the same structural_fingerprint are the same root cause — admin CMS uses this to collapse duplicate reports.';
COMMENT ON COLUMN bug_intelligence_fingerprints.fixed_in_build IS 'Build number stamped when a resolution PR ships. Set by admin CMS Phase 8 triage flow. compute_daily_bug_rollup() compares last_seen_build against this to flip regressed_after_fix.';
COMMENT ON COLUMN bug_intelligence_fingerprints.regressed_after_fix IS 'TRUE when last_seen_build > fixed_in_build. Auto-flipped by the rollup + emits a trend signal for admin dashboard.';
COMMENT ON COLUMN bug_intelligence_fingerprints.auto_resolved_at IS 'Set by compute_daily_bug_rollup() when fingerprint has been silent ≥5 days AND has a fixed_in_build stamp. Complements status=''resolved''.';

CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_structural
  ON bug_intelligence_fingerprints(structural_fingerprint)
  WHERE structural_fingerprint IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_op
  ON bug_intelligence_fingerprints(op)
  WHERE op IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_error_class
  ON bug_intelligence_fingerprints(error_class)
  WHERE error_class IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_regressed
  ON bug_intelligence_fingerprints(last_seen_at DESC)
  WHERE regressed_after_fix = TRUE;
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_unclassified
  ON bug_intelligence_fingerprints(last_seen_at DESC)
  WHERE is_classified = FALSE
    AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ============================================================================
-- 2. bug_intel_noise_filter — server-side deny list
--
--    Rows here cause compute_daily_bug_rollup() to DROP matching events
--    before they fingerprint. Two tiers:
--      tier='hard' — event is dropped entirely (counts as if it never fired)
--      tier='soft' — event is kept for raw queries but excluded from trends
--                    + visible via the admin CMS "Include noise" toggle
--
--    Match precedence (all optional; an empty filter row is ignored):
--      op IS NULL OR entry op = filter op
--      pg_code IS NULL OR entry pg_code = filter pg_code
--      nsurl_code IS NULL OR entry nsurl_code = filter nsurl_code
--      message_pattern IS NULL OR entry detail ~ filter message_pattern
--
--    Seeds mirror the QUALITY_PERFORMANCE_AGENT invariant 25/25a list and
--    CrashReportingService.reportError hardcoded drops (Fit33/CrashReportingService.swift:262-272).
-- ============================================================================

CREATE TABLE IF NOT EXISTS bug_intel_noise_filter (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  op TEXT,
  pg_code TEXT,
  nsurl_code INT,
  http_status INT,
  message_pattern TEXT,
  tier TEXT NOT NULL DEFAULT 'hard' CHECK (tier IN ('hard', 'soft')),
  rationale TEXT NOT NULL,
  created_by TEXT NOT NULL DEFAULT 'migration_20260516',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_noise_filter_tier ON bug_intel_noise_filter(tier);

ALTER TABLE bug_intel_noise_filter ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Service role manages bug_intel_noise_filter" ON bug_intel_noise_filter;
CREATE POLICY "Service role manages bug_intel_noise_filter"
  ON bug_intel_noise_filter FOR ALL
  USING (true) WITH CHECK (true);

COMMENT ON TABLE bug_intel_noise_filter IS
  'Server-side deny list for compute_daily_bug_rollup. Matches raw events by op/pg_code/nsurl_code/http_status/message_pattern and drops (tier=hard) or flags (tier=soft) them before fingerprinting. Managed via admin CMS Phase 9.';

-- Seed known-transient classes. All QP invariant 25a — these are expected
-- operational states, not bugs, so they must never create a fingerprint.
-- (Matches the Swift-side drops in CrashReportingService.reportError lines
-- 262-272 + Logger.swift minimum level gate at line 132.)
INSERT INTO bug_intel_noise_filter (name, nsurl_code, tier, rationale) VALUES
  ('nsurl_cancelled_tab_switch', -999, 'hard',
   'NSURLError -999 (cancelled) — Dashboard .task cancellation on tab switch. Never a bug. Swift CrashReportingService drops these; this row closes the server-side loop for pre-fix logs.'),
  ('nsurl_connection_lost', -1005, 'hard',
   'NSURLError -1005 (network connection lost) — transient network. Classifier routes to .warning. Retry queue handles recovery.'),
  ('nsurl_offline', -1009, 'hard',
   'NSURLError -1009 (not connected to internet) — offline. Classifier routes to .warning. Retry queue handles recovery.'),
  ('nsurl_timeout_short', -1001, 'soft',
   'NSURLError -1001 (timeout) — kept as soft signal so we can spot regressions in specific ops, but excluded from default trend detection.')
ON CONFLICT (name) DO NOTHING;

-- Note: `ON CONFLICT DO NOTHING` is benign on first deploy (no PK conflict
-- possible because `id` defaults to gen_random_uuid()). It exists so the
-- re-run of this migration during backfills is a no-op instead of crashing
-- on a unique-violation we don't actually have.

-- ============================================================================
-- 3. Helper: bug_intel_extract_nsurl_code(text)
--    Pulls the first "NSURLError" integer out of a raw message.
-- ============================================================================

CREATE OR REPLACE FUNCTION bug_intel_extract_nsurl_code(msg TEXT)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN msg IS NULL THEN NULL
    WHEN msg ~ 'NSURLError(Domain)? error -?[0-9]+' THEN
      NULLIF(substring(msg FROM 'NSURLError(?:Domain)? error (-?[0-9]+)'), '')::INT
    ELSE NULL
  END
$$;

COMMENT ON FUNCTION bug_intel_extract_nsurl_code(TEXT) IS
  'Best-effort extract of NSURLError code from a raw error message. Fallback for pre-DiagnosticContext logs that surface Foundation errors as text only.';

-- ============================================================================
-- 4. Helper: bug_intel_classify_error(pg_code, http_status, nsurl_code, message)
--    Returns a short error_class tag. Precedence: pg > http > nsurl > message
-- ============================================================================

CREATE OR REPLACE FUNCTION bug_intel_classify_error(
  p_pg_code TEXT,
  p_http_status INT,
  p_nsurl_code INT,
  p_message TEXT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_pg_code IS NOT NULL AND p_pg_code <> '' THEN
    RETURN 'pg:' || p_pg_code;
  END IF;
  IF p_http_status IS NOT NULL AND p_http_status > 0 THEN
    RETURN 'http:' || p_http_status;
  END IF;
  IF p_nsurl_code IS NOT NULL THEN
    RETURN 'nsurl:' || p_nsurl_code;
  END IF;
  IF p_message IS NULL OR p_message = '' THEN
    RETURN 'unknown';
  END IF;
  IF p_message ILIKE '%jwt expired%' OR p_message ILIKE '%invalid jwt%' THEN RETURN 'auth:expired'; END IF;
  IF p_message ILIKE '%cancelled%' OR p_message LIKE '%-999%' THEN RETURN 'cancelled'; END IF;
  IF p_message ILIKE '%not connected to the internet%' OR p_message LIKE '%-1009%' THEN RETURN 'offline'; END IF;
  IF p_message ILIKE '%network connection was lost%' OR p_message LIKE '%-1005%' THEN RETURN 'network_lost'; END IF;
  IF p_message ILIKE '%timeout%' OR p_message LIKE '%-1001%' THEN RETURN 'timeout'; END IF;
  IF p_message ILIKE '%row-level security%' OR p_message ILIKE '%permission denied%' THEN RETURN 'rls'; END IF;
  IF p_message ILIKE '%duplicate key%' THEN RETURN 'pg:23505'; END IF;
  IF p_message ILIKE '%violates check constraint%' THEN RETURN 'pg:23514'; END IF;
  IF p_message ILIKE '%uuid = text%' OR p_message ILIKE '%operator does not exist%' THEN RETURN 'pg:42883'; END IF;
  IF p_message ILIKE '%could not find the function%' OR p_message ILIKE '%PGRST202%' THEN RETURN 'pgrest:202'; END IF;
  RETURN 'unknown';
END;
$$;

-- ============================================================================
-- 5. Helper: bug_intel_compare_semver(newer, older) -> 1 | 0 | -1
--    Parses "1.2.3" / "2026.04.23" build strings. Falls back to lexical compare
--    if either side isn't numeric dotted.
-- ============================================================================

CREATE OR REPLACE FUNCTION bug_intel_compare_semver(v_newer TEXT, v_older TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  a_parts INT[];
  b_parts INT[];
  i INT;
  a INT;
  b INT;
BEGIN
  IF v_newer IS NULL OR v_older IS NULL THEN RETURN 0; END IF;
  IF v_newer = v_older THEN RETURN 0; END IF;

  BEGIN
    a_parts := string_to_array(regexp_replace(v_newer, '[^0-9.]', '', 'g'), '.')::INT[];
    b_parts := string_to_array(regexp_replace(v_older, '[^0-9.]', '', 'g'), '.')::INT[];
  EXCEPTION WHEN OTHERS THEN
    -- Fall back to lexical compare on parse failure.
    RETURN CASE WHEN v_newer > v_older THEN 1
                WHEN v_newer < v_older THEN -1 ELSE 0 END;
  END;

  FOR i IN 1..GREATEST(array_length(a_parts, 1), array_length(b_parts, 1)) LOOP
    a := COALESCE(a_parts[i], 0);
    b := COALESCE(b_parts[i], 0);
    IF a > b THEN RETURN 1; END IF;
    IF a < b THEN RETURN -1; END IF;
  END LOOP;
  RETURN 0;
END;
$$;

-- ============================================================================
-- 6. Rewrite compute_daily_bug_rollup() with structural extraction + noise
--    filter + regression flag + auto-resolve.
--
--    This is a full drop-in replacement of the function body from
--    supabase/20260427_bug_intelligence.sql (section 9). Behavior differences:
--      (a) _bug_events_tmp carries 5 new columns: op, pg_code, http_status,
--          nsurl_code, is_classified, endpoint.
--      (b) Events matching bug_intel_noise_filter(tier='hard') are dropped
--          before fingerprinting (INSERT...WHERE NOT EXISTS).
--      (c) Fingerprint UPSERT also sets op/error_class/pg_code/http_status/
--          nsurl_code/endpoint/is_classified/structural_fingerprint. Preserves
--          admin-managed fields (status, assigned_agent, fixed_in_build, etc.)
--          via ON CONFLICT DO UPDATE.
--      (d) Regression detection: on UPSERT, if last_seen_build stamped above
--          fixed_in_build per bug_intel_compare_semver, flip
--          regressed_after_fix=TRUE and emit trend type='regression_after_fix'.
--      (e) Auto-resolve: single UPDATE pass at the end flips silent+fixed
--          fingerprints to status='resolved', auto_resolved_at=now().
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
  v_regressed_after_fix INTEGER := 0;
  v_auto_resolved INTEGER := 0;
  v_noise_dropped INTEGER := 0;
BEGIN
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
    fingerprint TEXT,
    op TEXT,
    error_class TEXT,
    pg_code TEXT,
    http_status INT,
    nsurl_code INT,
    endpoint TEXT,
    is_classified BOOLEAN,
    structural_fingerprint TEXT
  ) ON COMMIT DROP;

  DELETE FROM _bug_events_tmp;

  -- 6a) Errors from dev_session_logs (entries is a JSONB array of events).
  INSERT INTO _bug_events_tmp (
    user_id, occurred_at, raw_message, normalized_message,
    source, error_domain, screen, app_version, build_number, fingerprint,
    op, error_class, pg_code, http_status, nsurl_code, endpoint,
    is_classified, structural_fingerprint
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
    ),
    -- Structural extraction from DiagnosticContext (see Fit33/Logger.swift:106-116).
    NULLIF(entry->>'x_op', ''),
    NULL, -- error_class filled below from pg/http/nsurl/message
    COALESCE(NULLIF(entry->>'x_pg_code', ''), NULLIF(entry->>'error', '')),
    -- api_status is from DiagnosticContext.httpStatus (Logger.swift:111).
    -- x_http_status is the same value reflected via extra dict; prefer the
    -- first-class field.
    CASE
      WHEN (entry->>'api_status') ~ '^\d+$' THEN (entry->>'api_status')::INT
      WHEN (entry->>'x_http_status') ~ '^\d+$' THEN (entry->>'x_http_status')::INT
      ELSE NULL
    END,
    -- NSURL extraction: try x_nsurl_code first (future client support), fall
    -- back to regex over raw message (today's clients don't ship it explicitly).
    COALESCE(
      CASE WHEN (entry->>'x_nsurl_code') ~ '^-?\d+$' THEN (entry->>'x_nsurl_code')::INT ELSE NULL END,
      bug_intel_extract_nsurl_code(COALESCE(entry->>'detail', ''))
    ),
    NULLIF(entry->>'api_endpoint', ''),
    (entry->>'x_op') IS NOT NULL AND (entry->>'x_op') <> '',
    NULL -- structural_fingerprint computed below
  FROM dev_session_logs b,
       jsonb_array_elements(bug_intelligence_ensure_array(b.entries)) entry
  WHERE b.created_at >= now() - v_window
    AND entry->>'type' = 'error'
    AND COALESCE(entry->>'detail', '') <> '';

  -- 6b) Crashes.
  INSERT INTO _bug_events_tmp (
    user_id, occurred_at, raw_message, normalized_message,
    source, error_domain, screen, app_version, build_number, fingerprint,
    op, error_class, pg_code, http_status, nsurl_code, endpoint,
    is_classified, structural_fingerprint
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
    ),
    NULL, -- crash_reports doesn't carry op today; future: add column
    NULL,
    NULLIF(c.error_code, ''),
    NULL,
    bug_intel_extract_nsurl_code(c.error_message),
    NULL,
    FALSE, -- crashes are pre-classifier by definition
    NULL
  FROM crash_reports c
  WHERE COALESCE(c.occurred_at, c.created_at) >= now() - v_window
    AND COALESCE(c.error_message, '') <> '';

  -- 6c) Derive error_class + structural_fingerprint now that source columns
  -- are populated. Two-pass keeps the extraction readable.
  UPDATE _bug_events_tmp
  SET error_class = bug_intel_classify_error(pg_code, http_status, nsurl_code, raw_message);

  UPDATE _bug_events_tmp
  SET structural_fingerprint =
    CASE
      WHEN op IS NOT NULL AND error_class <> 'unknown' THEN
        md5(source || '|' || op || '|' || error_class)
      WHEN op IS NULL AND error_class NOT IN ('unknown', '') THEN
        -- Still useful when op is missing: group by (source, error_class, normalized domain-ish token).
        md5(source || '|' || COALESCE(NULLIF(endpoint, ''), error_domain, '') || '|' || error_class)
      ELSE NULL
    END;

  -- 6d) Apply NOISE FILTER (tier='hard'). Delete matching rows from _bug_events_tmp.
  WITH noise AS (
    DELETE FROM _bug_events_tmp e
    USING bug_intel_noise_filter f
    WHERE f.tier = 'hard'
      AND (f.op IS NULL OR e.op IS NOT DISTINCT FROM f.op)
      AND (f.pg_code IS NULL OR e.pg_code IS NOT DISTINCT FROM f.pg_code)
      AND (f.nsurl_code IS NULL OR e.nsurl_code IS NOT DISTINCT FROM f.nsurl_code)
      AND (f.http_status IS NULL OR e.http_status IS NOT DISTINCT FROM f.http_status)
      AND (f.message_pattern IS NULL OR e.raw_message ~ f.message_pattern)
      AND NOT (f.op IS NULL AND f.pg_code IS NULL AND f.nsurl_code IS NULL
               AND f.http_status IS NULL AND f.message_pattern IS NULL)
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_noise_dropped FROM noise;

  -- 6e) UPSERT fingerprints. Preserve admin-managed fields + compute
  -- regressed_after_fix on the fly.
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
      ARRAY_AGG(DISTINCT e.screen) FILTER (WHERE e.screen IS NOT NULL) AS screens,
      (MODE() WITHIN GROUP (ORDER BY e.op) FILTER (WHERE e.op IS NOT NULL)) AS op,
      (MODE() WITHIN GROUP (ORDER BY e.error_class) FILTER (WHERE e.error_class IS NOT NULL)) AS error_class,
      (MODE() WITHIN GROUP (ORDER BY e.pg_code) FILTER (WHERE e.pg_code IS NOT NULL)) AS pg_code,
      (MODE() WITHIN GROUP (ORDER BY e.http_status) FILTER (WHERE e.http_status IS NOT NULL)) AS http_status,
      (MODE() WITHIN GROUP (ORDER BY e.nsurl_code) FILTER (WHERE e.nsurl_code IS NOT NULL)) AS nsurl_code,
      (MODE() WITHIN GROUP (ORDER BY e.endpoint) FILTER (WHERE e.endpoint IS NOT NULL)) AS endpoint,
      BOOL_OR(e.is_classified) AS is_classified,
      (MODE() WITHIN GROUP (ORDER BY e.structural_fingerprint) FILTER (WHERE e.structural_fingerprint IS NOT NULL)) AS structural_fingerprint
    FROM _bug_events_tmp e
    GROUP BY e.fingerprint
  )
  INSERT INTO bug_intelligence_fingerprints AS f (
    fingerprint, source, normalized_message, sample_message, error_domain,
    first_seen_at, last_seen_at,
    first_seen_app_version, first_seen_build,
    last_seen_app_version, last_seen_build,
    occurrence_count, unique_user_count, affected_screens,
    op, error_class, pg_code, http_status, nsurl_code, endpoint,
    is_classified, structural_fingerprint
  )
  SELECT
    a.fingerprint, a.source, a.normalized_message, a.sample_message, a.error_domain,
    a.first_seen_at, a.last_seen_at,
    a.first_app_version, a.first_build,
    a.last_app_version, a.last_build,
    a.occurrence_count, a.unique_user_count,
    COALESCE(a.screens, '{}'),
    a.op, a.error_class, a.pg_code, a.http_status, a.nsurl_code, a.endpoint,
    COALESCE(a.is_classified, FALSE), a.structural_fingerprint
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
    op = COALESCE(EXCLUDED.op, f.op),
    error_class = COALESCE(EXCLUDED.error_class, f.error_class),
    pg_code = COALESCE(EXCLUDED.pg_code, f.pg_code),
    http_status = COALESCE(EXCLUDED.http_status, f.http_status),
    nsurl_code = COALESCE(EXCLUDED.nsurl_code, f.nsurl_code),
    endpoint = COALESCE(EXCLUDED.endpoint, f.endpoint),
    is_classified = f.is_classified OR EXCLUDED.is_classified,
    structural_fingerprint = COALESCE(EXCLUDED.structural_fingerprint, f.structural_fingerprint),
    -- Flip regressed_after_fix when new activity arrives on a build > fixed_in_build.
    regressed_after_fix = (
      f.regressed_after_fix
      OR (
        f.fixed_in_build IS NOT NULL
        AND EXCLUDED.last_seen_build IS NOT NULL
        AND bug_intel_compare_semver(EXCLUDED.last_seen_build, f.fixed_in_build) > 0
      )
    ),
    -- Clear auto_resolved_at on new activity (can't be "silent" anymore).
    auto_resolved_at = CASE
      WHEN EXCLUDED.last_seen_at > f.last_seen_at THEN NULL
      ELSE f.auto_resolved_at
    END,
    updated_at = now();

  GET DIAGNOSTICS v_fp_upserts = ROW_COUNT;

  -- 6f) Regression-after-fix trends (one per fingerprint per day, de-duped).
  INSERT INTO bug_intelligence_trends (
    fingerprint, trend_type, today_count, affected_users, sample_window
  )
  SELECT
    f.fingerprint,
    'regression_after_fix',
    f.occurrence_count,
    f.unique_user_count,
    '5d'
  FROM bug_intelligence_fingerprints f
  WHERE f.regressed_after_fix = TRUE
    AND f.last_seen_at >= v_today::TIMESTAMPTZ
    AND NOT EXISTS (
      SELECT 1 FROM bug_intelligence_trends t
      WHERE t.fingerprint = f.fingerprint
        AND t.trend_type = 'regression_after_fix'
        AND t.detected_at >= v_today::TIMESTAMPTZ
    );

  GET DIAGNOSTICS v_regressed_after_fix = ROW_COUNT;

  -- 6g) Rewrite the rolling 5-day daily rollup (unchanged from Phase 1).
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

  -- 6h) Trend detection: new + regression (unchanged from Phase 1).
  WITH daily_totals AS (
    SELECT r.fingerprint, r.day,
      SUM(r.occurrence_count)::INT AS n,
      SUM(r.unique_user_count)::INT AS u
    FROM bug_intelligence_daily_rollup r
    WHERE r.day >= v_today - INTERVAL '5 days'
    GROUP BY r.fingerprint, r.day
  ),
  today_vs_baseline AS (
    SELECT t.fingerprint,
      MAX(CASE WHEN t.day = v_today THEN t.n ELSE 0 END) AS today_count,
      MAX(CASE WHEN t.day = v_today THEN t.u ELSE 0 END) AS today_users,
      AVG(CASE WHEN t.day < v_today AND t.day >= v_today - INTERVAL '4 days' THEN t.n END) AS baseline_mean
    FROM daily_totals t
    GROUP BY t.fingerprint
  ),
  candidates AS (
    SELECT tvb.fingerprint, tvb.today_count, tvb.today_users, tvb.baseline_mean,
      CASE
        WHEN tvb.today_count >= 3 AND f.first_seen_at >= v_today::TIMESTAMPTZ THEN 'new'
        WHEN tvb.today_count >= 3 AND COALESCE(tvb.baseline_mean, 0) > 0
             AND tvb.today_count > 3 * tvb.baseline_mean THEN 'regression'
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
  SELECT c.fingerprint, c.trend_type, c.today_count, c.baseline_mean,
    CASE WHEN COALESCE(c.baseline_mean, 0) > 0 THEN (c.today_count::NUMERIC / c.baseline_mean) ELSE NULL END,
    c.today_users, '5d'
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

  -- 6i) Auto-resolve quiet+fixed fingerprints (Tier 2.4).
  -- Criteria: fixed_in_build stamped, status is still open, last_seen_at is
  -- ≥5 days old, regressed_after_fix is FALSE. Flip to status='resolved'.
  UPDATE bug_intelligence_fingerprints
  SET
    status = 'resolved',
    auto_resolved_at = now(),
    resolved_at = COALESCE(resolved_at, now()),
    updated_at = now()
  WHERE fixed_in_build IS NOT NULL
    AND regressed_after_fix = FALSE
    AND status NOT IN ('resolved', 'wont_fix', 'duplicate')
    AND last_seen_at < now() - INTERVAL '5 days'
    AND auto_resolved_at IS NULL;

  GET DIAGNOSTICS v_auto_resolved = ROW_COUNT;

  RETURN jsonb_build_object(
    'started_at', v_start,
    'completed_at', now(),
    'duration_seconds', EXTRACT(EPOCH FROM (now() - v_start)),
    'fingerprints_upserted', v_fp_upserts,
    'rollup_rows_written', v_rollup_written,
    'new_trend_signals', v_new_trends,
    'regression_trend_signals', v_regression_trends,
    'regressed_after_fix_signals', v_regressed_after_fix,
    'auto_resolved', v_auto_resolved,
    'noise_events_dropped', v_noise_dropped
  );
END;
$$;

GRANT EXECUTE ON FUNCTION compute_daily_bug_rollup() TO service_role;

COMMENT ON FUNCTION compute_daily_bug_rollup() IS
  'Hourly rollup (pg_cron): scans dev_session_logs + crash_reports, applies bug_intel_noise_filter, extracts DiagnosticContext structural fields, upserts fingerprints with op/error_class/pg/http/nsurl/endpoint/is_classified/structural_fingerprint, flips regressed_after_fix on post-fix activity, auto-resolves silent+fixed fingerprints. Phase 9 / 2026-05-16.';

-- ============================================================================
-- 7. Backfill: populate structural columns on existing fingerprints from
--    the sample_message + error_domain we already have. Best-effort — rows
--    without enough context stay with NULL op/pg_code and is_classified=FALSE
--    (which correctly signals "this slipped past the classifier gate").
-- ============================================================================

UPDATE bug_intelligence_fingerprints
SET
  error_class = COALESCE(
    error_class,
    bug_intel_classify_error(pg_code, http_status, nsurl_code, sample_message)
  ),
  nsurl_code = COALESCE(nsurl_code, bug_intel_extract_nsurl_code(sample_message))
WHERE error_class IS NULL
   OR (nsurl_code IS NULL AND sample_message ~ 'NSURLError(Domain)? error (-?\d+)');

-- Compute structural_fingerprint for backfilled rows that now have enough info.
UPDATE bug_intelligence_fingerprints
SET structural_fingerprint = md5(source || '|' || op || '|' || error_class)
WHERE structural_fingerprint IS NULL
  AND op IS NOT NULL
  AND error_class IS NOT NULL
  AND error_class <> 'unknown';

-- ============================================================================
-- 8. Prime + verify
-- ============================================================================

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := compute_daily_bug_rollup();
  RAISE NOTICE '[20260516] rollup priming result: %', v_result;
END $$;

DO $$
DECLARE
  v_total INT;
  v_classified INT;
  v_with_class INT;
  v_with_struct INT;
  v_noise INT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM bug_intelligence_fingerprints;
  SELECT COUNT(*) INTO v_classified FROM bug_intelligence_fingerprints WHERE is_classified = TRUE;
  SELECT COUNT(*) INTO v_with_class FROM bug_intelligence_fingerprints WHERE error_class IS NOT NULL;
  SELECT COUNT(*) INTO v_with_struct FROM bug_intelligence_fingerprints WHERE structural_fingerprint IS NOT NULL;
  SELECT COUNT(*) INTO v_noise FROM bug_intel_noise_filter;

  RAISE NOTICE '[20260516] fingerprints: % total / % classified / % error_class / % structural_fingerprint. noise filters: %.',
    v_total, v_classified, v_with_class, v_with_struct, v_noise;

  IF v_noise < 4 THEN
    RAISE EXCEPTION '[20260516] noise filter seeds missing (expected ≥4, got %)', v_noise;
  END IF;

  -- Sanity: helper functions resolve.
  PERFORM bug_intel_classify_error('23505', NULL, NULL, 'test');
  PERFORM bug_intel_extract_nsurl_code('NSURLErrorDomain error -999');
  PERFORM bug_intel_compare_semver('1.2.4', '1.2.3');

  RAISE NOTICE '[20260516] helpers verified.';
END $$;

DO $$ BEGIN
  RAISE NOTICE '✅ Phase 9 bug intelligence installed: structural columns + noise filter (% seeds) + regression flag + auto-resolve + rewritten compute_daily_bug_rollup().',
    (SELECT COUNT(*) FROM bug_intel_noise_filter);
END $$;

COMMIT;
