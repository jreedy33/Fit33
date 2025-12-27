-- ============================================================================
-- GOAL CLASSIFICATION UPDATE SCRIPT (SLIM VERSION)
-- Adds 4 key columns for goal-based exercise recommendations
-- ============================================================================

-- ============================================================================
-- STEP 1: ADD NEW COLUMNS TO EXERCISES TABLE
-- ============================================================================

-- Fat Loss Rating (1-10): How good for "Get Lean" goal
-- Different from endurance - measures metabolic demand (burpees, thrusters, etc.)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS fat_loss_rating INTEGER DEFAULT 5;

-- General Fitness Rating (1-10): How good for balanced/variety workouts
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS general_fitness_rating INTEGER DEFAULT 5;

-- Is Compound: True for multi-joint movements (squats, presses, rows)
-- Explicit flag is cleaner than deriving from exercise name
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_compound BOOLEAN DEFAULT FALSE;

-- Supersetable: True if exercise can be done back-to-back without major fatigue
-- Useful for "Get Lean" goal where we want circuits/supersets
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS supersetable BOOLEAN DEFAULT TRUE;

-- ============================================================================
-- STEP 2: CREATE INDEXES FOR GOAL-BASED QUERIES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_exercises_fat_loss ON exercises(fat_loss_rating);
CREATE INDEX IF NOT EXISTS idx_exercises_general_fitness ON exercises(general_fitness_rating);
CREATE INDEX IF NOT EXISTS idx_exercises_compound ON exercises(is_compound);
CREATE INDEX IF NOT EXISTS idx_exercises_supersetable ON exercises(supersetable);

-- ============================================================================
-- STEP 3: VERIFY COLUMNS EXIST
-- ============================================================================

SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'exercises' 
AND column_name IN ('fat_loss_rating', 'general_fitness_rating', 'is_compound', 'supersetable')
ORDER BY column_name;
