-- ============================================================================
-- COLLABORATIVE LEARNING - TABLES SETUP
-- ============================================================================
-- This creates the 5 core tables needed for collaborative learning.
-- Run this FIRST, then use your app to generate workout data.
-- After you have data, you'll create the materialized views separately.
-- ============================================================================

-- Table 1: User Similarity Profiles
CREATE TABLE IF NOT EXISTS user_similarity_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    goal TEXT,
    experience_level TEXT,
    equipment_available TEXT[],
    preferred_workout_duration INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_similarity_user ON user_similarity_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_similarity_goal ON user_similarity_profiles(goal);

ALTER TABLE user_similarity_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all similarity profiles" ON user_similarity_profiles;
CREATE POLICY "Users can view all similarity profiles" ON user_similarity_profiles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert own similarity profile" ON user_similarity_profiles;
CREATE POLICY "Users can insert own similarity profile" ON user_similarity_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own similarity profile" ON user_similarity_profiles;
CREATE POLICY "Users can update own similarity profile" ON user_similarity_profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- Table 2: Collaborative Workout Data
CREATE TABLE IF NOT EXISTS collaborative_workout_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_type TEXT,
    exercises_completed TEXT[],
    total_volume REAL,
    duration_minutes INTEGER,
    user_goal TEXT,
    user_experience TEXT,
    equipment_used TEXT[],
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_collab_workout_user ON collaborative_workout_data(user_id);
CREATE INDEX IF NOT EXISTS idx_collab_workout_type ON collaborative_workout_data(workout_type);
CREATE INDEX IF NOT EXISTS idx_collab_workout_date ON collaborative_workout_data(completed_at);

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all workout data" ON collaborative_workout_data;
CREATE POLICY "Users can view all workout data" ON collaborative_workout_data FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert own workout data" ON collaborative_workout_data;
CREATE POLICY "Users can insert own workout data" ON collaborative_workout_data FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

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

ALTER TABLE exercise_pairings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all pairings" ON exercise_pairings;
CREATE POLICY "Users can view all pairings" ON exercise_pairings FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert pairings" ON exercise_pairings;
CREATE POLICY "Users can insert pairings" ON exercise_pairings FOR INSERT TO authenticated WITH CHECK (true);

-- Table 4: Program Completions
CREATE TABLE IF NOT EXISTS collaborative_program_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    program_name TEXT,
    program_type TEXT,
    total_days INTEGER,
    completed_days INTEGER,
    completion_rate REAL,
    user_goal TEXT,
    user_experience TEXT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_program_completion_user ON collaborative_program_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_program_completion_type ON collaborative_program_completions(program_type);

ALTER TABLE collaborative_program_completions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all program completions" ON collaborative_program_completions;
CREATE POLICY "Users can view all program completions" ON collaborative_program_completions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert own program completions" ON collaborative_program_completions;
CREATE POLICY "Users can insert own program completions" ON collaborative_program_completions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Table 5: User Exercise Preferences
CREATE TABLE IF NOT EXISTS user_exercise_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    exercise_name TEXT NOT NULL,
    preference_score REAL DEFAULT 0,
    times_completed INTEGER DEFAULT 0,
    last_completed TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pref_user ON user_exercise_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_pref_exercise ON user_exercise_preferences(exercise_name);

ALTER TABLE user_exercise_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view all preferences" ON user_exercise_preferences;
CREATE POLICY "Users can view all preferences" ON user_exercise_preferences FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Users can insert own preferences" ON user_exercise_preferences;
CREATE POLICY "Users can insert own preferences" ON user_exercise_preferences FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own preferences" ON user_exercise_preferences;
CREATE POLICY "Users can update own preferences" ON user_exercise_preferences FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- ============================================================================
-- ✅ DONE! All 5 tables created successfully.
-- ============================================================================
-- Next steps:
-- 1. Use your app to complete 10-20 workouts
-- 2. Come back here and I'll give you the materialized views SQL
-- ============================================================================

