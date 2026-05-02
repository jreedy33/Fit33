-- =============================================================================
-- record_cardio_workout RPC — single-transaction native cardio fanout
-- =============================================================================
-- Cardio Redesign Phase 1. Replaces the bare `INSERT` from
-- `SupabaseManager.saveCardioWorkout` with a SECURITY DEFINER RPC that runs:
--
--   1. INSERT into cardio_workouts with user_id = auth.uid(),
--      source = 'fit33', origin_app = 'fit33', external_id = client UUID
--      (idempotent on (user_id, source, external_id) — guards double-tap
--      on Finish).
--   2. Same-origin overlap dedup: any other 'fit33' row whose time window
--      overlaps ≥50% with the new row (older `created_at` loses).
--   3. Cross-origin merge: any 'strava' row that overlaps ≥50% with the new
--      'fit33' row → DELETE the strava one. Native is canonical because:
--        a) it has the route polyline (Strava only has a summary)
--        b) the iOS-side fan-out (XP, quest verify, push) has already fired
--        c) Strava-as-HealthKit-mirror double-write would otherwise create
--           a third row.
--      Per WHOOP-dedup pattern in HealthDataService.cardioOverlapDedup —
--      we mirror that contract on the server.
--   4. League points: +50 (.workout source) + graduated cardio bonus.
--      Cardio bonus formula (Fitness Expert sign-off, FITNESS_EXPERT §5):
--         points = round(base_per_km × km × intensity_multiplier)
--      base_per_km: walk=3, run=5, hike=4, indoor_cycle=1.5,
--                   outdoor_cycle=1.0, rowing=4
--      intensity_multiplier:
--         no HR  → 1.00 (fairness for users without wearable)
--         <Z2    → 0.80 (avg_hr <110)
--         Z2     → 1.00 (110–149)
--         Z3     → 1.15 (150–164)
--         Z4+    → 1.25 (165+)
--      junk-session penalty: × 0.5 if duration < 10 min
--      daily cap: cardio_bonus per day capped at +50 (= 1 strength session
--      worth of bonus). Calls add_league_points which has its own
--      ledger-backed cap enforcement (Sprint 3 #20260717).
--   5. Friend feed: post_cardio_activity called only when goal_achieved
--      (otherwise routine sessions don't spam the feed).
--   6. RETURN the new workout UUID for client-side recap.
--
-- IDOR-safe: NEVER takes p_user_id. auth.uid() is the only user binding.
-- All other identifying fields come from p_payload (a JSONB envelope).
--
-- Idempotent: re-running the same external_id is a no-op (second call
-- returns the existing UUID instead of inserting a duplicate).
-- =============================================================================

BEGIN;

-- Drop ALL overloads before CREATE OR REPLACE (Supabase invariant #38).
DROP FUNCTION IF EXISTS public.record_cardio_workout(JSONB);
DROP FUNCTION IF EXISTS public.record_cardio_workout(JSON);

CREATE OR REPLACE FUNCTION public.record_cardio_workout(p_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id        UUID := auth.uid();
    v_external_id      TEXT;
    v_existing_id      UUID;
    v_new_id           UUID;
    v_started_at       TIMESTAMPTZ;
    v_completed_at     TIMESTAMPTZ;
    v_distance_m       DOUBLE PRECISION;
    v_duration_s       DOUBLE PRECISION;
    v_avg_hr           INT;
    v_activity         TEXT;
    v_goal_achieved    BOOLEAN;
    v_distance_km      NUMERIC;
    v_duration_min     NUMERIC;
    v_base             NUMERIC;
    v_intensity        NUMERIC;
    v_cardio_bonus     INT;
    v_today_bonus_used INT;
    v_today_start_utc  TIMESTAMPTZ;
    v_caller_tz        TEXT;
BEGIN
    -- 1. Authentication --------------------------------------------------------
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- 2. Extract required fields from payload ----------------------------------
    v_external_id := COALESCE(p_payload->>'external_id', gen_random_uuid()::TEXT);
    v_started_at  := COALESCE((p_payload->>'started_at')::TIMESTAMPTZ, NOW());
    v_completed_at := COALESCE((p_payload->>'completed_at')::TIMESTAMPTZ, NOW());
    v_distance_m  := COALESCE((p_payload->>'distance_meters')::DOUBLE PRECISION, 0);
    v_duration_s  := COALESCE((p_payload->>'duration_seconds')::DOUBLE PRECISION, 0);
    v_avg_hr      := COALESCE((p_payload->>'average_heart_rate')::INT, 0);
    v_activity    := LOWER(COALESCE(p_payload->>'activity_type', 'unknown'));
    v_goal_achieved := COALESCE((p_payload->>'goal_achieved')::BOOLEAN, FALSE);

    -- 3. Idempotency check (double-tap on Finish) -----------------------------
    SELECT id INTO v_existing_id
    FROM public.cardio_workouts
    WHERE user_id = v_caller_id
      AND source = 'fit33'
      AND external_id = v_external_id
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        RETURN v_existing_id;
    END IF;

    -- 4. Insert the new fit33 row ---------------------------------------------
    INSERT INTO public.cardio_workouts (
        user_id, source, origin_app, external_id,
        activity_type, workout_name,
        started_at, completed_at,
        duration_seconds, distance_meters, calories_burned,
        average_pace, best_pace, average_speed, max_speed,
        average_heart_rate, max_heart_rate,
        cadence, average_power,
        total_elevation_gain,
        goal_type, goal_value, goal_achieved,
        polyline_native, splits_native_json,
        gps_avg_accuracy_m, weather_json,
        route_coordinates,
        created_at
    )
    VALUES (
        v_caller_id, 'fit33', 'fit33', v_external_id,
        v_activity,
        p_payload->>'workout_name',
        v_started_at, v_completed_at,
        v_duration_s, v_distance_m,
        COALESCE((p_payload->>'calories_burned')::DOUBLE PRECISION, 0),
        COALESCE((p_payload->>'average_pace')::DOUBLE PRECISION, NULL),
        COALESCE((p_payload->>'best_pace')::DOUBLE PRECISION, NULL),
        COALESCE((p_payload->>'average_speed')::DOUBLE PRECISION, NULL),
        COALESCE((p_payload->>'max_speed')::DOUBLE PRECISION, NULL),
        NULLIF(v_avg_hr, 0),
        COALESCE((p_payload->>'max_heart_rate')::INT, NULL),
        COALESCE((p_payload->>'cadence')::INT, NULL),
        COALESCE((p_payload->>'average_power')::INT, NULL),
        COALESCE((p_payload->>'total_elevation_gain')::DOUBLE PRECISION, 0),
        p_payload->>'goal_type',
        COALESCE((p_payload->>'goal_value')::DOUBLE PRECISION, NULL),
        v_goal_achieved,
        p_payload->>'polyline_native',
        p_payload->'splits_native_json',
        COALESCE((p_payload->>'gps_avg_accuracy_m')::REAL, NULL),
        p_payload->'weather_json',
        p_payload->>'route_coordinates',
        NOW()
    )
    RETURNING id INTO v_new_id;

    -- 5. Same-origin dedup (delete any older 'fit33' row that overlaps) -------
    -- This guards against a rapid-fire double save of the same physical
    -- session (e.g. user double-tapped End). The newer (just-inserted) row
    -- wins because it has the most up-to-date data.
    DELETE FROM public.cardio_workouts old
    WHERE old.user_id = v_caller_id
      AND old.origin_app = 'fit33'
      AND old.id <> v_new_id
      AND old.started_at < v_completed_at
      AND v_started_at < old.completed_at
      AND (
          EXTRACT(EPOCH FROM (
              LEAST(old.completed_at, v_completed_at)
              - GREATEST(old.started_at, v_started_at)
          )) * 2
      ) >= EXTRACT(EPOCH FROM (
          GREATEST(
              old.completed_at - old.started_at,
              v_completed_at - v_started_at
          )
      ));

    -- 6. Cross-origin Strava merge --------------------------------------------
    -- If a Strava row already covers the same physical session (Strava
    -- webhook arrived first, e.g. user wore an Apple Watch that synced to
    -- Strava 30s before they tapped Save in Fit33), keep the fit33 row and
    -- delete the Strava one. Native has the route + already fired XP /
    -- quest verify / push. The opposite case (Strava arrives AFTER fit33)
    -- is guarded inside strava-webhook/index.ts.
    DELETE FROM public.cardio_workouts strava
    WHERE strava.user_id = v_caller_id
      AND strava.origin_app = 'strava'
      AND strava.id <> v_new_id
      AND strava.started_at < v_completed_at
      AND v_started_at < strava.completed_at
      AND (
          EXTRACT(EPOCH FROM (
              LEAST(strava.completed_at, v_completed_at)
              - GREATEST(strava.started_at, v_started_at)
          )) * 2
      ) >= EXTRACT(EPOCH FROM (
          GREATEST(
              strava.completed_at - strava.started_at,
              v_completed_at - v_started_at
          )
      ));

    -- 7. League points fanout: workout (+50, capped server-side) -------------
    -- add_league_points enforces per-source caps via league_point_source_caps
    -- (Sprint 3 #20260717). No-op silently if the user is over cap.
    BEGIN
        PERFORM add_league_points(
            v_caller_id,
            50,
            'workout',
            'cardio_native:' || v_new_id::TEXT
        );
    EXCEPTION WHEN OTHERS THEN
        -- League point award is best-effort; never fail the cardio save.
        RAISE NOTICE 'record_cardio_workout: workout LP award failed: %', SQLERRM;
    END;

    -- 8. Cardio bonus (graduated formula) ------------------------------------
    v_distance_km  := v_distance_m / 1000.0;
    v_duration_min := v_duration_s / 60.0;

    v_base := CASE v_activity
        WHEN 'walk'           THEN 3.0
        WHEN 'walking'        THEN 3.0
        WHEN 'run'            THEN 5.0
        WHEN 'running'        THEN 5.0
        WHEN 'outdoor_run'    THEN 5.0
        WHEN 'hike'           THEN 4.0
        WHEN 'hiking'         THEN 4.0
        WHEN 'indoor_cycle'   THEN 1.5
        WHEN 'outdoor_cycle'  THEN 1.0
        WHEN 'cycling'        THEN 1.0
        WHEN 'rowing'         THEN 4.0
        ELSE 0
    END;

    v_intensity := CASE
        WHEN v_avg_hr = 0          THEN 1.0
        WHEN v_avg_hr < 110        THEN 0.8
        WHEN v_avg_hr < 150        THEN 1.0
        WHEN v_avg_hr < 165        THEN 1.15
        ELSE                            1.25
    END;

    -- Junk-session penalty (under-10-minute completions)
    IF v_duration_min < 10 THEN
        v_intensity := v_intensity * 0.5;
    END IF;

    v_cardio_bonus := GREATEST(0, ROUND(v_base * v_distance_km * v_intensity)::INT);

    -- Per-day cardio bonus cap (+50 / day = 1 strength session worth)
    v_caller_tz := COALESCE(p_payload->>'timezone', 'UTC');
    BEGIN
        v_today_start_utc := (date_trunc('day', NOW() AT TIME ZONE v_caller_tz)) AT TIME ZONE v_caller_tz;
    EXCEPTION WHEN OTHERS THEN
        v_today_start_utc := date_trunc('day', NOW());
    END;

    -- Read prior cardio_bonus awards from the league_point_awards ledger if it
    -- exists; otherwise fall back to 0 and let `add_league_points` handle the
    -- cap. The Sprint-3 league pipeline keeps a `league_point_awards` ledger.
    BEGIN
        SELECT COALESCE(SUM(points), 0) INTO v_today_bonus_used
        FROM public.league_point_awards
        WHERE user_id = v_caller_id
          AND source = 'cardio_bonus'
          AND created_at >= v_today_start_utc;
    EXCEPTION WHEN undefined_table OR undefined_column THEN
        v_today_bonus_used := 0;
    END;

    v_cardio_bonus := LEAST(v_cardio_bonus, GREATEST(0, 50 - COALESCE(v_today_bonus_used, 0)));

    IF v_cardio_bonus > 0 THEN
        BEGIN
            PERFORM add_league_points(
                v_caller_id,
                v_cardio_bonus,
                'cardio_bonus',
                v_activity || ':' || v_new_id::TEXT
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'record_cardio_workout: cardio_bonus LP award failed: %', SQLERRM;
        END;
    END IF;

    -- 9. Friend feed (only when the user actually hit their goal) ------------
    IF v_goal_achieved THEN
        BEGIN
            PERFORM post_cardio_activity(
                v_new_id::TEXT,
                v_activity,
                v_duration_s::INT,
                v_distance_m,
                COALESCE((p_payload->>'calories_burned')::INT, 0),
                NULLIF(v_avg_hr, 0),
                COALESCE((p_payload->>'xp_earned')::INT, 0)
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'record_cardio_workout: friend feed post failed: %', SQLERRM;
        END;
    END IF;

    -- 10. PR detection (best-effort) -----------------------------------------
    BEGIN
        IF (SELECT 1 FROM pg_proc WHERE proname = '_check_cardio_prs' LIMIT 1) IS NOT NULL THEN
            PERFORM public._check_cardio_prs(v_caller_id, v_new_id);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'record_cardio_workout: PR check failed: %', SQLERRM;
    END;

    RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_cardio_workout(JSONB) TO authenticated;

COMMENT ON FUNCTION public.record_cardio_workout(JSONB) IS
    'Cardio Redesign Phase 1: single-transaction native cardio save. Inserts the row, dedups same-origin and cross-origin (Strava merge), awards graduated league points (workout +50 + cardio_bonus capped at +50/day), fires friend feed if goal_achieved, runs PR detection. IDOR-safe (auth.uid() only). Idempotent on (user_id, source=fit33, external_id).';

-- League points source registration ------------------------------------------
-- Register 'cardio_bonus' in the source caps policy table if it exists. The
-- Sprint 3 release introduced league_point_source_caps; if the table doesn't
-- exist yet (older deploy), this is a silent no-op.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'league_point_source_caps'
    ) THEN
        INSERT INTO public.league_point_source_caps (
            source, daily_cap, weekly_cap, lifetime_cap,
            description
        )
        VALUES (
            'cardio_bonus', 50, 200, NULL,
            'Cardio Redesign Phase 1: graduated bonus on native cardio rows. base_per_km × km × intensity_multiplier; daily cap 50, weekly cap 200.'
        )
        ON CONFLICT (source) DO UPDATE SET
            daily_cap   = EXCLUDED.daily_cap,
            weekly_cap  = EXCLUDED.weekly_cap,
            description = EXCLUDED.description;
    END IF;
END $$;

COMMIT;
