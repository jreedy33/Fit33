-- Bug-intel sweep Cluster B: canonicalize RLS on health-data tables.
--
-- Problem: `cardio_workouts` and `daily_activity_summary` are written by
-- HealthDataService (HealthKit + Fitbit + Strava + WHOOP sync paths) and
-- by SupabaseManager (manual edit / auto-gen). Bug-intel reports show
-- 42501 "new row violates row-level security policy" errors for these
-- tables, but no canonical RLS migration exists in this repo (the
-- policies live only on the remote DB). This migration snapshots the
-- policy shape into version control so drift is impossible going
-- forward, matching the shape we already applied to `step_tracking`.
--
-- Policy shape (same for both tables):
--   ENABLE ROW LEVEL SECURITY
--   SELECT: auth.uid() = user_id
--   INSERT: WITH CHECK (auth.uid() = user_id)
--   UPDATE: USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)
--   DELETE: USING (auth.uid() = user_id)
--
-- All policies are DROP-IF-EXISTS + CREATE to stay idempotent per
-- supabase-rules §4 (migration idempotency).

BEGIN;

-- =========================================================================
-- cardio_workouts
-- =========================================================================

ALTER TABLE IF EXISTS cardio_workouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cardio_workouts_select_own" ON cardio_workouts;
DROP POLICY IF EXISTS "cardio_workouts_insert_own" ON cardio_workouts;
DROP POLICY IF EXISTS "cardio_workouts_update_own" ON cardio_workouts;
DROP POLICY IF EXISTS "cardio_workouts_delete_own" ON cardio_workouts;
-- Also drop any legacy names that may have been applied via the dashboard.
DROP POLICY IF EXISTS "Users can read own cardio workouts" ON cardio_workouts;
DROP POLICY IF EXISTS "Users can insert own cardio workouts" ON cardio_workouts;
DROP POLICY IF EXISTS "Users can update own cardio workouts" ON cardio_workouts;
DROP POLICY IF EXISTS "Users can delete own cardio workouts" ON cardio_workouts;

CREATE POLICY "cardio_workouts_select_own"
    ON cardio_workouts FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "cardio_workouts_insert_own"
    ON cardio_workouts FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "cardio_workouts_update_own"
    ON cardio_workouts FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "cardio_workouts_delete_own"
    ON cardio_workouts FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- daily_activity_summary
-- =========================================================================

ALTER TABLE IF EXISTS daily_activity_summary ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily_activity_summary_select_own" ON daily_activity_summary;
DROP POLICY IF EXISTS "daily_activity_summary_insert_own" ON daily_activity_summary;
DROP POLICY IF EXISTS "daily_activity_summary_update_own" ON daily_activity_summary;
DROP POLICY IF EXISTS "daily_activity_summary_delete_own" ON daily_activity_summary;
DROP POLICY IF EXISTS "Users can read own daily activity" ON daily_activity_summary;
DROP POLICY IF EXISTS "Users can insert own daily activity" ON daily_activity_summary;
DROP POLICY IF EXISTS "Users can update own daily activity" ON daily_activity_summary;
DROP POLICY IF EXISTS "Users can delete own daily activity" ON daily_activity_summary;

CREATE POLICY "daily_activity_summary_select_own"
    ON daily_activity_summary FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "daily_activity_summary_insert_own"
    ON daily_activity_summary FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "daily_activity_summary_update_own"
    ON daily_activity_summary FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "daily_activity_summary_delete_own"
    ON daily_activity_summary FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- healthkit_sleep (bonus audit — HealthDataService writes here too)
-- =========================================================================

ALTER TABLE IF EXISTS healthkit_sleep ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "healthkit_sleep_select_own" ON healthkit_sleep;
DROP POLICY IF EXISTS "healthkit_sleep_insert_own" ON healthkit_sleep;
DROP POLICY IF EXISTS "healthkit_sleep_update_own" ON healthkit_sleep;
DROP POLICY IF EXISTS "healthkit_sleep_delete_own" ON healthkit_sleep;

CREATE POLICY "healthkit_sleep_select_own"
    ON healthkit_sleep FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "healthkit_sleep_insert_own"
    ON healthkit_sleep FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "healthkit_sleep_update_own"
    ON healthkit_sleep FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "healthkit_sleep_delete_own"
    ON healthkit_sleep FOR DELETE
    USING (auth.uid() = user_id);

COMMIT;

-- Sanity check — confirm all three tables have RLS enabled.
DO $$
DECLARE
    missing_rls TEXT;
BEGIN
    SELECT string_agg(c.relname, ', ')
      INTO missing_rls
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN ('cardio_workouts', 'daily_activity_summary', 'healthkit_sleep')
       AND c.relrowsecurity = false;
    IF missing_rls IS NOT NULL THEN
        RAISE WARNING 'Tables missing RLS after migration: %', missing_rls;
    ELSE
        RAISE NOTICE '[20260511] RLS verified on cardio_workouts, daily_activity_summary, healthkit_sleep.';
    END IF;
END $$;
