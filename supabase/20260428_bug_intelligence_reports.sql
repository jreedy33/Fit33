-- ============================================================================
-- Bug Intelligence Pipeline (Phase 2): Claude Triage Reports + Agent Routing
-- Date: 2026-04-28
-- Sprint 8 (Q2-97)
--
-- PURPOSE
-- -------
-- Phase 1 fingerprints + trends → this phase adds a scheduled Claude triage
-- agent that converts raw fingerprints into assigned, agent-owned, fixable
-- reports (title / summary / file_path / code_diff / severity / confidence).
--
-- ARCHITECTURE
-- ------------
--   bug_intelligence_fingerprints (open status, recent activity)
--           |
--           v  (every 4h via pg_cron -> trigger_triage_bugs -> edge fn)
--   supabase/functions/triage-bugs/index.ts
--      - pulls top N open + recent fingerprints
--      - enriches each with example entries + linked crash rows
--      - calls Claude with ENGINEERING_TEAM ownership matrix in system prompt
--      - writes into bug_intelligence_reports
--      - marks source fingerprint.status = 'triaged' + assigned_agent = owner
--      - marks source trend rows reviewed_at = now() + reviewed_by = 'triage-v1'
--
-- SCHEDULING
-- ----------
--   * triage-bugs-run              — pg_cron every 4h at :17
--   * cleanup-bug-intelligence-reports — pg_cron daily at 03:45 UTC (90d ret.)
--
-- SECURITY
-- --------
--   * bug_intelligence_reports: service-role only (admin CMS uses service
--     role via /api/admin route with verifyAdmin).
--   * trigger_triage_bugs() follows canonical internal_config + x-cron-key
--     pattern from 20260420_challenge_opponent_wake.sql.
--
-- ROLLBACK
-- --------
--   DROP TABLE IF EXISTS bug_intelligence_reports CASCADE;
--   DROP FUNCTION IF EXISTS trigger_triage_bugs();
--   DROP FUNCTION IF EXISTS cleanup_bug_intelligence_reports();
--   SELECT cron.unschedule('triage-bugs-run');
--   SELECT cron.unschedule('cleanup-bug-intelligence-reports');
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. bug_intelligence_reports — Claude's per-fingerprint triage output
-- ============================================================================

CREATE TABLE IF NOT EXISTS bug_intelligence_reports (
    id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,

    -- Link to fingerprint (many reports per fingerprint over time — a bug can
    -- be re-triaged after regression, after a failed fix, after more data).
    fingerprint TEXT NOT NULL
        REFERENCES bug_intelligence_fingerprints(fingerprint)
        ON DELETE CASCADE,

    -- The trend that triggered this triage run (nullable: a manual triage
    -- from the CMS "Triage now" button has no trend id).
    trigger_trend_id UUID
        REFERENCES bug_intelligence_trends(id)
        ON DELETE SET NULL,
    trigger_reason TEXT NOT NULL
        CHECK (trigger_reason IN ('new', 'regression', 'scheduled', 'manual')),

    -- Claude routing output
    agent_owner TEXT NOT NULL
        CHECK (agent_owner IN (
            'quality-performance',
            'product-engineer',
            'data-backend',
            'infra-security',
            'supabase-expert',
            'design-system',
            'design',
            'fitness-expert',
            'device-compatibility',
            'support',
            'unknown'
        )),
    invariant_violated TEXT,         -- e.g. "no force unwraps" (swiftui-rules #2)
    severity TEXT NOT NULL
        CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    confidence NUMERIC(3, 2) NOT NULL
        CHECK (confidence >= 0 AND confidence <= 1),

    -- Human-readable summary
    title TEXT NOT NULL,
    summary TEXT NOT NULL,

    -- Fix material (nullable — some triages produce analysis without a diff)
    file_path TEXT,
    code_diff TEXT,

    -- Cross-links
    pain_point_candidate TEXT,       -- proposed addition to SUPPORT_AGENT pain registry
    suggested_todo TEXT,             -- proposed MASTER_TODO line

    -- Observability
    analysis_model TEXT NOT NULL DEFAULT 'claude-sonnet-4-20250514',
    raw_response JSONB,
    example_entry_ids JSONB,         -- [dev_session_logs.id or crash_reports.id]

    -- Review / PR lifecycle
    review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (review_status IN ('pending', 'approved', 'rejected', 'merged', 'stale')),
    reviewed_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    pr_url TEXT,
    pr_branch TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_bug_reports_fingerprint_created
    ON bug_intelligence_reports (fingerprint, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_reports_agent_status
    ON bug_intelligence_reports (agent_owner, review_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_reports_severity_confidence
    ON bug_intelligence_reports (severity, confidence DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_reports_review_status
    ON bug_intelligence_reports (review_status, created_at DESC);

ALTER TABLE bug_intelligence_reports ENABLE ROW LEVEL SECURITY;
-- No policies → service role only (admin CMS proxies all reads/writes).

COMMENT ON TABLE bug_intelligence_reports IS
    'Claude triage output per fingerprint. One row per triage run. Admin CMS reads via service role.';

-- ============================================================================
-- 2. trigger_triage_bugs() — pg_cron wrapper around the edge function
--    Canonical pattern from 20260420_challenge_opponent_wake.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_triage_bugs()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_anon TEXT;
BEGIN
    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'trigger_triage_bugs: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/triage-bugs',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_anon,
            'apikey',        v_anon,
            'x-cron-key',    v_key,
            'Content-Type',  'application/json'
        ),
        body    := jsonb_build_object('source', 'cron')
    );
END;
$$;

REVOKE ALL ON FUNCTION trigger_triage_bugs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trigger_triage_bugs() TO service_role;

COMMENT ON FUNCTION trigger_triage_bugs() IS
    'pg_cron entry point for Claude bug triage. Fires the triage-bugs edge function every 4h.';

-- ============================================================================
-- 3. cleanup_bug_intelligence_reports() — 90-day retention
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_bug_intelligence_reports()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted INT;
BEGIN
    -- Keep reports that are still actionable: pending, approved, or merged
    -- PRs we might want to reference. Only prune rejected/stale/merged reports
    -- older than 90 days.
    DELETE FROM bug_intelligence_reports
    WHERE created_at < NOW() - INTERVAL '90 days'
      AND review_status IN ('rejected', 'stale', 'merged');
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION cleanup_bug_intelligence_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION cleanup_bug_intelligence_reports() TO service_role;

-- ============================================================================
-- 4. pg_cron schedules (idempotent)
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'triage-bugs-run') THEN
        PERFORM cron.unschedule('triage-bugs-run');
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-bug-intelligence-reports') THEN
        PERFORM cron.unschedule('cleanup-bug-intelligence-reports');
    END IF;
END $$;

-- Triage every 4 hours at :17 — offset from compute_daily_bug_rollup (hourly
-- :00) so the two cron jobs never compete for the same connection window.
SELECT cron.schedule(
    'triage-bugs-run',
    '17 */4 * * *',
    $$SELECT trigger_triage_bugs()$$
);

-- Daily prune at 03:45 UTC (after rollup cleanup at 03:30).
SELECT cron.schedule(
    'cleanup-bug-intelligence-reports',
    '45 3 * * *',
    $$SELECT cleanup_bug_intelligence_reports()$$
);

-- ============================================================================
-- 5. Admin convenience view — most actionable reports first
--    (security_invoker = on per supabase-rules.mdc invariant)
-- ============================================================================

CREATE OR REPLACE VIEW v_bug_intelligence_inbox
WITH (security_invoker = on)
AS
SELECT
    r.id                     AS report_id,
    r.fingerprint,
    r.agent_owner,
    r.severity,
    r.confidence,
    r.title,
    r.summary,
    r.file_path,
    r.code_diff,
    r.invariant_violated,
    r.review_status,
    r.pr_url,
    r.created_at             AS report_created_at,
    f.source                 AS fingerprint_source,
    f.normalized_message,
    f.sample_message,
    f.error_domain,
    f.occurrence_count,
    f.unique_user_count,
    f.first_seen_app_version,
    f.last_seen_app_version,
    f.affected_screens,
    f.first_seen_at,
    f.last_seen_at,
    f.status                 AS fingerprint_status,
    f.assigned_agent         AS fingerprint_owner
FROM bug_intelligence_reports r
JOIN bug_intelligence_fingerprints f USING (fingerprint)
WHERE r.review_status = 'pending'
ORDER BY
    CASE r.severity
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        ELSE 4
    END,
    r.confidence DESC,
    r.created_at DESC;

COMMENT ON VIEW v_bug_intelligence_inbox IS
    'Admin CMS triage inbox: pending reports sorted by severity + confidence.';

-- ============================================================================
-- 6. Migration index hook
-- ============================================================================

DO $$ BEGIN
    RAISE NOTICE '✅ bug_intelligence_reports table + triage cron installed';
    RAISE NOTICE '   Next: deploy supabase/functions/triage-bugs + set internal_config keys';
END $$;

COMMIT;
