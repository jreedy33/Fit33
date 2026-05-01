-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║ Migration #175 — NUJ Phase 2: Monetization Signal Capture                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
--
-- Phase 2 of the New User Journey Tracking pipeline (#167). Adds the four
-- predictive boolean flags that the Monetization Agent identified as the
-- biggest signal carriers for "will this user subscribe?":
--
--   1. created_custom_workout         — saved their first custom workout
--                                       (industry baseline: ~2× lift)
--   2. streak_3_days                  — completed a 3-day streak
--                                       (industry baseline: 2-4× lift)
--   3. goal_set                       — chose at least one fitness goal in
--                                       onboarding (1.5× lift)
--   4. notification_permission_granted — opted into push (key retention lever
--                                       for the daily-quest reminder loop)
--
-- WHY they live on `new_user_journey_enrollment` (alongside the existing 7
-- funnel booleans):
--   - Same per-user lifetime granularity (one row per user, never duplicated)
--   - The trigger function already runs once per event INSERT — adding 4 more
--     OR-assignments is free
--   - The CMS cohort summary aggregates all 11 booleans in one query — keeps
--     the funnel in a single readable section, no JOINs
--   - These flags ARE permanent ("did they ever do X in the 72h window?"),
--     not toggleable — same semantic as the existing 7
--
-- HOW the trigger flips each (event payload contracts that iOS must respect):
--   - created_custom_workout         ← event_type='workout' AND
--                                       payload->>'phase'='custom_saved'
--   - streak_3_days                  ← event_type='state' AND
--                                       payload->>'name'='streak' AND
--                                       payload->>'to' IN ('3','3_days')
--   - goal_set                       ← event_type='funnel' AND
--                                       payload->>'funnel'='onboarding' AND
--                                       payload->>'step'='goals' AND
--                                       payload->>'has_goals' = 'true'
--                                       (iOS sets payload.has_goals = true
--                                       only when selectedGoals is non-empty
--                                       at the moment of step transition)
--   - notification_permission_granted ← event_type='permission' AND
--                                       payload->>'kind'='notifications' AND
--                                       payload->>'granted'='true'
--
-- IDEMPOTENT — `ADD COLUMN IF NOT EXISTS` + `CREATE OR REPLACE FUNCTION`.
-- The trigger BINDING (`nuj_events_after_insert`) is preserved automatically
-- because we only replace the function body, not the trigger itself.
--
-- COMPATIBILITY — the 4 new columns are NOT NULL DEFAULT FALSE, so existing
-- rows backfill to FALSE on the ALTER TABLE. The COALESCE-defensive trigger
-- pattern (introduced as a hotfix to #167) is preserved.
-- ============================================================================

BEGIN;

-- 1. Add the four new boolean flags to the enrollment table -------------------
ALTER TABLE public.new_user_journey_enrollment
    ADD COLUMN IF NOT EXISTS created_custom_workout         BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS streak_3_days                  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS goal_set                       BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS notification_permission_granted BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Replace the trigger function with the 4-extra-flag version ---------------
-- Same defensive COALESCE pattern as the #167 hotfix; same trigger binding.
CREATE OR REPLACE FUNCTION public.update_nuj_enrollment_counters()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.new_user_journey_enrollment
    SET
        total_events            = COALESCE(total_events, 0) + 1,
        last_event_at           = NEW.occurred_at,
        last_screen             = COALESCE(NEW.screen, last_screen),
        total_errors            = COALESCE(total_errors, 0)  + CASE WHEN NEW.is_error THEN 1 ELSE 0 END,
        total_crashes           = COALESCE(total_crashes, 0) + CASE WHEN NEW.event_type = 'crash' THEN 1 ELSE 0 END,
        completed_onboarding    = COALESCE(completed_onboarding,    FALSE) OR (NEW.event_type = 'funnel'      AND (NEW.payload->>'funnel') = 'onboarding' AND (NEW.payload->>'step') = 'completed'),
        completed_first_workout = COALESCE(completed_first_workout, FALSE) OR (NEW.event_type = 'workout'     AND (NEW.payload->>'phase')  = 'completed'),
        logged_first_meal       = COALESCE(logged_first_meal,       FALSE) OR (NEW.event_type = 'meal'        AND (NEW.payload->>'phase')  = 'logged'),
        added_first_friend      = COALESCE(added_first_friend,      FALSE) OR (NEW.event_type = 'social'      AND (NEW.payload->>'action') = 'friend_added'),
        connected_wearable      = COALESCE(connected_wearable,      FALSE) OR (NEW.event_type = 'integration' AND (NEW.payload->>'action') = 'success'),
        saw_paywall             = COALESCE(saw_paywall,             FALSE) OR (NEW.event_type = 'paywall'     AND (NEW.payload->>'action') = 'view'),
        converted_paywall       = COALESCE(converted_paywall,       FALSE) OR (NEW.event_type = 'paywall'     AND (NEW.payload->>'action') = 'convert'),

        -- Phase 2 (Migration #175) ─ monetization predictor flags
        created_custom_workout         = COALESCE(created_custom_workout,         FALSE) OR (NEW.event_type = 'workout'    AND (NEW.payload->>'phase')  = 'custom_saved'),
        streak_3_days                  = COALESCE(streak_3_days,                  FALSE) OR (NEW.event_type = 'state'      AND (NEW.payload->>'name')   = 'streak' AND (NEW.payload->>'to') IN ('3', '3_days')),
        goal_set                       = COALESCE(goal_set,                       FALSE) OR (NEW.event_type = 'funnel'     AND (NEW.payload->>'funnel') = 'onboarding' AND (NEW.payload->>'step') = 'goals' AND (NEW.payload->>'has_goals') = 'true'),
        notification_permission_granted = COALESCE(notification_permission_granted, FALSE) OR (NEW.event_type = 'permission' AND (NEW.payload->>'kind')   = 'notifications' AND (NEW.payload->>'granted') = 'true')
    WHERE user_id = NEW.user_id;

    RETURN NEW;
END;
$$;

-- 3. Bump pg_net wait timeout from 5s default to 60s (re-applied here so the
--    file is self-contained / re-runnable on a fresh project).
CREATE OR REPLACE FUNCTION public.trigger_generate_new_user_reports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pending INT;
    v_supabase_url TEXT;
    v_service_key TEXT;
    v_cron_key TEXT;
    v_request_id BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_pending
    FROM public.new_user_journey_enrollment
    WHERE (d1_report_due_at <= now() AND d1_report_generated = FALSE)
       OR (d2_report_due_at <= now() AND d2_report_generated = FALSE)
       OR (d3_report_due_at <= now() AND d3_report_generated = FALSE)
       OR (final_report_due_at <= now() AND final_report_generated = FALSE);

    IF v_pending = 0 THEN
        RETURN jsonb_build_object('success', TRUE, 'skipped', TRUE, 'pending', 0);
    END IF;

    BEGIN
        SELECT value INTO v_supabase_url FROM public.internal_config WHERE key = 'supabase_url';
        SELECT value INTO v_service_key  FROM public.internal_config WHERE key = 'service_role_key';
        SELECT value INTO v_cron_key     FROM public.internal_config WHERE key = 'cron_key';
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'internal_config_missing', 'pending', v_pending);
    END;

    IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'config_incomplete', 'pending', v_pending);
    END IF;

    SELECT net.http_post(
        url     := v_supabase_url || '/functions/v1/generate-new-user-report',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_service_key,
            'x-cron-key',    COALESCE(v_cron_key, '')
        ),
        body    := jsonb_build_object('source', 'cron', 'pending', v_pending),
        timeout_milliseconds := 60000
    ) INTO v_request_id;

    RETURN jsonb_build_object('success', TRUE, 'request_id', v_request_id, 'pending', v_pending);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() TO service_role;

-- 4. Trailing fail-loud audit -------------------------------------------------
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    FOR v_missing IN
        SELECT col FROM (VALUES
            ('created_custom_workout'),
            ('streak_3_days'),
            ('goal_set'),
            ('notification_permission_granted')
        ) AS x(col)
        WHERE NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'new_user_journey_enrollment'
              AND column_name = x.col
        )
    LOOP
        RAISE EXCEPTION 'AUDIT FAIL — column % missing from new_user_journey_enrollment', v_missing;
    END LOOP;

    RAISE NOTICE '✅ NUJ PHASE 2 (#175) DEPLOYED — 4 new monetization-signal flags live, trigger updated';
END $$;

COMMIT;

-- ============================================================================
-- Verify (paste into SQL editor after running):
--
--   SELECT column_name, data_type, is_nullable, column_default
--     FROM information_schema.columns
--    WHERE table_schema = 'public'
--      AND table_name = 'new_user_journey_enrollment'
--      AND column_name IN ('created_custom_workout','streak_3_days',
--                          'goal_set','notification_permission_granted')
--    ORDER BY column_name;
--
--   Expected: 4 rows, all `boolean`, `NO`, `false`.
-- ============================================================================
