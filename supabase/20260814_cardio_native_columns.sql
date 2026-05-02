-- =============================================================================
-- cardio_workouts: native walk + run columns (Cardio Redesign Phase 1)
-- =============================================================================
-- The Cardio Redesign ships native walk + run as first-class activities with
-- their own engine (`OutdoorCardioManager`) — independent of the Strava sync
-- path. Native runs need to persist:
--
--   * `polyline_native`      — Google-encoded polyline string compressed from
--                              the raw `[CLLocationCoordinate2D]` route
--                              (typically ~10× smaller than raw lat/lng JSON).
--                              Strava-sourced rows continue to use the
--                              existing `polyline_summary` column instead.
--   * `splits_native_json`   — per-km / per-mile split array from
--                              RunningManager.splits. Each element:
--                                {
--                                  "kilometer" | "mile": Int,
--                                  "time": Double (seconds),
--                                  "pace": Double (seconds per km),
--                                  "elevation_gain": Double (meters),
--                                  "avg_hr": Int,
--                                  "is_manual": Bool
--                                }
--                              Strava splits remain in `splits_json`.
--   * `gps_avg_accuracy_m`   — average horizontalAccuracy seen during the
--                              session. Powers leaderboard "junk run" filter.
--   * `weather_json`         — temp / wind / conditions snapshot at start
--                              (keys: temp_c, condition, wind_kph,
--                              humidity_pct). Powers "you ran your fastest
--                              5K despite 90°F heat" recap flavor.
--
-- Also widens the `goal_type` CHECK constraint to accept the new `'pace'`
-- mode (Goal-Pace runs from the redesigned Goal Setup sheet).
--
-- Idempotent — uses `IF NOT EXISTS` and conditional CHECK rebuild so re-runs
-- are safe (Supabase invariant: idempotency on every migration).
-- =============================================================================

BEGIN;

-- 1. New native cardio columns ------------------------------------------------
ALTER TABLE public.cardio_workouts
    ADD COLUMN IF NOT EXISTS polyline_native       TEXT,
    ADD COLUMN IF NOT EXISTS splits_native_json    JSONB,
    ADD COLUMN IF NOT EXISTS gps_avg_accuracy_m    REAL,
    ADD COLUMN IF NOT EXISTS weather_json          JSONB;

COMMENT ON COLUMN public.cardio_workouts.polyline_native IS
    'Google-encoded polyline string for native (origin_app=fit33) outdoor cardio sessions. Encoded from CLLocationCoordinate2D via the Google polyline algorithm — ~10× smaller than raw JSON lat/lng. NULL for indoor / Strava / HK-imported sessions.';
COMMENT ON COLUMN public.cardio_workouts.splits_native_json IS
    'Per-km/mile splits from RunningManager.splits. JSON array; each element: { kilometer | mile, time (sec), pace (sec/km), elevation_gain (m), avg_hr (bpm), is_manual (bool) }. NULL for Strava-sourced rows (use splits_json).';
COMMENT ON COLUMN public.cardio_workouts.gps_avg_accuracy_m IS
    'Average horizontalAccuracy in meters across the session''s location samples. Used by leaderboard / quest verification to filter junk-GPS runs (>30m avg).';
COMMENT ON COLUMN public.cardio_workouts.weather_json IS
    'Weather snapshot at start time. Keys: temp_c (Float), condition (String), wind_kph (Float), humidity_pct (Int). Optional — only populated when WeatherKit is opted in.';

-- 2. Widen goal_type CHECK to include 'pace' ----------------------------------
-- Drop the existing CHECK defensively (name varies across deploys) and re-add
-- with the widened set. Use a safe DO block so this migration succeeds whether
-- or not the prior CHECK existed.
DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    -- Find any existing check constraint on goal_type
    SELECT con.conname
    INTO v_constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'cardio_workouts'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%goal_type%'
    LIMIT 1;

    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE public.cardio_workouts DROP CONSTRAINT IF EXISTS %I',
            v_constraint_name
        );
    END IF;
END $$;

ALTER TABLE public.cardio_workouts
    ADD CONSTRAINT cardio_workouts_goal_type_check
    CHECK (
        goal_type IS NULL OR goal_type IN (
            'open',
            'time',
            'distance',
            'calories',
            'pace'
        )
    );

-- 3. Helpful index for native-only history queries -----------------------------
-- The redesigned recap surface fetches the user's native runs separately
-- (their fit33 row is the canonical source-of-truth, even when Strava also
-- has a copy). Partial index keeps it cheap.
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_native_recent
    ON public.cardio_workouts (user_id, started_at DESC)
    WHERE origin_app = 'fit33';

COMMIT;
