-- ============================================================================
-- Migration: Re-assert RLS policies for workout intelligence tables
-- Date: 2026-04-25
-- Agent: Data & Backend (primary), Infra & Security (RLS review)
--
-- Why:
--   New users completing onboarding hit PostgrestError 42501
--   ("new row violates row-level security policy") on EVERY workout
--   intelligence write: workout_context, user_performance_trends,
--   set_completion_patterns, exercise_user_effectiveness,
--   workout_time_performance, weekly_volume_trends,
--   equipment_proficiency, collaborative_workout_data.
--
--   Two root causes:
--   1) The Core Data User.id was being created with a fresh UUID()
--      during `createUser()` in onboarding instead of the Supabase
--      auth.uid() — fixed in Fit33/UserManager.swift.
--   2) Some of the policies above were only applied via standalone
--      docs/QUICK_WINS scripts that may never have been deployed to
--      production. This migration re-asserts them idempotently.
--
-- Idempotent: drops policies before recreating; uses IF NOT EXISTS
-- where supported; safe to run multiple times. Wrapped in a single
-- transaction.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. workout_context
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_insert_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_update_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_delete_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "Users can view own context" ON workout_context;
DROP POLICY IF EXISTS "Users can insert own context" ON workout_context;

CREATE POLICY "users_select_own_workout_context" ON workout_context
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_workout_context" ON workout_context
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_workout_context" ON workout_context
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_workout_context" ON workout_context
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_context_user_id ON workout_context (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 2. user_performance_trends
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE user_performance_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_insert_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_update_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_delete_own_performance_trends" ON user_performance_trends;

CREATE POLICY "users_select_own_performance_trends" ON user_performance_trends
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_performance_trends" ON user_performance_trends
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_performance_trends" ON user_performance_trends
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_performance_trends" ON user_performance_trends
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_performance_trends_user_id ON user_performance_trends (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 3. set_completion_patterns
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE set_completion_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_insert_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_update_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_delete_own_set_patterns" ON set_completion_patterns;

CREATE POLICY "users_select_own_set_patterns" ON set_completion_patterns
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_set_patterns" ON set_completion_patterns
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_set_patterns" ON set_completion_patterns
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_set_patterns" ON set_completion_patterns
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_set_completion_patterns_user_id ON set_completion_patterns (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 4. exercise_user_effectiveness
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE exercise_user_effectiveness ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_insert_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_update_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_delete_own_effectiveness" ON exercise_user_effectiveness;

CREATE POLICY "users_select_own_effectiveness" ON exercise_user_effectiveness
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_effectiveness" ON exercise_user_effectiveness
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_effectiveness" ON exercise_user_effectiveness
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_effectiveness" ON exercise_user_effectiveness
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_exercise_user_effectiveness_user_id ON exercise_user_effectiveness (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 5. workout_time_performance
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE workout_time_performance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_insert_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_update_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_delete_own_time_performance" ON workout_time_performance;

CREATE POLICY "users_select_own_time_performance" ON workout_time_performance
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_time_performance" ON workout_time_performance
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_time_performance" ON workout_time_performance
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_time_performance" ON workout_time_performance
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_time_performance_user_id ON workout_time_performance (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 6. weekly_volume_trends
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE weekly_volume_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_insert_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_update_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_delete_own_volume_trends" ON weekly_volume_trends;

CREATE POLICY "users_select_own_volume_trends" ON weekly_volume_trends
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_volume_trends" ON weekly_volume_trends
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_volume_trends" ON weekly_volume_trends
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_volume_trends" ON weekly_volume_trends
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_weekly_volume_trends_user_id ON weekly_volume_trends (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 7. equipment_proficiency
-- (was only created via QUICK_WINS.sql — may not be in prod)
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS equipment_proficiency (
    user_id UUID NOT NULL,
    equipment_type TEXT NOT NULL,
    first_used DATE DEFAULT CURRENT_DATE,
    last_used DATE DEFAULT CURRENT_DATE,
    times_used INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, equipment_type)
);

CREATE INDEX IF NOT EXISTS idx_proficiency_user ON equipment_proficiency(user_id);

ALTER TABLE equipment_proficiency ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_select_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_insert_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_update_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_delete_own_proficiency" ON equipment_proficiency;

CREATE POLICY "users_select_own_proficiency" ON equipment_proficiency
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_proficiency" ON equipment_proficiency
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_proficiency" ON equipment_proficiency
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_proficiency" ON equipment_proficiency
    FOR DELETE TO authenticated USING (user_id = auth.uid());

-- The increment_equipment_usage RPC is invoked with the caller's auth
-- context. Keep it SECURITY INVOKER so RLS is enforced on its INSERT.
CREATE OR REPLACE FUNCTION increment_equipment_usage(
    p_user_id UUID,
    p_equipment_type TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    -- Defensive: the RLS policy already enforces user_id = auth.uid(),
    -- but a clear mismatch should fail fast with a clean error.
    IF p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'increment_equipment_usage: p_user_id (%) does not match auth.uid() (%)', p_user_id, auth.uid()
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO equipment_proficiency (user_id, equipment_type, times_used, last_used)
    VALUES (p_user_id, p_equipment_type, 1, CURRENT_DATE)
    ON CONFLICT (user_id, equipment_type)
    DO UPDATE SET
        times_used = equipment_proficiency.times_used + 1,
        last_used = CURRENT_DATE,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION increment_equipment_usage(UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 8. collaborative_workout_data
-- (originally defined in docs/COLLABORATIVE_LEARNING_SCHEMA.sql which
--  may not have been deployed)
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "Authenticated users can read workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_select_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_insert_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_update_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_delete_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "authenticated_read_collab_workout" ON collaborative_workout_data;

-- Users can manage their own rows
CREATE POLICY "users_insert_own_collab_workout" ON collaborative_workout_data
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_collab_workout" ON collaborative_workout_data
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_collab_workout" ON collaborative_workout_data
    FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Aggregate read access (collaborative analysis requires reading peers).
CREATE POLICY "authenticated_read_collab_workout" ON collaborative_workout_data
    FOR SELECT TO authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_collab_workout_user_id ON collaborative_workout_data (user_id);

COMMIT;

-- ============================================================================
-- VERIFICATION (run manually after migration):
--
--   SELECT schemaname, tablename, policyname, cmd
--   FROM pg_policies
--   WHERE tablename IN (
--     'workout_context','user_performance_trends','set_completion_patterns',
--     'exercise_user_effectiveness','workout_time_performance',
--     'weekly_volume_trends','equipment_proficiency','collaborative_workout_data'
--   )
--   ORDER BY tablename, cmd, policyname;
--
-- Expected: 4 owner-scoped policies per table (SELECT/INSERT/UPDATE/DELETE),
-- plus 1 extra SELECT policy on collaborative_workout_data for peer reads.
-- ============================================================================
