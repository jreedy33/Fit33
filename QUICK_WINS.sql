-- ============================================================================
-- QUICK WINS - EASY IMPLEMENTATION SQL
-- ============================================================================
-- Time: 5 minutes to run
-- Impact: Start collecting performance data immediately
-- 
-- What you get:
-- ✅ Exercise performance history (weight progression)
-- ✅ Workout temporal patterns (when users work out)
-- ✅ Equipment proficiency auto-tracking
-- ============================================================================

-- Table 1: Exercise Performance History
CREATE TABLE IF NOT EXISTS exercise_performance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    exercise_name TEXT NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    best_set_weight DOUBLE PRECISION,
    best_set_reps INT,
    total_sets INT,
    total_volume DOUBLE PRECISION,
    one_rep_max_estimate DOUBLE PRECISION,
    equipment_used TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_perf_history_user_exercise ON exercise_performance_history(user_id, exercise_name);
CREATE INDEX idx_perf_history_user_date ON exercise_performance_history(user_id, workout_date DESC);

ALTER TABLE exercise_performance_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own performance" ON exercise_performance_history 
    FOR SELECT TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own performance" ON exercise_performance_history 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

-- Table 2: Workout Context (Temporal Tracking)
CREATE TABLE IF NOT EXISTS workout_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    workout_time TIME NOT NULL DEFAULT CURRENT_TIME,
    day_of_week TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_context_user ON workout_context(user_id);
CREATE INDEX idx_context_day ON workout_context(day_of_week);
CREATE INDEX idx_context_time ON workout_context(workout_time);

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own context" ON workout_context 
    FOR SELECT TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own context" ON workout_context 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

-- Table 3: Equipment Proficiency Auto-Tracking
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

CREATE INDEX idx_proficiency_user ON equipment_proficiency(user_id);

ALTER TABLE equipment_proficiency ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own proficiency" ON equipment_proficiency 
    FOR ALL TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- Helper Function: Increment Equipment Usage
CREATE OR REPLACE FUNCTION increment_equipment_usage(
    p_user_id UUID,
    p_equipment_type TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO equipment_proficiency (user_id, equipment_type, times_used, last_used)
    VALUES (p_user_id, p_equipment_type, 1, CURRENT_DATE)
    ON CONFLICT (user_id, equipment_type)
    DO UPDATE SET
        times_used = equipment_proficiency.times_used + 1,
        last_used = CURRENT_DATE,
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ✅ DONE! Run this entire file in Supabase SQL Editor
-- ============================================================================
-- Next steps:
-- 1. Verify tables in Supabase Table Editor
-- 2. Add Swift code from QUICK_WINS_ALL_CODE.swift
-- 3. Complete a test workout
-- 4. Check tables to see data flowing in
-- ============================================================================

