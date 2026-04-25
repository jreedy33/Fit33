-- ============================================================================
-- 20260606 — Smart Adaptive Daily Goals: verification fanout RPCs
--
-- Phase 6 of the personalization upgrade. Two SECURITY DEFINER RPCs the
-- iOS client calls fire-and-forget after every Strava sync /
-- ReadinessService recompute — they walk today's user_daily_quests for
-- the caller, run the matching auto-verifier, and call update_quest_progress
-- to flip any newly-completable quest to is_completed = TRUE.
--
--   * verify_strava_quests_for_today(p_timezone)
--       Detects:
--         run_outside_3km / run_outside_5km / run_outside_8km   → distance
--         cycle_outside_15km / cycle_outside_30km                → distance
--         beat_your_5k_pr             → cardio_personal_records 5K time vs prior best
--         negative_split_run          → splits_json second-half pace < first-half
--         complete_strava_segment     → segment_efforts_json non-empty for today
--
--   * verify_wearable_quests_for_today(p_timezone)
--       Reads daily_readiness_history (today's row) and today's
--       cardio_workouts to verify:
--         sleep_8h_wearable           → sleep_hours >= 8
--         recovery_above_67           → score >= 67
--         hrv_above_baseline          → hrv_delta_pct > 0
--         rhr_in_healthy_range        → rhr_trend_bpm <= 0
--         walk_when_red               → band = 'red' AND walk >= 20 min today
--         respect_red_recovery        → band = 'red' AND only recovery / mobility
--                                        workout type today
--
-- Both RPCs are auth.uid()-pinned (Data invariant 7) — service-role
-- contexts (cron) skipped because there's no caller to verify for.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. verify_strava_quests_for_today
-- ============================================================================
DROP FUNCTION IF EXISTS public.verify_strava_quests_for_today(TEXT);

CREATE OR REPLACE FUNCTION public.verify_strava_quests_for_today(
    p_timezone TEXT DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id  UUID := auth.uid();
    v_today      DATE;
    v_quest      RECORD;
    v_completed  TEXT[] := '{}';
    v_skipped    TEXT[] := '{}';
    v_5k_meters  INT := 5000;
    v_today_5k_seconds INT;
    v_best_5k_seconds  INT;
    v_negative_split   BOOLEAN;
    v_segments_today   INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_auth_uid');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               'run_outside_3km','run_outside_5km','run_outside_8km',
               'cycle_outside_15km','cycle_outside_30km',
               'beat_your_5k_pr','negative_split_run','complete_strava_segment'
           )
    LOOP
        -- Distance-only keys delegate to the existing helper from 20260531.
        IF v_quest.quest_key IN ('run_outside_3km','run_outside_5km','cycle_outside_15km') THEN
            IF public.is_strava_quest_completed(v_caller_id, v_quest.quest_key, p_timezone) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'run_outside_8km' THEN
            IF EXISTS (
                SELECT 1 FROM cardio_workouts cw
                WHERE cw.user_id = v_caller_id
                  AND cw.source = 'strava'
                  AND COALESCE(cw.activity_type, '') = 'outdoor_run'
                  AND COALESCE(cw.distance_meters, 0) >= 8000
                  AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
            ) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'cycle_outside_30km' THEN
            IF EXISTS (
                SELECT 1 FROM cardio_workouts cw
                WHERE cw.user_id = v_caller_id
                  AND cw.source = 'strava'
                  AND COALESCE(cw.activity_type, '') = 'outdoor_cycle'
                  AND COALESCE(cw.distance_meters, 0) >= 30000
                  AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
            ) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'beat_your_5k_pr' THEN
            -- Best-known 5K time prior to today (any source).
            SELECT MIN(elapsed_seconds) INTO v_best_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND COALESCE(activity_type, '') = 'outdoor_run'
               AND COALESCE(distance_meters, 0) >= v_5k_meters
               AND elapsed_seconds IS NOT NULL
               AND (started_at AT TIME ZONE p_timezone)::DATE < v_today;

            -- Today's fastest qualifying 5K segment.
            SELECT MIN(elapsed_seconds) INTO v_today_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND source = 'strava'
               AND COALESCE(activity_type, '') = 'outdoor_run'
               AND COALESCE(distance_meters, 0) >= v_5k_meters
               AND elapsed_seconds IS NOT NULL
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;

            IF v_today_5k_seconds IS NOT NULL
               AND (v_best_5k_seconds IS NULL OR v_today_5k_seconds < v_best_5k_seconds) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'negative_split_run' THEN
            -- Walk today's runs and check splits_json. Strava splits_json
            -- is an array of `{distance, elapsed_time, average_speed, …}`.
            -- Negative split = back half average pace ≤ front half (we use
            -- average_speed: back half ≥ front half).
            SELECT EXISTS (
                SELECT 1
                  FROM cardio_workouts cw,
                       LATERAL jsonb_array_elements(COALESCE(cw.splits_json, '[]'::jsonb)) WITH ORDINALITY AS s(elem, idx)
                 WHERE cw.user_id = v_caller_id
                   AND cw.source = 'strava'
                   AND COALESCE(cw.activity_type, '') = 'outdoor_run'
                   AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
                   AND jsonb_typeof(cw.splits_json) = 'array'
                   AND jsonb_array_length(cw.splits_json) >= 2
                 GROUP BY cw.id
                HAVING (
                    AVG((s.elem->>'average_speed')::NUMERIC) FILTER (WHERE s.idx >  jsonb_array_length(cw.splits_json) / 2)
                    >
                    AVG((s.elem->>'average_speed')::NUMERIC) FILTER (WHERE s.idx <= jsonb_array_length(cw.splits_json) / 2)
                )
            ) INTO v_negative_split;

            IF COALESCE(v_negative_split, FALSE) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'complete_strava_segment' THEN
            SELECT COUNT(*) INTO v_segments_today
              FROM cardio_workouts cw
             WHERE cw.user_id = v_caller_id
               AND cw.source = 'strava'
               AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND jsonb_typeof(COALESCE(cw.segment_efforts_json, '[]'::jsonb)) = 'array'
               AND jsonb_array_length(COALESCE(cw.segment_efforts_json, '[]'::jsonb)) > 0;

            IF v_segments_today > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_strava_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_strava_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_strava_quests_for_today(TEXT) IS
    'Smart Adaptive Daily Goals (20260606): walks today user_daily_quests for the caller and ticks any Strava-detectable completion. Auto-called from iOS DailyQuestService after StravaService.syncActivities.';


-- ============================================================================
-- 2. verify_wearable_quests_for_today
-- ============================================================================
DROP FUNCTION IF EXISTS public.verify_wearable_quests_for_today(TEXT);

CREATE OR REPLACE FUNCTION public.verify_wearable_quests_for_today(
    p_timezone TEXT DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_readiness   RECORD;
    v_quest       RECORD;
    v_completed   TEXT[] := '{}';
    v_skipped     TEXT[] := '{}';
    v_walk_minutes_today INT;
    v_recovery_workout_today BOOLEAN;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_auth_uid');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    SELECT score, band, hrv_delta_pct, sleep_hours, rhr_trend_bpm, primary_source
      INTO v_readiness
      FROM daily_readiness_history
     WHERE user_id = v_caller_id
       AND date = v_today
     ORDER BY updated_at DESC
     LIMIT 1;

    -- If we have NO readiness row yet, nothing wearable-driven can verify.
    IF v_readiness IS NULL THEN
        RETURN jsonb_build_object('success', TRUE, 'completed', '{}'::TEXT[], 'skipped', '{}'::TEXT[], 'reason', 'no_readiness_row');
    END IF;

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               'sleep_8h_wearable','recovery_above_67','hrv_above_baseline',
               'rhr_in_healthy_range','walk_when_red','respect_red_recovery'
           )
    LOOP
        IF v_quest.quest_key = 'sleep_8h_wearable' THEN
            IF COALESCE(v_readiness.sleep_hours, 0) >= 8 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'recovery_above_67' THEN
            IF COALESCE(v_readiness.score, 0) >= 67 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'hrv_above_baseline' THEN
            IF COALESCE(v_readiness.hrv_delta_pct, -1) > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'rhr_in_healthy_range' THEN
            -- Healthy = today's RHR ≤ 28-day baseline (rhr_trend_bpm ≤ 0).
            IF COALESCE(v_readiness.rhr_trend_bpm, 1) <= 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'walk_when_red' THEN
            IF v_readiness.band = 'red' THEN
                SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
                  INTO v_walk_minutes_today
                  FROM cardio_workouts
                 WHERE user_id = v_caller_id
                   AND COALESCE(activity_type, '') IN ('walk', 'hike')
                   AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
                IF v_walk_minutes_today >= 20 THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'respect_red_recovery' THEN
            -- Red day AND only recovery-flavored activity logged today
            -- (walk / hike / yoga / stretch / mobility — no strenuous run/lift).
            IF v_readiness.band = 'red' THEN
                SELECT EXISTS (
                    SELECT 1 FROM cardio_workouts
                    WHERE user_id = v_caller_id
                      AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
                      AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
                ) AND NOT EXISTS (
                    -- Canonical `workouts.date` is DATE (see
                    -- 20260327_engagement_scoring.sql line 14). No
                    -- timezone math needed — compare DATE to DATE.
                    SELECT 1 FROM workouts
                    WHERE user_id = v_caller_id
                      AND date = v_today
                ) INTO v_recovery_workout_today;

                IF v_recovery_workout_today THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today,
        'band', v_readiness.band,
        'score', v_readiness.score
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_wearable_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_wearable_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_wearable_quests_for_today(TEXT) IS
    'Smart Adaptive Daily Goals (20260606): walks today user_daily_quests for the caller and ticks any wearable-detectable completion (sleep / recovery / HRV / RHR / red-band conduct). Auto-called from iOS after ReadinessService.recompute().';

COMMIT;
