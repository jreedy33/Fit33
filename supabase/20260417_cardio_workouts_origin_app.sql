-- =============================================================================
-- cardio_workouts: track the TRUE origin of every workout row
-- =============================================================================
-- When a third-party app (Strava, Nike Run Club, Peloton, Garmin, Zwift, etc.)
-- writes a workout to Apple Health and Fit33 pulls it in, we currently lose
-- the original source: the row is saved with source='healthkit' and the
-- dashboard renders a generic "Apple Health" badge.
--
-- This migration adds an `origin_app` column that stores the canonical origin
-- key (e.g. 'strava', 'nike_run_club', 'peloton', 'garmin', 'apple_watch', ...)
-- independent of the transport (`source`).
--
-- With this column in place the app can:
--   1. Render the correct third-party badge for EVERY app that writes to
--      HealthKit, not just ones we have OAuth for.
--   2. When a user connects an OAuth integration (Strava, Fitbit, WHOOP,
--      Oura, ...), skip HealthKit saves for that origin and/or delete any
--      stale HealthKit-imported copies, so the OAuth feed is the single
--      source of truth (no duplicate rows for the same run).
-- =============================================================================

ALTER TABLE public.cardio_workouts
ADD COLUMN IF NOT EXISTS origin_app TEXT;

COMMENT ON COLUMN public.cardio_workouts.origin_app IS
  'Canonical key for the app that originally authored this workout (e.g. strava, nike_run_club, peloton, garmin, apple_watch, fit33). Independent of the `source` column which tracks the transport (strava/fitbit/whoop/oura/healthkit/fit33).';

-- Speeds up backfill/dedupe queries run on OAuth connect, e.g.
-- DELETE FROM cardio_workouts WHERE user_id = ? AND source='healthkit' AND origin_app='strava';
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_user_origin_source
  ON public.cardio_workouts (user_id, origin_app, source);

-- Best-effort backfill for existing rows: derive origin_app from workout_name
-- prefix written by HealthDataService.saveHealthKitWorkout prior to this
-- migration ("Strava Running", "Nike Run Club Run", "Apple Watch Cycling").
-- Only touches rows where origin_app IS NULL so it is safe to re-run.
UPDATE public.cardio_workouts
SET origin_app = CASE
    WHEN source = 'strava' THEN 'strava'
    WHEN source = 'fitbit' THEN 'fitbit'
    WHEN source = 'whoop'  THEN 'whoop'
    WHEN source = 'oura'   THEN 'oura'
    WHEN source = 'fit33'  THEN 'fit33'
    WHEN workout_name ILIKE 'Strava %'          THEN 'strava'
    WHEN workout_name ILIKE 'Nike Run Club %'   THEN 'nike_run_club'
    WHEN workout_name ILIKE 'Nike %'            THEN 'nike_run_club'
    WHEN workout_name ILIKE 'Peloton %'         THEN 'peloton'
    WHEN workout_name ILIKE 'Garmin %'          THEN 'garmin'
    WHEN workout_name ILIKE 'Zwift %'           THEN 'zwift'
    WHEN workout_name ILIKE 'Apple Watch %'     THEN 'apple_watch'
    WHEN workout_name ILIKE 'Watch %'           THEN 'apple_watch'
    WHEN workout_name ILIKE 'Fitbit %'          THEN 'fitbit'
    WHEN workout_name ILIKE 'WHOOP %'           THEN 'whoop'
    WHEN workout_name ILIKE 'Oura %'            THEN 'oura'
    ELSE NULL
END
WHERE origin_app IS NULL;
