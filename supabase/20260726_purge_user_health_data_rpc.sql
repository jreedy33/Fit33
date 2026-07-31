-- ============================================================================
-- purge_user_health_data() — real backend for the Settings → Privacy &
-- Security → Health Data "Stop syncing & delete cloud copy" control.
-- (2026-07-26 production-readiness audit — MASTER_TODO PR-10)
--
-- Before this migration the iOS button only logged the request while the UI
-- claimed "Purge will run within 24 hours" — a dishonest privacy surface
-- (App Review 5.1.1 / trust risk, Infra invariant 33).
--
-- Scope: HealthKit-DERIVED cloud rows for the calling user only.
--   - daily_activity_summary  → all rows (populated exclusively from HK)
--   - heart_rate_daily        → all rows (populated exclusively from HK)
--   - sleep_logs              → rows WHERE source = 'healthkit' only
--                               (WHOOP / Oura sleep is governed by their own
--                               disconnect flows)
--   - cardio_workouts         → rows WHERE source = 'healthkit' only
--                               (native Fit33 workouts are app content the
--                               user created in-app, NOT an HK cloud copy —
--                               deleting them would destroy workout history)
--
-- Auth: SECURITY DEFINER, derives the user from auth.uid() — takes NO user
-- parameter (supabase-rules: DEFINER RPCs must not trust client user ids).
-- Fails loudly when called without a user context.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.purge_user_health_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_activity_deleted   INTEGER := 0;
    v_heart_rate_deleted INTEGER := 0;
    v_sleep_deleted      INTEGER := 0;
    v_cardio_deleted     INTEGER := 0;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'purge_user_health_data: requires an authenticated user'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'daily_activity_summary') THEN
        DELETE FROM public.daily_activity_summary WHERE user_id = v_uid;
        GET DIAGNOSTICS v_activity_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'heart_rate_daily') THEN
        DELETE FROM public.heart_rate_daily WHERE user_id = v_uid;
        GET DIAGNOSTICS v_heart_rate_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sleep_logs') THEN
        DELETE FROM public.sleep_logs WHERE user_id = v_uid AND source = 'healthkit';
        GET DIAGNOSTICS v_sleep_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'cardio_workouts') THEN
        DELETE FROM public.cardio_workouts WHERE user_id = v_uid AND source = 'healthkit';
        GET DIAGNOSTICS v_cardio_deleted = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', v_uid,
        'deleted', jsonb_build_object(
            'daily_activity_summary', v_activity_deleted,
            'heart_rate_daily', v_heart_rate_deleted,
            'sleep_logs_healthkit', v_sleep_deleted,
            'cardio_workouts_healthkit', v_cardio_deleted
        )
    );
END $$;

REVOKE ALL ON FUNCTION public.purge_user_health_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_user_health_data() TO authenticated, service_role;

COMMENT ON FUNCTION public.purge_user_health_data() IS
    'Deletes the calling user''s HealthKit-derived cloud rows (activity, heart '
    'rate, HK-sourced sleep + cardio). Backs the Settings → Health Data '
    '"Stop syncing & delete cloud copy" control. auth.uid()-scoped; no params.';

-- PostgREST schema-cache reload (supabase-rules.mdc — mandatory after
-- CREATE OR REPLACE FUNCTION; fires only on successful commit).
NOTIFY pgrst, 'reload schema';

COMMIT;
