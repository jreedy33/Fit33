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
-- sleep_logs (bonus audit — HealthDataService writes here too)
--
-- NOTE 2026-04-23: original draft called this table `healthkit_sleep` but
-- the canonical table in this project is `sleep_logs` (see
-- HealthDataService.swift `.from("sleep_logs")`). Wrapped in a
-- to_regclass existence check so this whole section is a no-op on
-- environments that don't have the table yet (staging / fresh clone).
-- =========================================================================

DO $$
BEGIN
    IF to_regclass('public.sleep_logs') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY';

        EXECUTE 'DROP POLICY IF EXISTS "sleep_logs_select_own" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "sleep_logs_insert_own" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "sleep_logs_update_own" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "sleep_logs_delete_own" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "Users can read own sleep logs" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "Users can insert own sleep logs" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "Users can update own sleep logs" ON sleep_logs';
        EXECUTE 'DROP POLICY IF EXISTS "Users can delete own sleep logs" ON sleep_logs';

        EXECUTE $p$CREATE POLICY "sleep_logs_select_own"
            ON sleep_logs FOR SELECT
            USING (auth.uid() = user_id)$p$;

        EXECUTE $p$CREATE POLICY "sleep_logs_insert_own"
            ON sleep_logs FOR INSERT
            WITH CHECK (auth.uid() = user_id)$p$;

        EXECUTE $p$CREATE POLICY "sleep_logs_update_own"
            ON sleep_logs FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id)$p$;

        EXECUTE $p$CREATE POLICY "sleep_logs_delete_own"
            ON sleep_logs FOR DELETE
            USING (auth.uid() = user_id)$p$;

        RAISE NOTICE '[20260511] sleep_logs RLS policies applied.';
    ELSE
        RAISE NOTICE '[20260511] sleep_logs table not present — skipping.';
    END IF;
END $$;

COMMIT;

-- Sanity check — confirm each present table has RLS enabled. Tables not
-- yet provisioned in this environment are reported as "not present".
DO $$
DECLARE
    t TEXT;
    r RECORD;
BEGIN
    FOR t IN SELECT unnest(ARRAY['cardio_workouts', 'daily_activity_summary', 'sleep_logs']) LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            RAISE NOTICE '[20260511] % not present in this env — skipped.', t;
            CONTINUE;
        END IF;
        SELECT relrowsecurity INTO r
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = t;
        IF NOT r.relrowsecurity THEN
            RAISE WARNING '[20260511] Table % is missing RLS after migration.', t;
        ELSE
            RAISE NOTICE '[20260511] RLS verified on %.', t;
        END IF;
    END LOOP;
END $$;
