-- Strava insights cron — Phase 3 of Strava Integration Upgrade.
--
-- Wires the new `compute-strava-insights` edge function to pg_cron.
-- Mirrors the `trigger_compute_readiness_insights` pattern from
-- 20260507_personalized_insights_wearable.sql (canonical
-- `internal_config` + `x-cron-key` invariant — SUPABASE_AGENT #25,
-- supabase-rules #7).
--
-- The edge function itself reads `cardio_workouts` (Strava rows) and
-- `daily_readiness_history`, then upserts five strava_* insight cards
-- into `user_personalized_insights` using `onConflict:user_id,insight_key`.
--
-- Idempotent. Wrapped BEGIN/COMMIT.

BEGIN;

CREATE OR REPLACE FUNCTION public.trigger_compute_strava_insights()
RETURNS void
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
        RAISE WARNING 'compute_strava_insights: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/compute-strava-insights',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_anon,
            'apikey',        v_anon,
            'x-cron-key',    v_key,
            'Content-Type',  'application/json'
        ),
        body    := '{"source": "cron"}'::jsonb
    );
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_compute_strava_insights() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_compute_strava_insights() TO service_role;

COMMENT ON FUNCTION public.trigger_compute_strava_insights() IS
    'Phase 3 Strava integration: pg_cron entrypoint that POSTs to the compute-strava-insights edge function. Auth via x-cron-key + service_role bearer.';

-- Schedule nightly at 03:40 UTC — offset from compute-readiness-insights
-- (03:30) and bug-intel sweeps (03:45 / 04:30) so cold-starts stagger.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'compute-strava-insights-nightly') THEN
            PERFORM cron.unschedule('compute-strava-insights-nightly');
        END IF;

        PERFORM cron.schedule(
            'compute-strava-insights-nightly',
            '40 3 * * *',
            $cron$ SELECT public.trigger_compute_strava_insights() $cron$
        );
        RAISE NOTICE '✅ Scheduled compute-strava-insights-nightly (03:40 UTC daily)';
    ELSE
        RAISE NOTICE 'pg_cron not installed — trigger_compute_strava_insights() must be invoked manually';
    END IF;
END $$;

COMMIT;
