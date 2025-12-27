-- ============================================================================
-- EXERCISE FAMILY & INTELLIGENT SWAP SYSTEM
-- Run this in Supabase SQL Editor BEFORE importing classification data
-- ============================================================================

-- ============================================================================
-- STEP 1: ADD NEW COLUMNS TO EXERCISES TABLE
-- ============================================================================

-- Core family identification (for swap 1-2: same movement, different equipment)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS exercise_family TEXT;
COMMENT ON COLUMN exercises.exercise_family IS 'Movement family key like bicep_curl, bench_press, squat. All equipment variants share the same family.';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS base_exercise_name TEXT;
COMMENT ON COLUMN exercises.base_exercise_name IS 'Canonical name without equipment: Barbell Bench Press → Bench Press';

-- Complementary exercises (for swap 3+: different movement entirely)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS complementary_families TEXT;
COMMENT ON COLUMN exercises.complementary_families IS 'Comma-separated list of exercise families that pair well. Used for swap 3+ and workout suggestions.';

-- Equipment classification
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_equipment_primary BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN exercises.is_equipment_primary IS 'TRUE if this is the gold standard variant of the family. Only one per family.';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS equipment_category TEXT;
COMMENT ON COLUMN exercises.equipment_category IS 'Normalized: barbell, dumbbell, cable, machine, bodyweight, band, kettlebell, smith_machine';

-- Training parameters
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS duration_based BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN exercises.duration_based IS 'TRUE for stretches/cardio that track duration instead of reps';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS recommended_sets INT DEFAULT 3;
COMMENT ON COLUMN exercises.recommended_sets IS 'Default sets: 4 for heavy compounds, 3 for isolation, 1 for stretches/cardio';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS rest_seconds INT DEFAULT 60;
COMMENT ON COLUMN exercises.rest_seconds IS 'Rest between sets: 120 for deadlift/squat, 90 for compounds, 60 for isolation, 30 for stretches';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS muscles_worked_count INT DEFAULT 2;
COMMENT ON COLUMN exercises.muscles_worked_count IS 'Number of muscle groups engaged (1-6). Higher = more calories burned, more functional.';

-- Context-aware priority scores for intelligent sorting
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_build_muscle INT DEFAULT 70;
COMMENT ON COLUMN exercises.priority_build_muscle IS 'Sort priority (20-95) for Build Muscle goal. Barbell=95, Dumbbell=92, Cable=85, Machine=80';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_get_lean INT DEFAULT 70;
COMMENT ON COLUMN exercises.priority_get_lean IS 'Sort priority (50-90) for Get Lean goal. Dumbbell=90, Bodyweight=88, Cable=85, Barbell=78';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_home INT DEFAULT 50;
COMMENT ON COLUMN exercises.priority_home IS 'Sort priority (20-95) for Home training. Bodyweight=95, Dumbbell=92, Band=90, Barbell=65, Cable=30';

ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_gym INT DEFAULT 70;
COMMENT ON COLUMN exercises.priority_gym IS 'Sort priority (50-95) for Gym training. Barbell=95, Cable=92, Machine=88, Bodyweight=65';

-- ============================================================================
-- STEP 2: CREATE INDEXES FOR FAST QUERIES
-- ============================================================================

-- Family-based queries (for swap suggestions)
CREATE INDEX IF NOT EXISTS idx_exercises_family ON exercises(exercise_family);
CREATE INDEX IF NOT EXISTS idx_exercises_equipment_category ON exercises(equipment_category);
CREATE INDEX IF NOT EXISTS idx_exercises_primary ON exercises(exercise_family, is_equipment_primary) WHERE is_equipment_primary = TRUE;

-- Priority-based sorting
CREATE INDEX IF NOT EXISTS idx_exercises_priority_muscle ON exercises(priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_lean ON exercises(priority_get_lean DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_home ON exercises(priority_home DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_gym ON exercises(priority_gym DESC);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_exercises_family_muscle_priority ON exercises(exercise_family, priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_family_home_priority ON exercises(exercise_family, priority_home DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_family_gym_priority ON exercises(exercise_family, priority_gym DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_family_lean_priority ON exercises(exercise_family, priority_get_lean DESC);

-- ============================================================================
-- STEP 3: CREATE HELPER FUNCTIONS
-- ============================================================================

-- Function: Get equipment variants for an exercise (Swap 1-2)
CREATE OR REPLACE FUNCTION get_equipment_variants(
    p_exercise_id UUID,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    equipment_category TEXT,
    priority_score INT
) AS $$
DECLARE
    v_family TEXT;
    v_priority_column TEXT;
BEGIN
    -- Get the family of the source exercise
    SELECT exercise_family INTO v_family FROM exercises WHERE exercises.id = p_exercise_id;
    
    -- Determine which priority column to use
    v_priority_column := CASE 
        WHEN p_location = 'home' THEN 'priority_home'
        WHEN p_user_goal = 'Get Lean' THEN 'priority_get_lean'
        WHEN p_user_goal = 'Build Muscle' THEN 'priority_build_muscle'
        ELSE 'priority_gym'
    END;
    
    RETURN QUERY EXECUTE format('
        SELECT e.id, e.name, e.equipment, e.equipment_category,
               e.%I as priority_score
        FROM exercises e
        WHERE e.exercise_family = $1
          AND e.id != $2
        ORDER BY e.%I DESC
        LIMIT $3
    ', v_priority_column, v_priority_column)
    USING v_family, p_exercise_id, p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get complementary exercises (Swap 3+)
CREATE OR REPLACE FUNCTION get_complementary_exercises(
    p_exercise_id UUID,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 15
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    exercise_family TEXT,
    priority_score INT
) AS $$
DECLARE
    v_complementary TEXT;
    v_priority_column TEXT;
BEGIN
    -- Get complementary families for the source exercise
    SELECT complementary_families INTO v_complementary FROM exercises WHERE exercises.id = p_exercise_id;
    
    -- Determine which priority column to use
    v_priority_column := CASE 
        WHEN p_location = 'home' THEN 'priority_home'
        WHEN p_user_goal = 'Get Lean' THEN 'priority_get_lean'
        WHEN p_user_goal = 'Build Muscle' THEN 'priority_build_muscle'
        ELSE 'priority_gym'
    END;
    
    RETURN QUERY EXECUTE format('
        SELECT e.id, e.name, e.equipment, e.exercise_family,
               e.%I as priority_score
        FROM exercises e
        WHERE e.exercise_family = ANY(string_to_array($1, '',''))
          AND e.id != $2
        ORDER BY e.%I DESC
        LIMIT $3
    ', v_priority_column, v_priority_column)
    USING v_complementary, p_exercise_id, p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Smart swap (combines both)
CREATE OR REPLACE FUNCTION get_smart_swap_suggestions(
    p_exercise_id UUID,
    p_swap_count INT,
    p_user_goal TEXT DEFAULT 'Build Muscle',
    p_location TEXT DEFAULT 'gym',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    equipment TEXT,
    exercise_family TEXT,
    swap_type TEXT,
    priority_score INT
) AS $$
BEGIN
    IF p_swap_count < 3 THEN
        -- Swap 1-2: Same movement, different equipment
        RETURN QUERY
        SELECT ev.id, ev.name, ev.equipment, 
               (SELECT e.exercise_family FROM exercises e WHERE e.id = ev.id) as exercise_family,
               'equipment_variant'::TEXT as swap_type,
               ev.priority_score
        FROM get_equipment_variants(p_exercise_id, p_user_goal, p_location, p_limit) ev;
    ELSE
        -- Swap 3+: Different movement entirely
        RETURN QUERY
        SELECT ce.id, ce.name, ce.equipment, ce.exercise_family,
               'different_movement'::TEXT as swap_type,
               ce.priority_score
        FROM get_complementary_exercises(p_exercise_id, p_user_goal, p_location, p_limit) ce;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STEP 4: VERIFY INSTALLATION
-- ============================================================================

DO $$
DECLARE
    col_count INT;
BEGIN
    SELECT COUNT(*) INTO col_count
    FROM information_schema.columns
    WHERE table_name = 'exercises'
    AND column_name IN (
        'exercise_family', 'base_exercise_name', 'complementary_families',
        'is_equipment_primary', 'equipment_category', 'duration_based',
        'recommended_sets', 'rest_seconds', 'muscles_worked_count',
        'priority_build_muscle', 'priority_get_lean', 'priority_home', 'priority_gym'
    );
    
    IF col_count = 13 THEN
        RAISE NOTICE '✅ All 13 new columns added successfully!';
        RAISE NOTICE '✅ Indexes created';
        RAISE NOTICE '✅ Helper functions created';
        RAISE NOTICE '';
        RAISE NOTICE 'NEXT STEP: Import your classification data using UPDATE statements';
    ELSE
        RAISE NOTICE '⚠️ Only % of 13 columns found. Check for errors above.', col_count;
    END IF;
END $$;

-- ============================================================================
-- DONE! Run your UPDATE statements after this completes.
-- ============================================================================
