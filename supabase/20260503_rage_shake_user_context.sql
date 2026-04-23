-- 20260503_rage_shake_user_context.sql
-- Rage-shake v2.1 — enrich `v_bug_reports_for_triage` with user_email so
-- the triage-shake-reports edge function can (a) show the reporter's
-- email in the admin CMS inbox and (b) look up `user_profiles` with that
-- email as a fallback when `user_id` is null (e.g. pre-auth shake).
--
-- Also re-creates the view projecting `user_email`. `CREATE OR REPLACE
-- VIEW` cannot add columns to an existing view in Postgres, so we DROP
-- then CREATE. Safe because the view is service-role-only and has no
-- dependents.
--
-- Idempotent: DROP VIEW IF EXISTS → CREATE VIEW.

BEGIN;

DROP VIEW IF EXISTS public.v_bug_reports_for_triage;

CREATE VIEW public.v_bug_reports_for_triage
WITH (security_invoker = on) AS
SELECT
    id,
    user_id,
    user_name,
    user_email,                    -- NEW in v2.1 — Claude uses this to key
                                   -- user_profiles lookup when user_id is null.
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

COMMENT ON VIEW public.v_bug_reports_for_triage IS
'Phase 6 rage-shake view feeding supabase/functions/triage-shake-reports.
 v2.1 (2026-05-03): adds user_email so Claude can correlate the reporter
 with user_profiles. Service-role only.';

COMMIT;
