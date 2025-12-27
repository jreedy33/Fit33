-- ============================================================================
-- COLLABORATIVE LEARNING ENGINE - COMPLETE SETUP SCRIPT
-- ============================================================================
-- Copy and paste this entire script into Supabase SQL Editor and run it
-- ============================================================================

-- ============================================================================
-- STEP 1: CREATE BASE TABLES
-- ============================================================================

-- Table 1: User Similarity Profiles
CREATE TABLE IF NOT EXISTS user_similarity_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    goal TEXT NOT NULL,
    experience TEXT NOT NULL,
    equipment TEXT[] NOT NULL,
    age_range TEXT,
    gender TEXT,
    workout_location TEXT,
    total_workouts_completed INT DEFAULT 0,
    avg_workout_duration INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_similarity_goal ON user_similarity_profiles(goal);
CREATE INDEX IF NOT EXISTS idx_user_similarity_experience ON user_similarity_profiles(experience);

-- Table 2: Collaborative Workout Data
CREATE TABLE IF NOT EXISTS collaborative_workout_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    workout_type TEXT NOT NULL,
    program_id TEXT,
    exercises JSONB NOT NULL,
    was_successful BOOLEAN DEFAULT true,
    user_goal TEXT,
    user_experience TEXT,
    user_equipment TEXT[],
    duration_minutes INT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_collab_workout_user ON collaborative_workout_data(user_id);
CREATE INDEX IF NOT EXISTS idx_collab_workout_goal ON collaborative_workout_data(user_goal);
CREATE INDEX IF NOT EXISTS idx_collab_workout_type ON collaborative_workout_data(workout_type);
CREATE INDEX IF NOT EXISTS idx_collab_workout_date ON collaborative_workout_data(completed_at);

-- Table 3: Exercise Pairings
CREATE TABLE IF NOT EXISTS exercise_pairings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_1 TEXT NOT NULL,
    exercise_2 TEXT NOT NULL,
    muscle_group_1 TEXT,
    muscle_group_2 TEXT,
    equipment_1 TEXT,
    equipment_2 TEXT,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pairing_ex1 ON exercise_pairings(exercise_1);
CREATE INDEX IF NOT EXISTS idx_pairing_ex2 ON exercise_pairings(exercise_2);

-- Table 4: Program Completions
CREATE TABLE IF NOT EXISTS collaborative_program_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    program_id TEXT NOT NULL,
    program_name TEXT NOT NULL,
    template_id TEXT NOT NULL,
    total_days INT NOT NULL,
    completed_days INT NOT NULL,
    completion_rate DECIMAL(3,2),
    user_goal TEXT,
    user_experience TEXT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_program_completion_user ON collaborative_program_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_program_completion_template ON collaborative_program_completions(template_id);
CREATE INDEX IF NOT EXISTS idx_program_completion_rate ON collaborative_program_completions(completion_rate);

-- Table 5: User Exercise Preferences
CREATE TABLE IF NOT EXISTS user_exercise_preferences (
    user_id UUID REFERENCES auth.users(id),
    exercise_name TEXT NOT NULL,
    personal_score DECIMAL(5,4) DEFAULT 0,
    collaborative_score DECIMAL(5,4) DEFAULT 0,
    combined_score DECIMAL(5,4),
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, exercise_name)
);

CREATE INDEX IF NOT EXISTS idx_user_exercise_pref_score ON user_exercise_preferences(combined_score DESC);

-- ============================================================================
-- STEP 2: ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE collaborative_program_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_similarity_profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for re-run safety)
DROP POLICY IF EXISTS "Users can insert own workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "Users can insert own program completions" ON collaborative_program_completions;
DROP POLICY IF EXISTS "Users can manage own similarity profile" ON user_similarity_profiles;
DROP POLICY IF EXISTS "Authenticated users can read workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "Authenticated users can read program completions" ON collaborative_program_completions;
DROP POLICY IF EXISTS "Authenticated users can read similarity profiles" ON user_similarity_profiles;

-- Insert policies - users can only add their own data
CREATE POLICY "Users can insert own workout data" ON collaborative_workout_data
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can insert own program completions" ON collaborative_program_completions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can manage own similarity profile" ON user_similarity_profiles
    FOR ALL USING (auth.uid() = user_id);

-- Select policies - authenticated users can read aggregated data
CREATE POLICY "Authenticated users can read workout data" ON collaborative_workout_data
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can read program completions" ON collaborative_program_completions
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can read similarity profiles" ON user_similarity_profiles
    FOR SELECT USING (auth.role() = 'authenticated');

-- ============================================================================
-- STEP 3: CREATE AGGREGATION FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_collaborative_stats()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    -- Refresh exercise pairing stats
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'exercise_pairing_stats') THEN
            REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_pairing_stats;
            result := result || 'Exercise pairings refreshed. ';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW exercise_pairing_stats;
            result := result || 'Exercise pairings refreshed (non-concurrent). ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Exercise pairings failed. ';
        END;
    END;
    
    -- Refresh program success stats
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'program_success_stats') THEN
            REFRESH MATERIALIZED VIEW CONCURRENTLY program_success_stats;
            result := result || 'Program stats refreshed. ';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW program_success_stats;
            result := result || 'Program stats refreshed (non-concurrent). ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Program stats failed. ';
        END;
    END;
    
    -- Refresh exercise global stats
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'exercise_global_stats') THEN
            REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_global_stats;
            result := result || 'Global stats refreshed.';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW exercise_global_stats;
            result := result || 'Global stats refreshed (non-concurrent).';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Global stats failed.';
        END;
    END;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ✅ SETUP COMPLETE! 
-- ============================================================================
-- The tables are ready. Your app will now start recording workout data.
-- 
-- To verify tables were created, run this in a NEW query:
-- 
-- SELECT table_name 
-- FROM information_schema.tables 
-- WHERE table_schema = 'public' 
--   AND table_name IN ('user_similarity_profiles', 
--                      'collaborative_workout_data', 
--                      'exercise_pairings',
--                      'collaborative_program_completions',
--                      'user_exercise_preferences');
-- 
-- You should see 5 tables listed.
-- ============================================================================

