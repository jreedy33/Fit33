-- ============================================================================
-- FIX: exercise_performance_history Missing Columns
-- ============================================================================
-- Issue: App is trying to save workouts but the table is missing critical columns
-- Error: "Could not find the 'best_set_reps' column of 'exercise_performance_history'"
-- 
-- This migration adds the missing columns that the app expects
-- ============================================================================

-- Add missing columns to exercise_performance_history
-- These columns may already exist, so we use IF NOT EXISTS or ALTER TABLE with error handling

-- Check if table exists, if not create it
CREATE TABLE IF NOT EXISTS exercise_performance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    exercise_name TEXT NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add missing columns (will skip if they already exist)
DO $$ 
BEGIN
    -- best_set_weight
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'best_set_weight'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN best_set_weight DOUBLE PRECISION;
        RAISE NOTICE 'Added best_set_weight column';
    END IF;
    
    -- best_set_reps (CRITICAL - this is the missing one!)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'best_set_reps'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN best_set_reps INT;
        RAISE NOTICE 'Added best_set_reps column';
    END IF;
    
    -- total_sets
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'total_sets'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN total_sets INT;
        RAISE NOTICE 'Added total_sets column';
    END IF;
    
    -- total_reps
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'total_reps'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN total_reps INT;
        RAISE NOTICE 'Added total_reps column';
    END IF;
    
    -- total_volume
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'total_volume'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN total_volume DOUBLE PRECISION;
        RAISE NOTICE 'Added total_volume column';
    END IF;
    
    -- one_rep_max_estimate
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'one_rep_max_estimate'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN one_rep_max_estimate DOUBLE PRECISION;
        RAISE NOTICE 'Added one_rep_max_estimate column';
    END IF;
    
    -- equipment_used
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'equipment_used'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN equipment_used TEXT;
        RAISE NOTICE 'Added equipment_used column';
    END IF;
    
    -- exercise_id (Core Data reference)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'exercise_id'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN exercise_id TEXT;
        RAISE NOTICE 'Added exercise_id column';
    END IF;
    
    -- average_rpe
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'average_rpe'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN average_rpe DOUBLE PRECISION;
        RAISE NOTICE 'Added average_rpe column';
    END IF;
    
    -- form_quality
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'form_quality'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN form_quality TEXT CHECK (form_quality IN ('Poor', 'Fair', 'Good', 'Excellent'));
        RAISE NOTICE 'Added form_quality column';
    END IF;
    
    -- difficulty_feedback
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'difficulty_feedback'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN difficulty_feedback TEXT CHECK (difficulty_feedback IN ('Too Light', 'Light', 'Just Right', 'Heavy', 'Too Heavy'));
        RAISE NOTICE 'Added difficulty_feedback column';
    END IF;
    
    -- notes
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'exercise_performance_history' 
        AND column_name = 'notes'
    ) THEN
        ALTER TABLE exercise_performance_history 
        ADD COLUMN notes TEXT;
        RAISE NOTICE 'Added notes column';
    END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_perf_history_user_exercise 
    ON exercise_performance_history(user_id, exercise_name);

CREATE INDEX IF NOT EXISTS idx_perf_history_user_date 
    ON exercise_performance_history(user_id, workout_date DESC);

CREATE INDEX IF NOT EXISTS idx_perf_history_workout 
    ON exercise_performance_history(workout_id);

-- Enable RLS (if not already enabled)
ALTER TABLE exercise_performance_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid duplicates)
DROP POLICY IF EXISTS "Users can view own performance" ON exercise_performance_history;
DROP POLICY IF EXISTS "Users can insert own performance" ON exercise_performance_history;
DROP POLICY IF EXISTS "Users can update own performance" ON exercise_performance_history;

-- Create RLS policies
CREATE POLICY "Users can view own performance" 
    ON exercise_performance_history 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can insert own performance" 
    ON exercise_performance_history 
    FOR INSERT 
    TO authenticated 
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own performance" 
    ON exercise_performance_history 
    FOR UPDATE 
    TO authenticated 
    USING (auth.uid()::text = user_id::text);

-- Verify the schema
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'exercise_performance_history'
ORDER BY ordinal_position;

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ exercise_performance_history schema fixed!';
    RAISE NOTICE '📊 Your workout history should now sync properly.';
END $$;
