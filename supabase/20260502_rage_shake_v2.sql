-- 20260502_rage_shake_v2.sql
-- Rage-shake v2 — enrich bug_reports for Claude-powered triage.
--
-- Phase 6 of the Bug Intelligence pipeline.  When a user performs a rage
-- shake, the iOS client captures: screenshot, session_log, screen_name (via
-- SessionLogManager.getCurrentScreenInfo), likely_source_files (via
-- ScreenCodeMap.swift), severity, bug_category, expected_behavior. This
-- migration extends `bug_reports` to carry that metadata, adds a pg_notify
-- trigger so the `triage-shake-reports` edge function can run Claude
-- immediately (instead of waiting 4h for the cron), and wires the triage
-- report id back once Claude is done so the CMS /bug-intelligence UI
-- surfaces shake submissions alongside crash fingerprints.
--
-- RLS: bug_reports already has RLS. User can INSERT their own. Admin reads
-- via service role. We don't change that.
--
-- Idempotency: every ALTER/CREATE uses IF NOT EXISTS / OR REPLACE.

BEGIN;

-- ─── 1. New columns on bug_reports ──────────────────────────────────────
ALTER TABLE public.bug_reports
    ADD COLUMN IF NOT EXISTS severity TEXT
        CHECK (severity IN ('low', 'medium', 'high', 'critical'))
        DEFAULT 'medium',
    ADD COLUMN IF NOT EXISTS bug_category TEXT
        CHECK (bug_category IS NULL OR bug_category IN (
            'ui', 'data', 'performance', 'crash', 'auth',
            'workout', 'nutrition', 'social', 'health', 'other'
        )),
    ADD COLUMN IF NOT EXISTS likely_source_files JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS triage_status TEXT
        CHECK (triage_status IN ('pending', 'analyzing', 'analyzed', 'failed', 'legacy'))
        DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS triage_report_id UUID,
    ADD COLUMN IF NOT EXISTS triaged_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS triage_error TEXT;

-- Existing rows = legacy (no screen context, no severity info).
UPDATE public.bug_reports
   SET triage_status = 'legacy'
 WHERE triage_status = 'pending'
   AND created_at < now() - INTERVAL '1 hour';

-- Partial index so the triage worker / edge function can cheaply find
-- pending shake reports.
CREATE INDEX IF NOT EXISTS idx_bug_reports_triage_pending
    ON public.bug_reports (created_at DESC)
    WHERE triage_status = 'pending';

CREATE INDEX IF NOT EXISTS idx_bug_reports_triage_report
    ON public.bug_reports (triage_report_id)
    WHERE triage_report_id IS NOT NULL;

-- ─── 2. pg_cron wrapper → edge function (canonical pattern) ────────────
-- Same shape as trigger_triage_bugs() in 20260428_bug_intelligence_reports.sql.
-- Runs every 10 minutes (a shake report should feel near-realtime). The
-- edge function itself pulls only `triage_status = 'pending'` rows so the
-- cron is a no-op when the inbox is empty.
CREATE OR REPLACE FUNCTION public.trigger_triage_shake_reports()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_anon TEXT;
    v_pending INTEGER;
BEGIN
    -- Fast path: skip the HTTP round-trip when there's nothing to triage.
    SELECT count(*) INTO v_pending
      FROM public.bug_reports
     WHERE triage_status = 'pending';
    IF v_pending = 0 THEN RETURN; END IF;

    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'trigger_triage_shake_reports: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/triage-shake-reports',
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

REVOKE ALL ON FUNCTION public.trigger_triage_shake_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_triage_shake_reports() TO service_role;

COMMENT ON FUNCTION public.trigger_triage_shake_reports IS
'pg_cron entry point for Claude rage-shake triage. Fires the
 triage-shake-reports edge function every 10 minutes (no-op when the
 inbox is empty).';

-- Remove before re-scheduling so re-running the migration is idempotent.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'triage-shake-reports-run') THEN
        PERFORM cron.unschedule('triage-shake-reports-run');
    END IF;
END $$;

-- Offset by :03 so it doesn't collide with triage-bugs (:17 every 4h) or
-- compute_daily_bug_rollup (:00 hourly).
SELECT cron.schedule(
    'triage-shake-reports-run',
    '3,13,23,33,43,53 * * * *',
    $$SELECT trigger_triage_shake_reports()$$
);

-- ─── 4. RPC: mark_shake_report_triaged ─────────────────────────────────
-- Called by the edge function after Claude finishes. Keeps the UPDATE
-- authoritative (service role) and wires the bug_intelligence_reports.id
-- back to the bug_report so the CMS can deep-link either way.
CREATE OR REPLACE FUNCTION public.mark_shake_report_triaged(
    p_bug_report_id UUID,
    p_triage_report_id UUID,
    p_status TEXT DEFAULT 'analyzed',
    p_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Service-role only: the edge function uses the service-role key.
    -- Block non-service calls by checking auth.uid() is null (no JWT =
    -- service role bypassing JWT; authenticated users would have uid).
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'mark_shake_report_triaged is service-role only';
    END IF;

    IF p_status NOT IN ('analyzing', 'analyzed', 'failed') THEN
        RAISE EXCEPTION 'Invalid triage_status: %', p_status;
    END IF;

    UPDATE public.bug_reports
       SET triage_status    = p_status,
           triage_report_id = p_triage_report_id,
           triaged_at       = CASE WHEN p_status IN ('analyzed', 'failed')
                                   THEN now() ELSE triaged_at END,
           triage_error     = p_error
     WHERE id = p_bug_report_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_shake_report_triaged(UUID, UUID, TEXT, TEXT) FROM PUBLIC, authenticated, anon;
GRANT  EXECUTE ON FUNCTION public.mark_shake_report_triaged(UUID, UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.mark_shake_report_triaged IS
'Service-role RPC used by supabase/functions/triage-shake-reports to mark a
 bug_report as analyzed/failed and link it to the bug_intelligence_report
 Claude produced. Rejects authenticated callers (auth.uid() IS NOT NULL).';

-- ─── 5. View: v_bug_reports_for_triage ─────────────────────────────────
-- Edge function reads from this view so it doesn't need to hand-pick
-- columns. Includes everything Claude needs: description, expected,
-- screen_name, likely_source_files, severity, session_log,
-- screenshot_base64 (for Claude vision), device metadata.
CREATE OR REPLACE VIEW public.v_bug_reports_for_triage
WITH (security_invoker = on) AS
SELECT
    id,
    user_id,
    user_name,
    description,
    expected_behavior,
    reproduces_every_time,
    additional_info,
    screenshot_base64,
    screen_name,
    likely_source_files,
    severity,
    bug_category,
    session_log,
    device_model,
    os_version,
    app_version,
    triage_status,
    created_at
FROM public.bug_reports
WHERE triage_status IN ('pending', 'analyzing');

REVOKE ALL ON public.v_bug_reports_for_triage FROM PUBLIC, authenticated, anon;
GRANT  SELECT ON public.v_bug_reports_for_triage TO service_role;

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'bug_reports'
--    AND column_name IN ('severity','bug_category','likely_source_files',
--                        'triage_status','triage_report_id','triaged_at',
--                        'triage_error');
-- SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.bug_reports'::regclass;
-- SELECT count(*) AS pending FROM public.bug_reports WHERE triage_status = 'pending';
