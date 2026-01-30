-- ============================================================================
-- FIX: All RLS Policy Errors
-- ============================================================================
-- Multiple tables are causing RLS errors preventing workout data from syncing
-- This script fixes all the RLS policies to allow authenticated users to access their own data
-- ============================================================================

-- 1. Fix workout_context table
CREATE TABLE IF NOT EXISTS workout_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    day_of_week TEXT,
    time_of_day TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own context" ON workout_context;
DROP POLICY IF EXISTS "Users can insert own context" ON workout_context;

CREATE POLICY "Users can view own context" 
    ON workout_context 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own context" 
    ON workout_context 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

-- 2. Fix user_performance_trends table
CREATE TABLE IF NOT EXISTS user_performance_trends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    exercise_name TEXT NOT NULL,
    trend_direction TEXT,
    trend_percentage DOUBLE PRECISION,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_performance_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own trends" ON user_performance_trends;
DROP POLICY IF EXISTS "Users can insert own trends" ON user_performance_trends;
DROP POLICY IF EXISTS "Users can update own trends" ON user_performance_trends;

CREATE POLICY "Users can view own trends" 
    ON user_performance_trends 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own trends" 
    ON user_performance_trends 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own trends" 
    ON user_performance_trends 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- 3. Fix set_completion_patterns table
CREATE TABLE IF NOT EXISTS set_completion_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    exercise_name TEXT NOT NULL,
    typical_sets INT,
    typical_reps INT,
    typical_rest_time INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE set_completion_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "Users can insert own patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "Users can update own patterns" ON set_completion_patterns;

CREATE POLICY "Users can view own patterns" 
    ON set_completion_patterns 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own patterns" 
    ON set_completion_patterns 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own patterns" 
    ON set_completion_patterns 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- 4. Fix user_strength_ratios table
CREATE TABLE IF NOT EXISTS user_strength_ratios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ratio_type TEXT NOT NULL,
    ratio_value DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_strength_ratios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own ratios" ON user_strength_ratios;
DROP POLICY IF EXISTS "Users can insert own ratios" ON user_strength_ratios;
DROP POLICY IF EXISTS "Users can update own ratios" ON user_strength_ratios;

CREATE POLICY "Users can view own ratios" 
    ON user_strength_ratios 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own ratios" 
    ON user_strength_ratios 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own ratios" 
    ON user_strength_ratios 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- 5. Fix exercise_user_effectiveness table
CREATE TABLE IF NOT EXISTS exercise_user_effectiveness (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    exercise_name TEXT NOT NULL,
    effectiveness_score DOUBLE PRECISION,
    times_performed INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE exercise_user_effectiveness ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "Users can insert own effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "Users can update own effectiveness" ON exercise_user_effectiveness;

CREATE POLICY "Users can view own effectiveness" 
    ON exercise_user_effectiveness 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own effectiveness" 
    ON exercise_user_effectiveness 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own effectiveness" 
    ON exercise_user_effectiveness 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- 6. Fix workout_time_performance table
CREATE TABLE IF NOT EXISTS workout_time_performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    duration_minutes INT,
    time_of_day TEXT,
    performance_rating DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE workout_time_performance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own time performance" ON workout_time_performance;
DROP POLICY IF EXISTS "Users can insert own time performance" ON workout_time_performance;

CREATE POLICY "Users can view own time performance" 
    ON workout_time_performance 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own time performance" 
    ON workout_time_performance 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

-- 7. Fix weekly_volume_trends table
CREATE TABLE IF NOT EXISTS weekly_volume_trends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    week_start_date DATE NOT NULL,
    muscle_group TEXT,
    total_volume DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE weekly_volume_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own volume trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "Users can insert own volume trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "Users can update own volume trends" ON weekly_volume_trends;

CREATE POLICY "Users can view own volume trends" 
    ON weekly_volume_trends 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own volume trends" 
    ON weekly_volume_trends 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own volume trends" 
    ON weekly_volume_trends 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- 8. Fix collaborative_workout_data - Add missing program_id column
DO $$ 
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'collaborative_workout_data') THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'collaborative_workout_data' 
            AND column_name = 'program_id'
        ) THEN
            ALTER TABLE collaborative_workout_data 
            ADD COLUMN program_id UUID;
            RAISE NOTICE 'Added program_id column to collaborative_workout_data';
        END IF;
    END IF;
END $$;

-- Create indexes for better performance (only if columns exist)
DO $$ 
BEGIN
    -- Index for user_performance_trends
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_performance_trends' AND column_name = 'user_id') THEN
        CREATE INDEX IF NOT EXISTS idx_user_performance_trends_user 
            ON user_performance_trends(user_id, exercise_name);
        RAISE NOTICE 'Created index on user_performance_trends';
    END IF;
    
    -- Index for set_completion_patterns
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'set_completion_patterns' AND column_name = 'user_id') THEN
        CREATE INDEX IF NOT EXISTS idx_set_completion_patterns_user 
            ON set_completion_patterns(user_id, exercise_name);
        RAISE NOTICE 'Created index on set_completion_patterns';
    END IF;
    
    -- Index for user_strength_ratios
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_strength_ratios' AND column_name = 'user_id') THEN
        CREATE INDEX IF NOT EXISTS idx_user_strength_ratios_user 
            ON user_strength_ratios(user_id);
        RAISE NOTICE 'Created index on user_strength_ratios';
    END IF;
    
    -- Index for exercise_user_effectiveness
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'exercise_user_effectiveness' AND column_name = 'user_id') THEN
        CREATE INDEX IF NOT EXISTS idx_exercise_effectiveness_user 
            ON exercise_user_effectiveness(user_id, exercise_name);
        RAISE NOTICE 'Created index on exercise_user_effectiveness';
    END IF;
    
    -- Index for workout_time_performance (only if workout_id exists)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'workout_time_performance' AND column_name = 'workout_id') THEN
        CREATE INDEX IF NOT EXISTS idx_workout_time_perf_user 
            ON workout_time_performance(user_id, workout_id);
        RAISE NOTICE 'Created index on workout_time_performance';
    END IF;
    
    -- Index for weekly_volume_trends
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'weekly_volume_trends' AND column_name = 'week_start_date') THEN
        CREATE INDEX IF NOT EXISTS idx_weekly_volume_user 
            ON weekly_volume_trends(user_id, week_start_date DESC);
        RAISE NOTICE 'Created index on weekly_volume_trends';
    END IF;
END $$;

-- Success notification
DO $$
BEGIN
    RAISE NOTICE '✅ All RLS policies fixed!';
    RAISE NOTICE '📊 Your workouts should now sync correctly to the cloud.';
    RAISE NOTICE '🔄 Please try completing another workout to test.';
END $$;
