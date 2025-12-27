-- ============================================================================
-- FRESH START: Drop any existing tables and recreate them
-- ============================================================================

-- Drop existing tables (if any) to start fresh
DROP TABLE IF EXISTS user_exercise_preferences CASCADE;
DROP TABLE IF EXISTS collaborative_program_completions CASCADE;
DROP TABLE IF EXISTS exercise_pairings CASCADE;
DROP TABLE IF EXISTS collaborative_workout_data CASCADE;
DROP TABLE IF EXISTS user_similarity_profiles CASCADE;

-- Drop any existing materialized views that might conflict
DROP MATERIALIZED VIEW IF EXISTS exercise_pairing_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS exercise_global_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS program_success_stats CASCADE;

-- ============================================================================
-- TABLE 1: User Similarity Profiles
-- ============================================================================
CREATE TABLE user_similarity_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    goal TEXT,
    experience_level TEXT,
    equipment_available TEXT[],
    preferred_workout_duration INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_similarity_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "view_all" ON user_similarity_profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_own" ON user_similarity_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "update_own" ON user_similarity_profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id);

-- ============================================================================
-- TABLE 2: Collaborative Workout Data
-- ============================================================================
CREATE TABLE collaborative_workout_data (
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

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY "view_all" ON collaborative_workout_data FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_own" ON collaborative_workout_data FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 3: Exercise Pairings
-- ============================================================================
CREATE TABLE exercise_pairings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ex1 TEXT NOT NULL,
    ex2 TEXT NOT NULL,
    muscle1 TEXT,
    muscle2 TEXT,
    equip1 TEXT,
    equip2 TEXT,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE exercise_pairings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "view_all" ON exercise_pairings FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_all" ON exercise_pairings FOR INSERT TO authenticated WITH CHECK (true);

-- ============================================================================
-- TABLE 4: Program Completions
-- ============================================================================
CREATE TABLE collaborative_program_completions (
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

ALTER TABLE collaborative_program_completions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "view_all" ON collaborative_program_completions FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_own" ON collaborative_program_completions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 5: User Exercise Preferences
-- ============================================================================
CREATE TABLE user_exercise_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    exercise_name TEXT NOT NULL,
    preference_score REAL DEFAULT 0,
    times_completed INTEGER DEFAULT 0,
    last_completed TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE user_exercise_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "view_all" ON user_exercise_preferences FOR SELECT TO authenticated USING (true);
CREATE POLICY "insert_own" ON user_exercise_preferences FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "update_own" ON user_exercise_preferences FOR UPDATE TO authenticated USING (auth.uid() = user_id);

