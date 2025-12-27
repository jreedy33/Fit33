-- ============================================================================
-- COLLABORATIVE LEARNING ENGINE - DATABASE SCHEMA
-- ============================================================================
-- These tables aggregate workout data across ALL users to enable:
-- 1. Finding similar users based on profile (goal, equipment, experience)
-- 2. Tracking which exercises work well together (pairings)
-- 3. Identifying successful programs and workouts
-- 4. Making smarter recommendations based on collective intelligence
-- ============================================================================

-- 1. User Similarity Profiles
-- Stores user attributes for similarity matching
CREATE TABLE IF NOT EXISTS user_similarity_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    goal TEXT NOT NULL,  -- "Build Muscle", "Lose Weight", etc.
    experience TEXT NOT NULL,  -- "Beginner", "Intermediate", "Advanced"
    equipment TEXT[] NOT NULL,  -- ["Barbell", "Dumbbells", "Cables"]
    age_range TEXT,  -- "18-25", "26-35", etc.
    gender TEXT,
    workout_location TEXT,  -- "Gym", "Home"
    total_workouts_completed INT DEFAULT 0,
    avg_workout_duration INT DEFAULT 0,  -- minutes
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_similarity_goal ON user_similarity_profiles(goal);
CREATE INDEX idx_user_similarity_experience ON user_similarity_profiles(experience);

-- 2. Collaborative Workout Data
-- Records every completed workout for pattern analysis
CREATE TABLE IF NOT EXISTS collaborative_workout_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    workout_type TEXT NOT NULL,  -- "auto-gen", "custom", "program"
    program_id TEXT,  -- If from a program
    exercises JSONB NOT NULL,  -- Array of {name, equipment, sets, reps, muscle_group}
    was_successful BOOLEAN DEFAULT true,  -- Did user complete the workout?
    user_goal TEXT,
    user_experience TEXT,
    user_equipment TEXT[],
    duration_minutes INT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_collab_workout_user ON collaborative_workout_data(user_id);
CREATE INDEX idx_collab_workout_goal ON collaborative_workout_data(user_goal);
CREATE INDEX idx_collab_workout_type ON collaborative_workout_data(workout_type);
CREATE INDEX idx_collab_workout_date ON collaborative_workout_data(completed_at);

-- 3. Exercise Pairings (Co-occurrence)
-- Tracks which exercises are frequently done together
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

CREATE INDEX idx_pairing_ex1 ON exercise_pairings(exercise_1);
CREATE INDEX idx_pairing_ex2 ON exercise_pairings(exercise_2);

-- 4. Exercise Pairing Stats (Aggregated View)
-- Pre-computed statistics for fast lookups
-- NOTE: Create this AFTER you have data in exercise_pairings table
-- Run manually: SELECT refresh_collaborative_stats();

CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_pairing_stats AS
SELECT 
    ep.exercise_1,
    ep.exercise_2,
    ep.muscle_group_1,
    ep.muscle_group_2,
    COUNT(*) as co_occurrence_count,
    COUNT(DISTINCT ep.recorded_at::date) as days_seen_together
FROM exercise_pairings ep
GROUP BY ep.exercise_1, ep.exercise_2, ep.muscle_group_1, ep.muscle_group_2
HAVING COUNT(*) >= 5  -- Minimum 5 occurrences
ORDER BY co_occurrence_count DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pairing_stats ON exercise_pairing_stats(exercise_1, exercise_2);

-- 5. Program Completion Records
-- Tracks which programs users complete and their success rate
CREATE TABLE IF NOT EXISTS collaborative_program_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    program_id TEXT NOT NULL,
    program_name TEXT NOT NULL,
    template_id TEXT NOT NULL,
    total_days INT NOT NULL,
    completed_days INT NOT NULL,
    completion_rate DECIMAL(3,2),  -- 0.00 to 1.00
    user_goal TEXT,
    user_experience TEXT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_program_completion_user ON collaborative_program_completions(user_id);
CREATE INDEX idx_program_completion_template ON collaborative_program_completions(template_id);
CREATE INDEX idx_program_completion_rate ON collaborative_program_completions(completion_rate);

-- 6. Program Success Stats (Aggregated View)
-- NOTE: Create this AFTER you have data in collaborative_program_completions
CREATE MATERIALIZED VIEW IF NOT EXISTS program_success_stats AS
SELECT 
    template_id,
    program_name,
    COUNT(*) as completion_count,
    AVG(completion_rate) as avg_completion_rate,
    array_agg(DISTINCT user_id::text) as user_ids
FROM collaborative_program_completions
GROUP BY template_id, program_name
HAVING COUNT(*) >= 3;  -- Minimum 3 completions

CREATE INDEX IF NOT EXISTS idx_program_success_rate ON program_success_stats(avg_completion_rate DESC);

-- 7. Exercise Global Stats (Aggregated View)
-- Overall exercise popularity and success rates
-- NOTE: Create this AFTER you have data in collaborative_workout_data
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_global_stats AS
WITH exercise_data AS (
    SELECT 
        jsonb_array_elements(exercises)->>'name' as exercise_name,
        was_successful
    FROM collaborative_workout_data
)
SELECT 
    LOWER(exercise_name) as exercise_name,
    COUNT(*) as completion_count,
    AVG(CASE WHEN was_successful THEN 1.0 ELSE 0.0 END) as success_rate
FROM exercise_data
WHERE exercise_name IS NOT NULL
GROUP BY LOWER(exercise_name)
HAVING COUNT(*) >= 5;

CREATE UNIQUE INDEX IF NOT EXISTS idx_exercise_global_stats ON exercise_global_stats(exercise_name);

-- 8. User Exercise Preferences (Individual + Similar Users)
-- What exercises does each user prefer, weighted by similar users
CREATE TABLE IF NOT EXISTS user_exercise_preferences (
    user_id UUID REFERENCES auth.users(id),
    exercise_name TEXT NOT NULL,
    personal_score DECIMAL(5,4) DEFAULT 0,  -- Based on user's own history
    collaborative_score DECIMAL(5,4) DEFAULT 0,  -- Based on similar users
    combined_score DECIMAL(5,4) GENERATED ALWAYS AS (
        personal_score * 0.6 + collaborative_score * 0.4
    ) STORED,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, exercise_name)
);

CREATE INDEX idx_user_exercise_pref_score ON user_exercise_preferences(combined_score DESC);

-- 9. Function to refresh all materialized views
CREATE OR REPLACE FUNCTION refresh_collaborative_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_pairing_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY program_success_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_global_stats;
END;
$$ LANGUAGE plpgsql;

-- 10. Row Level Security Policies
-- Users can only insert their own data, but can read aggregated stats

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE collaborative_program_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_similarity_profiles ENABLE ROW LEVEL SECURITY;

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
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE user_similarity_profiles IS 
'Stores user attributes for finding similar users (goal, equipment, experience, etc.)';

COMMENT ON TABLE collaborative_workout_data IS 
'Records every completed workout with exercises for pattern analysis across all users';

COMMENT ON TABLE exercise_pairings IS 
'Raw data: which exercises were done together in the same workout';

COMMENT ON MATERIALIZED VIEW exercise_pairing_stats IS 
'Aggregated: how often exercise pairs occur together (for recommendations)';

COMMENT ON MATERIALIZED VIEW exercise_global_stats IS 
'Aggregated: overall popularity and success rates for each exercise';

COMMENT ON MATERIALIZED VIEW program_success_stats IS 
'Aggregated: which programs have the highest completion rates';

-- ============================================================================
-- SCHEDULER: Refresh stats hourly (set up in Supabase Dashboard > Database > Scheduled Jobs)
-- SELECT cron.schedule('refresh-collaborative-stats', '0 * * * *', 'SELECT refresh_collaborative_stats()');
-- ============================================================================

