-- =============================================================================
-- Native cardio quest widening (Cardio Redesign Phase 1)
-- =============================================================================
-- The Cardio Redesign ships native walk + run with `source = 'fit33'`.
-- The Phase-3 Strava quest detector and the Phase-6 verification fanout
-- (#20260531 + #20260606) currently filter on `source = 'strava'`
-- exclusively, which means a 5K outdoor run completed in Fit33 (no Strava
-- connected) would NOT tick the daily quest "5K Sweat" — even though
-- functionally it's the same workout.
--
-- This migration widens both helpers to accept `source IN ('strava', 'fit33')`
-- so the existing quest templates fire for both authoring sources without
-- needing duplicate templates.
--
-- Also widens the negative-split detector to fall back to
-- `splits_native_json` (Fit33's native splits format from RunningManager)
-- when `splits_json` (Strava's format) is absent. Fit33's split shape:
--   [{ "kilometer": Int, "time": Double, "pace": Double, "is_manual": Bool }]
-- vs Strava's:
--   [{ "distance": Double, "elapsed_time": Int, "average_speed": Double }]
-- Negative split = back-half average_speed > front-half OR back-half pace
-- (sec/km, lower-is-faster) < front-half pace.
--
-- Idempotent — drops all overloads then CREATE OR REPLACE.
-- =============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Widen `is_strava_quest_completed` (the Phase-3 distance helper)
-- ──────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.is_strava_quest_completed(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.is_strava_quest_completed(
    p_user_id UUID,
    p_quest_key TEXT,
    p_timezone TEXT DEFAULT 'UTC'
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id        UUID := auth.uid();
    v_today            DATE;
    v_required_meters  INT;
    v_required_types   TEXT[];
    v_count            INT;
BEGIN
    -- IDOR guard (Data invariant #7).
    IF v_caller_id IS NULL OR v_caller_id <> p_user_id THEN
        RETURN FALSE;
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Native runs map activity_type to: 'run' | 'walk' | 'outdoor_cycle'
    -- (CardioActivity enum in OutdoorCardioManager). Strava uses
    -- 'outdoor_run' | 'outdoor_cycle' | 'treadmill' | etc. We accept both
    -- shapes via expanded type arrays.
    CASE p_quest_key
        WHEN 'run_outside_3km' THEN
            v_required_meters := 3000;
            v_required_types  := ARRAY['outdoor_run', 'run'];
        WHEN 'run_outside_5km' THEN
            v_required_meters := 5000;
            v_required_types  := ARRAY['outdoor_run', 'run'];
        WHEN 'cycle_outside_15km' THEN
            v_required_meters := 15000;
            v_required_types  := ARRAY['outdoor_cycle', 'cycling'];
        ELSE
            RETURN FALSE;
    END CASE;

    SELECT COUNT(*) INTO v_count
    FROM public.cardio_workouts cw
    WHERE cw.user_id = v_caller_id
      AND cw.source IN ('strava', 'fit33')
      AND COALESCE(cw.activity_type, '') = ANY (v_required_types)
      AND COALESCE(cw.distance_meters, 0) >= v_required_meters
      AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today;

    RETURN v_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_strava_quest_completed(UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.is_strava_quest_completed(UUID, TEXT, TEXT) IS
    'Cardio Redesign Phase 1: returns TRUE when the caller has logged a qualifying outdoor cardio activity today (source IN strava | fit33). Used by daily-quest verification.';


-- ──────────────────────────────────────────────────────────────────────────
-- 2. Widen `verify_strava_quests_for_today` (Phase-6 fanout RPC)
-- ──────────────────────────────────────────────────────────────────────────
-- Same RPC name (Swift call sites unchanged), but every cw.source = 'strava'
-- becomes cw.source IN ('strava', 'fit33'), and negative-split + 5K-PR
-- detectors fall back to splits_native_json when splits_json is empty.
DROP FUNCTION IF EXISTS public.verify_strava_quests_for_today(TEXT);

CREATE OR REPLACE FUNCTION public.verify_strava_quests_for_today(
    p_timezone TEXT DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id        UUID := auth.uid();
    v_today            DATE;
    v_quest            RECORD;
    v_completed        TEXT[] := '{}';
    v_skipped          TEXT[] := '{}';
    v_5k_meters        INT := 5000;
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
        IF v_quest.quest_key IN ('run_outside_3km','run_outside_5km','cycle_outside_15km') THEN
            -- Distance keys delegate to the widened helper.
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
                  AND cw.source IN ('strava', 'fit33')
                  AND COALESCE(cw.activity_type, '') IN ('outdoor_run', 'run')
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
                  AND cw.source IN ('strava', 'fit33')
                  AND COALESCE(cw.activity_type, '') IN ('outdoor_cycle', 'cycling')
                  AND COALESCE(cw.distance_meters, 0) >= 30000
                  AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
            ) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'beat_your_5k_pr' THEN
            -- Best 5K time prior to today across any source — the historical
            -- baseline doesn't care who recorded it.
            SELECT MIN(elapsed_seconds) INTO v_best_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND COALESCE(activity_type, '') IN ('outdoor_run', 'run')
               AND COALESCE(distance_meters, 0) >= v_5k_meters
               AND elapsed_seconds IS NOT NULL
               AND (started_at AT TIME ZONE p_timezone)::DATE < v_today;

            -- Today's fastest qualifying 5K segment from EITHER source.
            SELECT MIN(elapsed_seconds) INTO v_today_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND source IN ('strava', 'fit33')
               AND COALESCE(activity_type, '') IN ('outdoor_run', 'run')
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
            -- Strava splits_json shape: { distance, elapsed_time, average_speed }
            --   → back-half avg(average_speed) > front-half avg
            -- Fit33 splits_native_json shape: { kilometer, time, pace }
            --   → back-half avg(pace) < front-half avg (lower pace = faster)
            -- Detect via either format, whichever is present.
            SELECT EXISTS (
                -- Strava-style detection
                SELECT 1
                  FROM cardio_workouts cw,
                       LATERAL jsonb_array_elements(COALESCE(cw.splits_json, '[]'::jsonb))
                            WITH ORDINALITY AS s(elem, idx)
                 WHERE cw.user_id = v_caller_id
                   AND cw.source = 'strava'
                   AND COALESCE(cw.activity_type, '') IN ('outdoor_run', 'run')
                   AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
                   AND jsonb_typeof(cw.splits_json) = 'array'
                   AND jsonb_array_length(cw.splits_json) >= 2
                 GROUP BY cw.id
                HAVING (
                    AVG((s.elem->>'average_speed')::NUMERIC)
                        FILTER (WHERE s.idx >  jsonb_array_length(cw.splits_json) / 2)
                    >
                    AVG((s.elem->>'average_speed')::NUMERIC)
                        FILTER (WHERE s.idx <= jsonb_array_length(cw.splits_json) / 2)
                )
                UNION ALL
                -- Native detection (pace is sec/km, lower = faster)
                SELECT 1
                  FROM cardio_workouts cw,
                       LATERAL jsonb_array_elements(COALESCE(cw.splits_native_json, '[]'::jsonb))
                            WITH ORDINALITY AS s(elem, idx)
                 WHERE cw.user_id = v_caller_id
                   AND cw.source = 'fit33'
                   AND COALESCE(cw.activity_type, '') IN ('outdoor_run', 'run')
                   AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
                   AND jsonb_typeof(cw.splits_native_json) = 'array'
                   AND jsonb_array_length(cw.splits_native_json) >= 2
                 GROUP BY cw.id
                HAVING (
                    AVG((s.elem->>'pace')::NUMERIC)
                        FILTER (WHERE s.idx >  jsonb_array_length(cw.splits_native_json) / 2)
                    <
                    AVG((s.elem->>'pace')::NUMERIC)
                        FILTER (WHERE s.idx <= jsonb_array_length(cw.splits_native_json) / 2)
                )
            ) INTO v_negative_split;

            IF COALESCE(v_negative_split, FALSE) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'complete_strava_segment' THEN
            -- Segments are Strava-only data. Native runs cannot complete this.
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
        'date', v_today,
        'sources_accepted', jsonb_build_array('strava', 'fit33')
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_strava_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_strava_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_strava_quests_for_today(TEXT) IS
    'Cardio Redesign Phase 1: walks today user_daily_quests for the caller and ticks any outdoor-cardio detectable completion. Now accepts source IN (strava, fit33) — same templates fire for both Strava webhook arrivals AND native (Fit33-tracked) runs. Negative-split detector falls back to splits_native_json when splits_json is absent. Segment quest remains Strava-only (segments are Strava-API data).';

COMMIT;
