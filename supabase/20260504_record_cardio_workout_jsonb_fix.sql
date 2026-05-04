-- =============================================================================
-- record_cardio_workout — route_coordinates JSONB cast hotfix
-- =============================================================================
-- The Cardio Redesign Phase-1 RPC (`20260815_record_cardio_workout_rpc.sql`)
-- inserted `p_payload->>'route_coordinates'` directly into `cardio_workouts`.
-- The `->>` operator returns TEXT but `cardio_workouts.route_coordinates` is
-- JSONB → every native cardio Save (with a route polyline) failed with:
--
--   ERROR: column "route_coordinates" is of type jsonb but expression is of type text
--
-- The iOS client (`SupabaseManager.saveCardioWorkout`) sends
-- `route_coordinates` as a JSON-encoded STRING inside the JSONB envelope (see
-- `CardioWorkoutData.routeCoordinatesJSON: String?`). We need to PARSE that
-- string back into JSONB before inserting it into the column.
--
-- This is a pure body change — NOT a schema change:
--   * Function signature unchanged: `record_cardio_workout(p_payload JSONB) RETURNS UUID`
--   * `cardio_workouts` table is NOT touched (no ALTER, no constraint change,
--     no REPLICA IDENTITY change, no publication change)
--   * Realtime subscriptions on `cardio_workouts` continue to fire on every
--     INSERT/UPDATE/DELETE exactly as before — the only difference is that
--     a row that USED to fail now succeeds, so realtime will fire MORE often
--     (which is the intended outcome — the cardio recap UI was the user
--     observable for this bug).
--   * SECURITY DEFINER, search_path, idempotency-by-external_id, dedup
--     branches, league-points fanout, friend-feed fanout, and PR detection
--     are all preserved verbatim.
--
-- Resolves: ed47235aacc85ca48e62488533eccab9 record_cardio_workout RPC route_coordinates type mismatch (crash) — 24 occ × 4 users
-- Resolves: dc1787c30c387f39f525a1d9ae22f4a9 Cardio recap save route_coordinates type mismatch (crash twin) — 24 occ × 4 users
-- Resolves: db636b01b92ebad2fa74167ecc5213ea Cardio recap save fails with route coordinates type error (log) — 11 occ × 2 users
-- Resolves: 791da679d303f736ffe558afd6222d35 Route coordinates type mismatch in RPC call (log twin) — 11 occ × 2 users
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
    -- Route coords / splits / weather are JSONB columns. The iOS client may
    -- send them as either:
    --   (a) a JSON-encoded STRING (legacy / current):
    --       "route_coordinates": "[{\"lat\":...,\"lng\":...},...]"
    --   (b) a native JSON ARRAY/OBJECT (forward-compat):
    --       "route_coordinates": [{"lat":...,"lng":...},...]
    -- We auto-detect via `jsonb_typeof` and parse the string variant. NULL
    -- and missing keys yield NULL JSONB (column is nullable).
    v_route_coords     JSONB;
    v_splits_native    JSONB;
    v_weather          JSONB;
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

    -- 2a. JSONB-safe extraction for route_coordinates / splits / weather ------
    -- Auto-detect string-vs-native shape. Falls through to NULL on
    -- malformed / empty / missing input. This is the actual fix for
    -- `column "route_coordinates" is of type jsonb but expression is of
    -- type text` (bug-intel ed47235a / db636b01 / 791da679 / dc1787c3).
    v_route_coords := CASE
        WHEN p_payload ? 'route_coordinates' = FALSE THEN NULL
        WHEN p_payload->'route_coordinates' = 'null'::jsonb THEN NULL
        WHEN jsonb_typeof(p_payload->'route_coordinates') = 'string' THEN
            CASE
                WHEN COALESCE(p_payload->>'route_coordinates', '') = '' THEN NULL
                ELSE
                    -- Cast string-content to JSONB. If the iOS client sent
                    -- malformed JSON (shouldn't — it goes through
                    -- JSONEncoder), the cast throws and the cardio save
                    -- aborts with a real signal — better than silently
                    -- inserting NULL and losing the route.
                    (p_payload->>'route_coordinates')::JSONB
            END
        ELSE p_payload->'route_coordinates'  -- already array/object/etc.
    END;

    v_splits_native := CASE
        WHEN p_payload ? 'splits_native_json' = FALSE THEN NULL
        WHEN p_payload->'splits_native_json' = 'null'::jsonb THEN NULL
        WHEN jsonb_typeof(p_payload->'splits_native_json') = 'string' THEN
            CASE
                WHEN COALESCE(p_payload->>'splits_native_json', '') = '' THEN NULL
                ELSE (p_payload->>'splits_native_json')::JSONB
            END
        ELSE p_payload->'splits_native_json'
    END;

    v_weather := CASE
        WHEN p_payload ? 'weather_json' = FALSE THEN NULL
        WHEN p_payload->'weather_json' = 'null'::jsonb THEN NULL
        WHEN jsonb_typeof(p_payload->'weather_json') = 'string' THEN
            CASE
                WHEN COALESCE(p_payload->>'weather_json', '') = '' THEN NULL
                ELSE (p_payload->>'weather_json')::JSONB
            END
        ELSE p_payload->'weather_json'
    END;

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
        v_splits_native,
        COALESCE((p_payload->>'gps_avg_accuracy_m')::REAL, NULL),
        v_weather,
        v_route_coords,
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
    'Cardio Redesign Phase 1: single-transaction native cardio save. Inserts the row, dedups same-origin and cross-origin (Strava merge), awards graduated league points (workout +50 + cardio_bonus capped at +50/day), fires friend feed if goal_achieved, runs PR detection. IDOR-safe (auth.uid() only). Idempotent on (user_id, source=fit33, external_id). 2026-05-04 hotfix: route_coordinates / splits_native_json / weather_json now correctly cast string-encoded JSON to JSONB before insert (bug-intel ed47235a / db636b01 / 791da679 / dc1787c3).';

-- =============================================================================
-- Audit: prove the function still has the correct signature and is reachable
-- =============================================================================

DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'record_cardio_workout'
      AND oidvectortypes(p.proargtypes) = 'jsonb';

    IF v_count <> 1 THEN
        RAISE EXCEPTION '[20260504_record_cardio_workout_jsonb_fix] FAILED: expected exactly 1 record_cardio_workout(jsonb) overload, got %', v_count;
    END IF;

    RAISE NOTICE '[20260504_record_cardio_workout_jsonb_fix] ✅ record_cardio_workout(JSONB) replaced; signature preserved.';
END $$;

-- =============================================================================
-- Bug-intel: replay Resolves: directives so the fingerprints flip to
-- `migration_resolved:20260504_record_cardio_workout_jsonb_fix` immediately
-- (rather than waiting for the next github-pr-webhook run). Wrapped in
-- IF EXISTS so this migration is safe to run on a fresh DB that hasn't
-- deployed the bug-intel pipeline yet.
-- =============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'mark_fingerprints_resolved_by_migration'
    ) THEN
        PERFORM public.mark_fingerprints_resolved_by_migration(
            '20260504_record_cardio_workout_jsonb_fix',
            ARRAY[
                'ed47235aacc85ca48e62488533eccab9',
                'dc1787c30c387f39f525a1d9ae22f4a9',
                'db636b01b92ebad2fa74167ecc5213ea',
                '791da679d303f736ffe558afd6222d35'
            ],
            'route_coordinates JSONB cast in record_cardio_workout RPC'
        );
    END IF;

    -- Phase 12.5 — stamp `latest_resolving_migration_at` so the 48h
    -- stale-fix grace filter applies to any post-deploy stale-client
    -- repeats (users on builds that haven't yet gotten this fix).
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'bug_intel_register_migration_deploy'
    ) THEN
        PERFORM public.bug_intel_register_migration_deploy(
            '20260504_record_cardio_workout_jsonb_fix',
            ARRAY[
                'ed47235aacc85ca48e62488533eccab9',
                'dc1787c30c387f39f525a1d9ae22f4a9',
                'db636b01b92ebad2fa74167ecc5213ea',
                '791da679d303f736ffe558afd6222d35'
            ]
        );
    END IF;
END $$;

-- PostgREST schema cache reload (Supabase invariant 19b) — strictly redundant
-- since the function signature is unchanged, but harmless and makes the
-- post-deploy contract explicit (the function body changed; clients see
-- the new behavior immediately).
NOTIFY pgrst, 'reload schema';

COMMIT;
