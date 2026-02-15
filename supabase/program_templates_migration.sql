-- ============================================================================
-- PROGRAM TEMPLATES & ENHANCED PROGRAM SYSTEM MIGRATION
-- ============================================================================
-- Creates tables for:
--   1. program_templates - Master program templates (14/30/90 day GAIN/LEAN)
--   2. user_active_programs - Tracks user's active program with lazy day generation
--   3. program_day_history - Records completed days for cooldown/variety tracking
--   4. exercise_bundles - Bundle definitions (similar exercises grouped together)
-- ============================================================================

-- ============================================================================
-- 1. PROGRAM TEMPLATES TABLE
-- Stores the 6 master templates that can be adjusted per user
-- ============================================================================

CREATE TABLE IF NOT EXISTS program_templates (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    goal TEXT NOT NULL CHECK (goal IN ('gain', 'lean')),
    duration_days INT NOT NULL CHECK (duration_days IN (14, 30, 90)),
    days_per_week INT NOT NULL CHECK (days_per_week BETWEEN 2 AND 7),
    difficulty TEXT NOT NULL DEFAULT 'Intermediate',
    icon TEXT DEFAULT 'figure.strengthtraining.traditional',
    color TEXT DEFAULT 'blue',
    blocks_json JSONB NOT NULL DEFAULT '[]'::JSONB,          -- PeriodizationBlock array
    weekly_schedule_json JSONB NOT NULL DEFAULT '[]'::JSONB,  -- DaySplitTemplate array
    exercise_swap_pct NUMERIC(3,2) DEFAULT 0.50,
    weekly_pattern_coverage TEXT[] DEFAULT '{}',
    benefits TEXT[] DEFAULT '{}',
    warmup_suggestion TEXT,
    tags TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. USER ACTIVE PROGRAMS TABLE
-- Tracks a user's enrollment in a program with lazy day generation
-- Only the next day is generated after the current day is completed
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_active_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    template_id TEXT NOT NULL REFERENCES program_templates(id),
    program_name TEXT NOT NULL,
    goal TEXT NOT NULL,
    duration_days INT NOT NULL,
    
    -- Progress tracking
    current_day INT NOT NULL DEFAULT 1,
    total_workout_days INT NOT NULL,    -- Excludes rest days
    completed_days INT NOT NULL DEFAULT 0,
    current_week INT NOT NULL DEFAULT 1,
    current_block INT NOT NULL DEFAULT 1,
    
    -- State
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    last_workout_at TIMESTAMPTZ,
    
    -- Generated day data (JSONB for the current/next day only - lazy generation)
    current_day_json JSONB,             -- The current day's workout
    anchor_exercises_json JSONB DEFAULT '{}'::JSONB,  -- Anchor lifts tracked across weeks
    
    -- User customizations
    user_equipment TEXT[] DEFAULT '{}',
    user_experience TEXT DEFAULT 'Intermediate',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Only one active program per user
    CONSTRAINT unique_active_program UNIQUE (user_id, is_active) 
        -- Note: This enforces at DB level but we handle it in app logic too
);

-- Partial unique index: only one active program per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_program_per_user 
    ON user_active_programs (user_id) 
    WHERE is_active = TRUE AND is_completed = FALSE;

-- ============================================================================
-- 3. PROGRAM DAY HISTORY TABLE
-- Records each completed workout day for:
--   - Exercise cooldown tracking (don't repeat exercises within cooldown window)
--   - Progression tracking (load increases over time)
--   - Weekly coverage validation
-- ============================================================================

CREATE TABLE IF NOT EXISTS program_day_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    program_id UUID NOT NULL REFERENCES user_active_programs(id) ON DELETE CASCADE,
    
    day_number INT NOT NULL,
    week_number INT NOT NULL,
    block_number INT NOT NULL DEFAULT 1,
    day_name TEXT NOT NULL,
    
    -- Exercise data
    exercises_json JSONB NOT NULL DEFAULT '[]'::JSONB,  -- Full exercise list with sets/reps/weight
    exercise_names TEXT[] NOT NULL DEFAULT '{}',          -- For quick cooldown lookups
    exercise_bundles TEXT[] DEFAULT '{}',                  -- Bundle IDs used this day
    
    -- Performance
    total_volume NUMERIC DEFAULT 0,        -- Total weight × reps
    total_sets INT DEFAULT 0,
    duration_minutes INT DEFAULT 0,
    
    -- Timestamps
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for cooldown lookups: "what exercises did user X do in the last N days?"
CREATE INDEX IF NOT EXISTS idx_program_day_history_user_recent 
    ON program_day_history (user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_program_day_history_program 
    ON program_day_history (program_id, day_number);

-- ============================================================================
-- 4. EXERCISE BUNDLES TABLE
-- Stores bundle definitions so they can be updated without app releases
-- ============================================================================

CREATE TABLE IF NOT EXISTS exercise_bundles (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    families TEXT[] NOT NULL DEFAULT '{}',   -- Exercise family IDs in this bundle
    movement_pattern TEXT NOT NULL,
    max_per_workout INT NOT NULL DEFAULT 2,
    max_per_week INT NOT NULL DEFAULT 4,
    cooldown_days INT NOT NULL DEFAULT 3,
    superset_partner_id TEXT,               -- Bundle ID of superset partner
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 5. SEED PROGRAM TEMPLATES
-- ============================================================================

INSERT INTO program_templates (id, name, description, goal, duration_days, days_per_week, difficulty, icon, color, tags, warmup_suggestion)
VALUES
    ('14_day_gain', '14-Day Gain', '2-week strength + hypertrophy kickstart. Upper/Lower split with heavy anchors and quality volume.', 'gain', 14, 4, 'Intermediate', 'figure.strengthtraining.traditional', 'blue', ARRAY['gain', '14-day', 'upper-lower', 'strength'], '5 min light cardio + 2 warm-up sets at 50% and 75%'),
    ('14_day_lean', '14-Day Lean', '2-week high-density fat-burning program with supersets and conditioning finishers.', 'lean', 14, 5, 'Intermediate', 'flame.fill', 'orange', ARRAY['lean', '14-day', 'fat-loss', 'supersets'], '3-5 min light cardio + dynamic stretching'),
    ('30_day_gain', '30-Day Gain', 'Classic 4-week bodybuilding split with progressive overload and Week 4 deload.', 'gain', 30, 5, 'Intermediate', 'figure.strengthtraining.traditional', 'purple', ARRAY['gain', '30-day', 'bodybuilding', 'split'], '5 min cardio + 2 warm-up sets at 50% and 75%'),
    ('30_day_lean', '30-Day Lean', '4-week upper/lower split with non-conflicting supersets for maximum work density.', 'lean', 30, 4, 'Intermediate', 'flame.fill', 'pink', ARRAY['lean', '30-day', 'upper-lower', 'supersets'], '3-5 min jump rope or cycling + dynamic stretching'),
    ('90_day_gain', '90-Day Gain (Strength & Size)', 'Premium 3-block periodized program: hypertrophy → strength → intensity techniques.', 'gain', 90, 5, 'Intermediate', 'bolt.fill', 'red', ARRAY['gain', '90-day', 'periodized', 'premium'], '5 min light cardio + 2-3 warm-up sets ramping to working weight'),
    ('90_day_lean', '90-Day Lean (Recomp)', 'Premium 3-block recomposition: strength anchors → volume density → peak leanness.', 'lean', 90, 5, 'Intermediate', 'flame.fill', 'red', ARRAY['lean', '90-day', 'periodized', 'premium'], '5 min light cardio + movement prep')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    updated_at = NOW();

-- ============================================================================
-- 6. SEED EXERCISE BUNDLES
-- ============================================================================

INSERT INTO exercise_bundles (id, display_name, families, movement_pattern, max_per_workout, max_per_week, cooldown_days, superset_partner_id)
VALUES
    ('horizontal_press', 'Horizontal Press (Chest)', ARRAY['bench_press', 'chest_press', 'smith_chest_press', 'pushup', 'dip'], 'horizontal_press', 2, 4, 3, 'horizontal_pull'),
    ('chest_isolation', 'Chest Fly / Isolation', ARRAY['chest_fly', 'cable_crossover', 'pec_deck'], 'chest_fly', 1, 3, 3, 'horizontal_pull'),
    ('vertical_press', 'Vertical Press (Shoulders)', ARRAY['shoulder_press'], 'vertical_press', 1, 3, 3, 'vertical_pull'),
    ('lateral_raise_bundle', 'Lateral Raise', ARRAY['lateral_raise', 'front_raise'], 'lateral_raise', 1, 3, 3, 'rear_delt_bundle'),
    ('rear_delt_bundle', 'Rear Delt', ARRAY['rear_delt', 'face_pull'], 'rear_delt', 1, 3, 3, 'lateral_raise_bundle'),
    ('horizontal_pull', 'Row (Horizontal Pull)', ARRAY['row'], 'horizontal_pull', 2, 4, 3, 'horizontal_press'),
    ('vertical_pull', 'Pulldown / Pull-up', ARRAY['pulldown', 'pullup', 'chinup'], 'vertical_pull', 1, 3, 3, 'vertical_press'),
    ('shrug_bundle', 'Shrug', ARRAY['shrug'], 'shrug', 1, 2, 5, NULL),
    ('squat_pattern', 'Squat / Leg Press', ARRAY['squat', 'leg_press'], 'squat', 2, 4, 3, 'hinge_pattern'),
    ('hinge_pattern', 'Deadlift / RDL', ARRAY['deadlift', 'good_morning', 'back_extension'], 'hinge', 1, 3, 4, 'squat_pattern'),
    ('lunge_pattern', 'Lunge / Split Squat', ARRAY['lunge', 'step_up'], 'lunge', 1, 3, 3, NULL),
    ('hip_thrust_bundle', 'Hip Thrust / Glute Bridge', ARRAY['hip_thrust'], 'hip_thrust', 1, 3, 3, NULL),
    ('quad_isolation', 'Leg Extension', ARRAY['leg_extension'], 'leg_extension', 1, 2, 3, 'ham_isolation'),
    ('ham_isolation', 'Leg Curl', ARRAY['leg_curl'], 'leg_curl', 1, 2, 3, 'quad_isolation'),
    ('calf_bundle', 'Calf Raise', ARRAY['calf_raise'], 'calf_raise', 1, 3, 2, NULL),
    ('bicep_curl_bundle', 'Bicep Curl', ARRAY['bicep_curl', 'hammer_curl', 'preacher_curl', 'concentration_curl'], 'bicep_curl', 2, 4, 2, 'tricep_extension_bundle'),
    ('tricep_extension_bundle', 'Tricep Extension / Pushdown', ARRAY['tricep_pushdown', 'tricep_extension', 'skull_crusher', 'kickback'], 'tricep_extension', 2, 4, 2, 'bicep_curl_bundle'),
    ('core_flexion_bundle', 'Core Flexion', ARRAY['crunch', 'leg_raise'], 'core_flexion', 1, 4, 1, NULL),
    ('core_stability_bundle', 'Core Stability', ARRAY['plank', 'dead_bug', 'hollow_hold', 'ab_wheel'], 'core_stability', 1, 4, 1, NULL),
    ('core_rotation_bundle', 'Core Rotation', ARRAY['woodchop', 'russian_twist', 'anti_rotation'], 'core_rotation', 1, 3, 2, NULL)
ON CONFLICT (id) DO UPDATE SET
    families = EXCLUDED.families,
    max_per_workout = EXCLUDED.max_per_workout,
    cooldown_days = EXCLUDED.cooldown_days,
    updated_at = NOW();

-- ============================================================================
-- 7. RLS POLICIES
-- ============================================================================

-- Program templates are readable by all authenticated users
ALTER TABLE program_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Program templates are viewable by authenticated users"
    ON program_templates FOR SELECT
    TO authenticated
    USING (true);

-- User programs are only accessible by the owning user
ALTER TABLE user_active_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own programs"
    ON user_active_programs FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own programs"
    ON user_active_programs FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own programs"
    ON user_active_programs FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id);

-- Day history is only accessible by the owning user
ALTER TABLE program_day_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own day history"
    ON program_day_history FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own day history"
    ON program_day_history FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Exercise bundles are readable by all
ALTER TABLE exercise_bundles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exercise bundles are viewable by authenticated users"
    ON exercise_bundles FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ PROGRAM TEMPLATES MIGRATION COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Tables created:';
    RAISE NOTICE '  • program_templates (6 templates seeded)';
    RAISE NOTICE '  • user_active_programs (with lazy day generation)';
    RAISE NOTICE '  • program_day_history (cooldown + progression tracking)';
    RAISE NOTICE '  • exercise_bundles (20 bundles seeded)';
    RAISE NOTICE '';
    RAISE NOTICE 'RLS policies applied to all tables.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
