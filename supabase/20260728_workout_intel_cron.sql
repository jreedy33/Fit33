-- ═══════════════════════════════════════════════════════════════════════════
-- 20260728_workout_intel_cron.sql  (Migration #159)
--
-- pg_cron schedules for the workout-intelligence + corroboration pipeline.
--
-- TWO SEPARATE SCHEDULES
-- ----------------------
--
-- 1. analyze-quality-workout — drains pending ai_workout_reports rows.
--    Every 10 minutes (`7,17,27,37,47,57 * * * *`). Off-cycle from
--    triage-shake-reports (`3,13,...`) and triage-bugs (`:17 every 4h`)
--    so the three Anthropic-API workloads don't collide.
--
--    The fast-path SKIPs the HTTP call when there are no pending rows —
--    so this cron is a true no-op on an empty queue.
--
-- 2. promote_corroborated_proposals — re-evaluates pending proposals
--    against the corroboration ladder. Once a 2nd report agrees with
--    a previously-pending proposal, the multi-report gate fires and
--    the proposal auto-applies. This is the path that turns "Claude
--    proposed X for the first time" into "Claude proposed X twice
--    independently — apply it" without any human in the loop.
--
--    Runs nightly at 03:45 UTC (off-cycle from quest computation at
--    03:50 and bug-intel autoresolve at 04:30).
--
-- DEPENDENCIES
-- ------------
--   - #156 created `ai_workout_reports`, `propose_exercise_correction`.
--   - #157 created `exercise_correction_proposals`,
--     `promote_corroborated_proposals`, the corroboration ladder.
--   - This migration only adds the schedules + the cron-entry-point
--     wrapper. Re-running it is idempotent (unschedules first).
--
-- INTERNAL_CONFIG REQUIRED
-- ------------------------
--   internal_config('supabase_url')      = https://<ref>.supabase.co
--   internal_config('service_role_key')  = service-role JWT
--   internal_config('anon_key')          = anon JWT (used for the gateway
--                                          Authorization header so the
--                                          gateway accepts the request;
--                                          the function's own auth uses
--                                          x-cron-key)
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Cron entry point: analyze-quality-workout
--    Wraps the edge function call in the canonical fast-path-skip pattern.
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trigger_analyze_quality_workout()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url     TEXT;
    v_key     TEXT;
    v_anon    TEXT;
    v_pending INTEGER;
BEGIN
    SELECT count(*) INTO v_pending
      FROM public.ai_workout_reports
     WHERE status = 'pending';
    IF v_pending = 0 THEN RETURN; END IF;

    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'trigger_analyze_quality_workout: internal_config missing keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/analyze-quality-workout',
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

REVOKE ALL ON FUNCTION public.trigger_analyze_quality_workout() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_analyze_quality_workout() TO service_role;

COMMENT ON FUNCTION public.trigger_analyze_quality_workout IS
'pg_cron entry point for the workout-intelligence pipeline. Drains pending ai_workout_reports rows by firing analyze-quality-workout every 10 min. Fast-path skips when the queue is empty.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Cron entry point: promote_corroborated_proposals
--    Wraps the SQL function (no edge call needed — purely DB-local).
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.trigger_promote_corroborated_proposals()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pending INTEGER;
    v_result  JSONB;
BEGIN
    SELECT count(*) INTO v_pending
      FROM public.exercise_correction_proposals
     WHERE status = 'pending'
       AND confidence = 1.0;
    IF v_pending = 0 THEN RETURN; END IF;

    SELECT promote_corroborated_proposals(500) INTO v_result;
    RAISE NOTICE 'promote_corroborated_proposals nightly sweep: %', v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_promote_corroborated_proposals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_promote_corroborated_proposals() TO service_role;

COMMENT ON FUNCTION public.trigger_promote_corroborated_proposals IS
'pg_cron entry point for the corroboration ladder. Re-evaluates every pending confidence=1.0 proposal nightly — auto-promotes any that newly pass sister/name/multi_report gates.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Schedules — unschedule first so the migration is re-run safe.
-- ───────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'analyze-quality-workout-run') THEN
            PERFORM cron.unschedule('analyze-quality-workout-run');
        END IF;
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'promote-corroborated-proposals-nightly') THEN
            PERFORM cron.unschedule('promote-corroborated-proposals-nightly');
        END IF;

        -- analyze-quality-workout: every 10 min, off-cycle from
        -- triage-shake-reports (:3,13,...) and triage-bugs (:17 every 4h).
        PERFORM cron.schedule(
            'analyze-quality-workout-run',
            '7,17,27,37,47,57 * * * *',
            $cron$ SELECT trigger_analyze_quality_workout(); $cron$
        );

        -- promote-corroborated-proposals: nightly at 03:45 UTC.
        -- Off-cycle from compute-user-quest-personalization (:50) and
        -- bug-intel-single-incident-autoresolve (:30).
        PERFORM cron.schedule(
            'promote-corroborated-proposals-nightly',
            '45 3 * * *',
            $cron$ SELECT trigger_promote_corroborated_proposals(); $cron$
        );

        RAISE NOTICE '✅ Migration #159: analyze-quality-workout (every 10m) + promote-corroborated-proposals (nightly 03:45 UTC) scheduled.';
    ELSE
        RAISE WARNING 'pg_cron extension not available — skipping schedule installation';
    END IF;
END $$;

COMMIT;
