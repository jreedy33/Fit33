-- ============================================================================
-- DATABASE MIGRATIONS - Pre-Beta Enhancement
-- ============================================================================
-- This file contains all new tables needed to improve recommendation quality
-- and add critical safety features before beta launch.
--
-- PRIORITY 1: Safety & Legal (Run FIRST)
-- PRIORITY 2: User Experience (Run SECOND)
-- PRIORITY 3: Recommendation Quality (Run THIRD)
-- ============================================================================

-- ============================================================================
-- PRIORITY 1: SAFETY & LEGAL (MUST HAVE FOR BETA)
-- ============================================================================

-- Table: user_limitations
-- Purpose: Track injuries, pain, and medical limitations to prevent unsafe exercise recommendations
-- Impact: CRITICAL for user safety and legal liability
CREATE TABLE IF NOT EXISTS user_limitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    limitation_type TEXT NOT NULL CHECK (limitation_type IN ('injury', 'pain', 'mobility', 'medical', 'other')),
    affected_area TEXT NOT NULL, -- 'Lower Back', 'Right Knee', 'Left Shoulder', etc.
    severity TEXT NOT NULL CHECK (severity IN ('Mild', 'Moderate', 'Severe')),
    exercises_to_avoid TEXT[], -- Specific exercise names to exclude
    movement_patterns_to_avoid TEXT[], -- 'Heavy Squatting', 'Overhead Pressing', 'Deadlifting'
    recommended_alternatives TEXT[], -- Suggested safe alternatives
    notes TEXT,
    started_date DATE NOT NULL DEFAULT CURRENT_DATE,
    resolved_date DATE, -- NULL if still active
    is_active BOOLEAN GENERATED ALWAYS AS (resolved_date IS NULL) STORED,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_limitations_user ON user_limitations(user_id);
CREATE INDEX IF NOT EXISTS idx_limitations_active ON user_limitations(user_id, is_active) WHERE is_active = TRUE;

-- Enable RLS
ALTER TABLE user_limitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own limitations" ON user_limitations FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own limitations" ON user_limitations FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own limitations" ON user_limitations FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can delete own limitations" ON user_limitations FOR DELETE TO authenticated USING (auth.uid()::text = user_id::text);

-- ============================================================================
-- PRIORITY 2: USER EXPERIENCE (HIGH IMPACT)
-- ============================================================================

-- Table: workout_feedback
-- Purpose: Collect user ratings and feedback on workouts for recommendation improvement
-- Impact: Essential for learning what users enjoy and appropriate difficulty levels
CREATE TABLE IF NOT EXISTS workout_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID NOT NULL,
    workout_name TEXT,
    workout_type TEXT, -- 'program', 'auto-gen', 'custom'
    overall_rating INT CHECK (overall_rating BETWEEN 1 AND 5),
    difficulty_rating TEXT CHECK (difficulty_rating IN ('Too Easy', 'Slightly Easy', 'Just Right', 'Slightly Hard', 'Too Hard')),
    enjoyment_rating INT CHECK (enjoyment_rating BETWEEN 1 AND 5),
    energy_before TEXT CHECK (energy_before IN ('Low', 'Medium', 'High')),
    energy_after TEXT CHECK (energy_after IN ('Exhausted', 'Tired', 'Normal', 'Energized', 'Pumped')),
    would_do_again BOOLEAN,
    favorite_exercise TEXT,
    least_favorite_exercise TEXT,
    comments TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workout_feedback_user ON workout_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_feedback_workout ON workout_feedback(workout_id);
CREATE INDEX IF NOT EXISTS idx_workout_feedback_date ON workout_feedback(created_at DESC);

ALTER TABLE workout_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own feedback" ON workout_feedback FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own feedback" ON workout_feedback FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own feedback" ON workout_feedback FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);

-- Table: exercise_performance_history
-- Purpose: Track detailed performance for each exercise to enable progressive overload
-- Impact: Enables proper weight progression and personalized recommendations
CREATE TABLE IF NOT EXISTS exercise_performance_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID,
    exercise_name TEXT NOT NULL,
    exercise_id TEXT, -- Core Data exercise ID
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    best_set_weight DOUBLE PRECISION,
    best_set_reps INT,
    total_sets INT,
    total_reps INT,
    total_volume DOUBLE PRECISION, -- sum(weight * reps) across all sets
    average_rpe DOUBLE PRECISION,
    one_rep_max_estimate DOUBLE PRECISION, -- Calculated using Epley formula
    form_quality TEXT CHECK (form_quality IN ('Poor', 'Fair', 'Good', 'Excellent')),
    difficulty_feedback TEXT CHECK (difficulty_feedback IN ('Too Light', 'Light', 'Just Right', 'Heavy', 'Too Heavy')),
    equipment_used TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_perf_history_user_exercise ON exercise_performance_history(user_id, exercise_name);
CREATE INDEX IF NOT EXISTS idx_perf_history_user_date ON exercise_performance_history(user_id, workout_date DESC);
CREATE INDEX IF NOT EXISTS idx_perf_history_date ON exercise_performance_history(workout_date DESC);

ALTER TABLE exercise_performance_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own performance" ON exercise_performance_history FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own performance" ON exercise_performance_history FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);

-- Table: equipment_inventory
-- Purpose: Track exactly what equipment and weights each user has available
-- Impact: Prevents recommending exercises with unavailable equipment or weights
CREATE TABLE IF NOT EXISTS equipment_inventory (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    equipment_type TEXT NOT NULL, -- 'Dumbbell', 'Barbell', 'Kettlebell', 'Cable Machine', etc.
    equipment_brand TEXT,
    max_weight_available DOUBLE PRECISION, -- Max weight in lbs or kg
    min_weight_available DOUBLE PRECISION, -- Min weight in lbs or kg
    weight_increments DOUBLE PRECISION, -- 2.5, 5, 10 lbs
    weight_unit TEXT DEFAULT 'lbs' CHECK (weight_unit IN ('lbs', 'kg')),
    quantity INT DEFAULT 1, -- How many of this equipment (e.g., 2 dumbbells)
    equipment_condition TEXT CHECK (equipment_condition IN ('New', 'Good', 'Fair', 'Worn', 'Broken')),
    is_available BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_equipment_user ON equipment_inventory(user_id);
CREATE INDEX IF NOT EXISTS idx_equipment_type ON equipment_inventory(equipment_type);

ALTER TABLE equipment_inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own equipment" ON equipment_inventory FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own equipment" ON equipment_inventory FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own equipment" ON equipment_inventory FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can delete own equipment" ON equipment_inventory FOR DELETE TO authenticated USING (auth.uid()::text = user_id::text);

-- ============================================================================
-- PRIORITY 3: RECOMMENDATION QUALITY (MEDIUM IMPACT)
-- ============================================================================

-- Table: workout_context
-- Purpose: Track contextual factors (sleep, stress, time of day) to identify patterns
-- Impact: Learn when users perform best and adjust recommendations accordingly
CREATE TABLE IF NOT EXISTS workout_context (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    workout_id UUID NOT NULL,
    workout_date DATE NOT NULL DEFAULT CURRENT_DATE,
    workout_time TIME NOT NULL DEFAULT CURRENT_TIME,
    day_of_week TEXT NOT NULL, -- 'Monday', 'Tuesday', etc.
    sleep_hours DOUBLE PRECISION,
    sleep_quality TEXT CHECK (sleep_quality IN ('Poor', 'Fair', 'Good', 'Great')),
    stress_level INT CHECK (stress_level BETWEEN 1 AND 10),
    nutrition_quality TEXT CHECK (nutrition_quality IN ('Fasted', 'Light Snack', 'Light Meal', 'Full Meal', 'Heavy Meal')),
    hours_since_last_meal DOUBLE PRECISION,
    hours_since_last_workout DOUBLE PRECISION,
    location TEXT, -- 'Home', 'Gym', 'Park', 'Hotel', etc.
    workout_partner_present BOOLEAN DEFAULT FALSE,
    temperature TEXT, -- 'Cold', 'Cool', 'Comfortable', 'Warm', 'Hot'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_context_user ON workout_context(user_id);
CREATE INDEX IF NOT EXISTS idx_context_date ON workout_context(workout_date DESC);
CREATE INDEX IF NOT EXISTS idx_context_day ON workout_context(day_of_week);

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own context" ON workout_context FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own context" ON workout_context FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own context" ON workout_context FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);

-- Table: recovery_metrics
-- Purpose: Track daily recovery state to prevent overtraining
-- Impact: Adjust workout intensity based on recovery, suggest rest days when needed
CREATE TABLE IF NOT EXISTS recovery_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    soreness_level INT CHECK (soreness_level BETWEEN 0 AND 10),
    soreness_areas TEXT[], -- ['Chest', 'Shoulders', 'Lower Back']
    fatigue_level INT CHECK (fatigue_level BETWEEN 0 AND 10),
    readiness_to_train INT CHECK (readiness_to_train BETWEEN 0 AND 10),
    sleep_hours DOUBLE PRECISION,
    sleep_quality TEXT CHECK (sleep_quality IN ('Poor', 'Fair', 'Good', 'Great')),
    stress_level INT CHECK (stress_level BETWEEN 1 AND 10),
    resting_heart_rate INT, -- If user tracks HRV/RHR
    took_rest_day BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_recovery_user ON recovery_metrics(user_id);
CREATE INDEX IF NOT EXISTS idx_recovery_date ON recovery_metrics(date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_recovery_user_date ON recovery_metrics(user_id, date);

ALTER TABLE recovery_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own recovery" ON recovery_metrics FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own recovery" ON recovery_metrics FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own recovery" ON recovery_metrics FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);

-- Table: program_feedback
-- Purpose: Collect feedback on completed or abandoned programs
-- Impact: Learn which program structures work best, why users quit programs
CREATE TABLE IF NOT EXISTS program_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    program_id TEXT NOT NULL,
    program_name TEXT NOT NULL,
    program_type TEXT, -- 'Smart', 'Generated', 'Cloud', 'Custom'
    days_completed INT NOT NULL,
    total_days INT NOT NULL,
    completion_percentage DOUBLE PRECISION GENERATED ALWAYS AS (CAST(days_completed AS DOUBLE PRECISION) / NULLIF(total_days, 0) * 100) STORED,
    overall_rating INT CHECK (overall_rating BETWEEN 1 AND 5),
    difficulty_rating TEXT CHECK (difficulty_rating IN ('Too Easy', 'Slightly Easy', 'Just Right', 'Slightly Hard', 'Too Hard')),
    enjoyment_rating INT CHECK (enjoyment_rating BETWEEN 1 AND 5),
    saw_results BOOLEAN,
    would_recommend BOOLEAN,
    favorite_day INT,
    least_favorite_day INT,
    why_stopped TEXT, -- If completion_percentage < 100
    what_would_change TEXT,
    comments TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_program_feedback_user ON program_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_program_feedback_program ON program_feedback(program_id);
CREATE INDEX IF NOT EXISTS idx_program_feedback_completion ON program_feedback(completion_percentage DESC);

ALTER TABLE program_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own program feedback" ON program_feedback FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can insert own program feedback" ON program_feedback FOR INSERT TO authenticated WITH CHECK (auth.uid()::text = user_id::text);
CREATE POLICY "Users can update own program feedback" ON program_feedback FOR UPDATE TO authenticated USING (auth.uid()::text = user_id::text);

-- Table: equipment_proficiency
-- Purpose: Track how comfortable/skilled user is with each equipment type
-- Impact: Avoid recommending complex equipment to beginners
CREATE TABLE IF NOT EXISTS equipment_proficiency (
    user_id UUID NOT NULL,
    equipment_type TEXT NOT NULL,
    proficiency_level TEXT NOT NULL CHECK (proficiency_level IN ('Novice', 'Comfortable', 'Proficient', 'Expert')),
    first_used DATE DEFAULT CURRENT_DATE,
    last_used DATE DEFAULT CURRENT_DATE,
    times_used INT DEFAULT 0,
    needs_instruction BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, equipment_type)
);

CREATE INDEX IF NOT EXISTS idx_proficiency_user ON equipment_proficiency(user_id);

ALTER TABLE equipment_proficiency ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own proficiency" ON equipment_proficiency FOR SELECT TO authenticated USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage own proficiency" ON equipment_proficiency FOR ALL TO authenticated USING (auth.uid()::text = user_id::text);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function: Get active user limitations
CREATE OR REPLACE FUNCTION get_active_limitations(p_user_id UUID)
RETURNS TABLE (
    limitation_type TEXT,
    affected_area TEXT,
    severity TEXT,
    exercises_to_avoid TEXT[],
    movement_patterns_to_avoid TEXT[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ul.limitation_type,
        ul.affected_area,
        ul.severity,
        ul.exercises_to_avoid,
        ul.movement_patterns_to_avoid
    FROM user_limitations ul
    WHERE ul.user_id = p_user_id 
      AND ul.is_active = TRUE
    ORDER BY ul.severity DESC, ul.started_date DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Calculate One-Rep Max (Epley Formula)
CREATE OR REPLACE FUNCTION calculate_one_rep_max(weight DOUBLE PRECISION, reps INT)
RETURNS DOUBLE PRECISION AS $$
BEGIN
    IF reps = 1 THEN
        RETURN weight;
    ELSIF reps > 12 THEN
        -- Formula becomes less accurate above 12 reps
        RETURN weight * (1 + 0.033 * 12);
    ELSE
        RETURN weight * (1 + 0.033 * reps);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function: Get exercise progression trend
CREATE OR REPLACE FUNCTION get_exercise_progression(
    p_user_id UUID,
    p_exercise_name TEXT,
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    workout_date DATE,
    best_weight DOUBLE PRECISION,
    best_reps INT,
    total_volume DOUBLE PRECISION,
    one_rm_estimate DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        eph.workout_date,
        eph.best_set_weight,
        eph.best_set_reps,
        eph.total_volume,
        eph.one_rep_max_estimate
    FROM exercise_performance_history eph
    WHERE eph.user_id = p_user_id 
      AND eph.exercise_name = p_exercise_name
    ORDER BY eph.workout_date DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- MATERIALIZED VIEWS FOR ANALYTICS
-- ============================================================================

-- View: User recovery patterns
CREATE MATERIALIZED VIEW IF NOT EXISTS user_recovery_patterns AS
SELECT 
    user_id,
    AVG(readiness_to_train) as avg_readiness,
    AVG(soreness_level) as avg_soreness,
    AVG(fatigue_level) as avg_fatigue,
    AVG(sleep_hours) as avg_sleep,
    COUNT(*) as total_check_ins,
    SUM(CASE WHEN took_rest_day THEN 1 ELSE 0 END) as rest_days_taken
FROM recovery_metrics
GROUP BY user_id;

CREATE INDEX IF NOT EXISTS idx_recovery_patterns_user ON user_recovery_patterns(user_id);

-- View: Exercise performance summary
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_performance_summary AS
SELECT 
    user_id,
    exercise_name,
    COUNT(*) as times_performed,
    MAX(one_rep_max_estimate) as max_1rm,
    AVG(average_rpe) as avg_rpe,
    MAX(workout_date) as last_performed,
    AVG(total_volume) as avg_volume
FROM exercise_performance_history
GROUP BY user_id, exercise_name;

CREATE INDEX IF NOT EXISTS idx_perf_summary_user_exercise ON exercise_performance_summary(user_id, exercise_name);

-- View: Workout satisfaction trends
CREATE MATERIALIZED VIEW IF NOT EXISTS workout_satisfaction_trends AS
SELECT 
    user_id,
    workout_type,
    AVG(overall_rating) as avg_overall_rating,
    AVG(enjoyment_rating) as avg_enjoyment,
    COUNT(*) as total_feedback,
    SUM(CASE WHEN would_do_again THEN 1 ELSE 0 END) as would_repeat_count
FROM workout_feedback
GROUP BY user_id, workout_type;

CREATE INDEX IF NOT EXISTS idx_satisfaction_trends_user ON workout_satisfaction_trends(user_id);

-- Function: Refresh all materialized views
CREATE OR REPLACE FUNCTION refresh_performance_views()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_recovery_patterns;
    result := result || 'Recovery patterns refreshed. ';
    
    REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_performance_summary;
    result := result || 'Performance summary refreshed. ';
    
    REFRESH MATERIALIZED VIEW CONCURRENTLY workout_satisfaction_trends;
    result := result || 'Satisfaction trends refreshed.';
    
    RETURN result;
EXCEPTION WHEN OTHERS THEN
    RETURN 'Error refreshing views: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ✅ MIGRATION COMPLETE
-- ============================================================================
-- All tables, indexes, RLS policies, and helper functions have been created.
-- 
-- Next steps:
-- 1. Verify tables in Supabase Table Editor
-- 2. Test RLS policies
-- 3. Update Swift code to use new tables
-- 4. Create UI for new data collection points
-- ============================================================================

