-- Migration: Add RLS policies for 7 analytics tables
-- Date: 2026-03-20
-- Agent: Data & Backend (primary), Infra & Security (policy review)
-- Note: PostgreSQL CREATE POLICY does not support IF NOT EXISTS,
--       so we DROP IF EXISTS first to make this idempotent.

BEGIN;

-- ─── 1. workout_context ───

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_insert_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_update_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_delete_own_workout_context" ON workout_context;

CREATE POLICY "users_select_own_workout_context" ON workout_context FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_workout_context" ON workout_context FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_workout_context" ON workout_context FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_workout_context" ON workout_context FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_context_user_id ON workout_context (user_id);

-- ─── 2. user_performance_trends ───

ALTER TABLE user_performance_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_insert_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_update_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_delete_own_performance_trends" ON user_performance_trends;

CREATE POLICY "users_select_own_performance_trends" ON user_performance_trends FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_performance_trends" ON user_performance_trends FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_performance_trends" ON user_performance_trends FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_performance_trends" ON user_performance_trends FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_performance_trends_user_id ON user_performance_trends (user_id);

-- ─── 3. set_completion_patterns ───

ALTER TABLE set_completion_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_insert_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_update_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_delete_own_set_patterns" ON set_completion_patterns;

CREATE POLICY "users_select_own_set_patterns" ON set_completion_patterns FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_set_patterns" ON set_completion_patterns FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_set_patterns" ON set_completion_patterns FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_set_patterns" ON set_completion_patterns FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_set_completion_patterns_user_id ON set_completion_patterns (user_id);

-- ─── 4. user_strength_ratios ───

ALTER TABLE user_strength_ratios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_strength_ratios" ON user_strength_ratios;
DROP POLICY IF EXISTS "users_insert_own_strength_ratios" ON user_strength_ratios;
DROP POLICY IF EXISTS "users_update_own_strength_ratios" ON user_strength_ratios;
DROP POLICY IF EXISTS "users_delete_own_strength_ratios" ON user_strength_ratios;

CREATE POLICY "users_select_own_strength_ratios" ON user_strength_ratios FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_strength_ratios" ON user_strength_ratios FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_strength_ratios" ON user_strength_ratios FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_strength_ratios" ON user_strength_ratios FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_strength_ratios_user_id ON user_strength_ratios (user_id);

-- ─── 5. exercise_user_effectiveness ───

ALTER TABLE exercise_user_effectiveness ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_insert_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_update_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_delete_own_effectiveness" ON exercise_user_effectiveness;

CREATE POLICY "users_select_own_effectiveness" ON exercise_user_effectiveness FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_effectiveness" ON exercise_user_effectiveness FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_effectiveness" ON exercise_user_effectiveness FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_effectiveness" ON exercise_user_effectiveness FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_exercise_user_effectiveness_user_id ON exercise_user_effectiveness (user_id);

-- ─── 6. workout_time_performance ───

ALTER TABLE workout_time_performance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_insert_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_update_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_delete_own_time_performance" ON workout_time_performance;

CREATE POLICY "users_select_own_time_performance" ON workout_time_performance FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_time_performance" ON workout_time_performance FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_time_performance" ON workout_time_performance FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_time_performance" ON workout_time_performance FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_time_performance_user_id ON workout_time_performance (user_id);

-- ─── 7. weekly_volume_trends ───

ALTER TABLE weekly_volume_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_insert_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_update_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_delete_own_volume_trends" ON weekly_volume_trends;

CREATE POLICY "users_select_own_volume_trends" ON weekly_volume_trends FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_volume_trends" ON weekly_volume_trends FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_volume_trends" ON weekly_volume_trends FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users_delete_own_volume_trends" ON weekly_volume_trends FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_weekly_volume_trends_user_id ON weekly_volume_trends (user_id);

COMMIT;
