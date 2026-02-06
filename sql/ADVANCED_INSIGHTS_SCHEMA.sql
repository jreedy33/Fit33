-- ============================================================================
-- ADVANCED PERSONALIZED INSIGHTS SCHEMA
-- Comprehensive correlation tracking for smarter, data-driven recommendations
-- ============================================================================

-- ============================================================================
-- 1. CORRELATION TRACKING TABLE
-- Stores computed correlations between different metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_metric_correlations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- What metrics are being correlated
    metric_a TEXT NOT NULL,  -- e.g., 'protein_intake', 'sleep_hours', 'hydration'
    metric_b TEXT NOT NULL,  -- e.g., 'strength_gain', 'weight_change', 'workout_performance'
    
    -- Correlation data
    correlation_coefficient DOUBLE PRECISION,  -- -1 to 1 (Pearson correlation)
    sample_size INT DEFAULT 0,  -- Number of data points used
    confidence_level DOUBLE PRECISION,  -- 0-1 confidence in the correlation
    
    -- Time window
    time_window_days INT DEFAULT 30,  -- Rolling window for calculation
    
    -- Direction and interpretation
    relationship_direction TEXT CHECK (relationship_direction IN ('positive', 'negative', 'neutral', 'insufficient_data')),
    relationship_strength TEXT CHECK (relationship_strength IN ('strong', 'moderate', 'weak', 'none')),
    
    -- When correlation is actionable
    is_actionable BOOLEAN DEFAULT FALSE,
    action_recommendation TEXT,  -- e.g., "Increase protein by 20g for better gains"
    
    -- Timestamps
    calculated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, metric_a, metric_b, time_window_days)
);

CREATE INDEX idx_user_correlations_user ON user_metric_correlations(user_id);
CREATE INDEX idx_user_correlations_actionable ON user_metric_correlations(user_id, is_actionable) WHERE is_actionable = TRUE;

-- ============================================================================
-- 2. PERSONALIZED INSIGHTS TABLE
-- Stores generated insights with full context
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_personalized_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Insight metadata
    insight_type TEXT NOT NULL,  -- 'achievement', 'correlation', 'warning', 'tip', 'milestone', 'trend'
    insight_category TEXT NOT NULL,  -- 'nutrition', 'workout', 'weight', 'hydration', 'social', 'streak', 'goal'
    
    -- The insight itself
    title TEXT NOT NULL,  -- Short headline
    message TEXT NOT NULL,  -- Full insight message with data
    detail_message TEXT,  -- Optional deeper explanation
    
    -- Supporting data (JSON for flexibility)
    data_points JSONB,  -- {"protein_avg": 150, "weight_change": 2.5, "days": 7}
    
    -- Context
    related_goal TEXT,  -- 'build_muscle', 'lose_weight', etc.
    time_period TEXT,  -- 'today', 'this_week', 'this_month', 'all_time'
    
    -- Display properties
    priority INT DEFAULT 5,  -- 1-10, higher = more important
    icon TEXT,  -- SF Symbol name
    accent_color TEXT,  -- Hex color or named color
    
    -- User interaction
    is_read BOOLEAN DEFAULT FALSE,
    is_dismissed BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    
    -- Validity
    valid_from TIMESTAMPTZ DEFAULT NOW(),
    valid_until TIMESTAMPTZ,  -- NULL = never expires
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_insights_user_active ON user_personalized_insights(user_id, is_dismissed, valid_until);
CREATE INDEX idx_insights_priority ON user_personalized_insights(user_id, priority DESC);
CREATE INDEX idx_insights_category ON user_personalized_insights(user_id, insight_category);

-- ============================================================================
-- 3. GOAL-SPECIFIC PROGRESS METRICS
-- Tracks detailed progress for each goal type
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_goal_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    goal_type TEXT NOT NULL,  -- 'build_muscle', 'lose_weight', 'get_stronger', etc.
    
    -- Date range
    week_start DATE NOT NULL,
    
    -- Nutrition metrics
    avg_daily_calories INT,
    avg_daily_protein INT,
    avg_daily_carbs INT,
    avg_daily_fat INT,
    protein_goal_hit_days INT DEFAULT 0,
    calorie_goal_hit_days INT DEFAULT 0,
    nutrition_consistency_score DOUBLE PRECISION,  -- 0-100
    
    -- Workout metrics
    workouts_completed INT DEFAULT 0,
    total_volume_lbs DOUBLE PRECISION DEFAULT 0,
    avg_workout_duration_min INT,
    personal_records_count INT DEFAULT 0,
    exercises_performed INT DEFAULT 0,
    sets_completed INT DEFAULT 0,
    
    -- Weight/body composition
    starting_weight_lbs DOUBLE PRECISION,
    ending_weight_lbs DOUBLE PRECISION,
    weight_change_lbs DOUBLE PRECISION,
    weight_trend TEXT,  -- 'gaining', 'losing', 'maintaining', 'fluctuating'
    
    -- Recovery/activity
    avg_daily_steps INT,
    avg_sleep_hours DOUBLE PRECISION,
    hydration_goal_hit_days INT DEFAULT 0,
    rest_days_taken INT DEFAULT 0,
    
    -- Calculated scores
    overall_consistency_score DOUBLE PRECISION,  -- 0-100
    goal_alignment_score DOUBLE PRECISION,  -- How well actions align with goal
    predicted_outcome TEXT,  -- 'on_track', 'ahead', 'behind', 'at_risk'
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, goal_type, week_start)
);

CREATE INDEX idx_goal_metrics_user ON user_goal_metrics(user_id, goal_type, week_start DESC);

-- ============================================================================
-- 4. PATTERN DETECTION TABLE
-- Stores detected patterns in user behavior
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_behavior_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Pattern identification
    pattern_type TEXT NOT NULL,  -- 'time_preference', 'workout_style', 'nutrition_habit', 'social_behavior'
    pattern_name TEXT NOT NULL,  -- e.g., 'morning_person', 'high_protein_eater', 'social_workout_booster'
    
    -- Pattern data
    pattern_data JSONB NOT NULL,  -- Flexible storage for pattern details
    
    -- Confidence
    confidence_score DOUBLE PRECISION,  -- 0-1
    data_points_used INT,
    
    -- Impact
    impact_area TEXT,  -- What this pattern affects
    impact_score DOUBLE PRECISION,  -- How much it affects outcomes
    
    -- Recommendations
    leverage_recommendation TEXT,  -- How to use this pattern positively
    
    -- Timestamps
    first_detected TIMESTAMPTZ DEFAULT NOW(),
    last_confirmed TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, pattern_type, pattern_name)
);

CREATE INDEX idx_patterns_user ON user_behavior_patterns(user_id, pattern_type);

-- ============================================================================
-- 5. STREAK & MILESTONE TRACKING
-- Tracks various streaks beyond just workouts
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_streak_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    streak_type TEXT NOT NULL,  -- 'workout', 'protein_goal', 'calorie_goal', 'hydration', 'logging', 'weight_log'
    
    -- Current streak
    current_streak INT DEFAULT 0,
    current_streak_start DATE,
    
    -- Best streak
    longest_streak INT DEFAULT 0,
    longest_streak_start DATE,
    longest_streak_end DATE,
    
    -- Statistics
    total_days_achieved INT DEFAULT 0,
    average_streak_length DOUBLE PRECISION,
    streak_break_count INT DEFAULT 0,
    
    -- Last activity
    last_achieved_date DATE,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, streak_type)
);

CREATE INDEX idx_streaks_user ON user_streak_tracking(user_id);

-- ============================================================================
-- 6. PERFORMANCE WINDOWS
-- Track performance in different time windows for trend analysis
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_performance_windows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    window_type TEXT NOT NULL,  -- '7_day', '14_day', '30_day', '90_day'
    window_end_date DATE NOT NULL,
    
    -- Volume metrics
    total_workout_volume DOUBLE PRECISION,
    avg_workout_volume DOUBLE PRECISION,
    volume_change_percent DOUBLE PRECISION,  -- vs previous window
    
    -- Frequency metrics
    workouts_completed INT,
    workout_frequency_per_week DOUBLE PRECISION,
    
    -- Strength metrics
    avg_weight_lifted DOUBLE PRECISION,
    max_weight_lifted DOUBLE PRECISION,
    personal_records INT,
    estimated_1rm_change_percent DOUBLE PRECISION,
    
    -- Nutrition metrics
    avg_daily_calories INT,
    avg_daily_protein INT,
    protein_goal_adherence_percent DOUBLE PRECISION,
    calorie_goal_adherence_percent DOUBLE PRECISION,
    
    -- Body composition
    weight_change_lbs DOUBLE PRECISION,
    weight_trend TEXT,
    
    -- Recovery
    avg_rest_between_workouts DOUBLE PRECISION,  -- days
    avg_sleep_hours DOUBLE PRECISION,
    
    -- Calculated performance score
    overall_performance_score DOUBLE PRECISION,  -- 0-100
    performance_trend TEXT,  -- 'improving', 'stable', 'declining'
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, window_type, window_end_date)
);

CREATE INDEX idx_performance_windows ON user_performance_windows(user_id, window_type, window_end_date DESC);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE user_metric_correlations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_personalized_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_goal_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_behavior_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_streak_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_performance_windows ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can manage own correlations" ON user_metric_correlations
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own insights" ON user_personalized_insights
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own goal metrics" ON user_goal_metrics
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own patterns" ON user_behavior_patterns
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own streaks" ON user_streak_tracking
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own performance windows" ON user_performance_windows
    FOR ALL USING (auth.uid() = user_id);

-- ============================================================================
-- FUNCTIONS FOR INSIGHT GENERATION
-- ============================================================================

-- Function to calculate correlation between two metrics
CREATE OR REPLACE FUNCTION calculate_metric_correlation(
    p_user_id UUID,
    p_metric_a TEXT,
    p_metric_b TEXT,
    p_days INT DEFAULT 30
)
RETURNS TABLE (
    correlation DOUBLE PRECISION,
    sample_size INT,
    direction TEXT,
    strength TEXT
) AS $$
DECLARE
    v_corr DOUBLE PRECISION;
    v_count INT;
    v_direction TEXT;
    v_strength TEXT;
BEGIN
    -- This is a template - actual implementation depends on metric types
    -- For now, return placeholder
    v_corr := 0;
    v_count := 0;
    v_direction := 'insufficient_data';
    v_strength := 'none';
    
    RETURN QUERY SELECT v_corr, v_count, v_direction, v_strength;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get active insights for a user
CREATE OR REPLACE FUNCTION get_active_insights(p_user_id UUID, p_limit INT DEFAULT 10)
RETURNS TABLE (
    id UUID,
    insight_type TEXT,
    insight_category TEXT,
    title TEXT,
    message TEXT,
    detail_message TEXT,
    data_points JSONB,
    priority INT,
    icon TEXT,
    accent_color TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.id,
        i.insight_type,
        i.insight_category,
        i.title,
        i.message,
        i.detail_message,
        i.data_points,
        i.priority,
        i.icon,
        i.accent_color,
        i.created_at
    FROM user_personalized_insights i
    WHERE i.user_id = p_user_id
    AND i.is_dismissed = FALSE
    AND (i.valid_until IS NULL OR i.valid_until > NOW())
    ORDER BY i.priority DESC, i.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get streak summary
CREATE OR REPLACE FUNCTION get_streak_summary(p_user_id UUID)
RETURNS TABLE (
    streak_type TEXT,
    current_streak INT,
    longest_streak INT,
    total_days_achieved INT,
    last_achieved_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.streak_type,
        s.current_streak,
        s.longest_streak,
        s.total_days_achieved,
        s.last_achieved_date
    FROM user_streak_tracking s
    WHERE s.user_id = p_user_id
    ORDER BY s.current_streak DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get goal-specific insights
CREATE OR REPLACE FUNCTION get_goal_insights(
    p_user_id UUID,
    p_goal_type TEXT,
    p_weeks INT DEFAULT 4
)
RETURNS TABLE (
    week_start DATE,
    nutrition_consistency_score DOUBLE PRECISION,
    overall_consistency_score DOUBLE PRECISION,
    goal_alignment_score DOUBLE PRECISION,
    weight_change_lbs DOUBLE PRECISION,
    personal_records_count INT,
    predicted_outcome TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.week_start,
        m.nutrition_consistency_score,
        m.overall_consistency_score,
        m.goal_alignment_score,
        m.weight_change_lbs,
        m.personal_records_count,
        m.predicted_outcome
    FROM user_goal_metrics m
    WHERE m.user_id = p_user_id
    AND m.goal_type = p_goal_type
    ORDER BY m.week_start DESC
    LIMIT p_weeks;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER TO UPDATE TIMESTAMPS
-- ============================================================================
CREATE OR REPLACE FUNCTION update_insights_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_correlations_updated
    BEFORE UPDATE ON user_metric_correlations
    FOR EACH ROW EXECUTE FUNCTION update_insights_updated_at();

CREATE TRIGGER trigger_insights_updated
    BEFORE UPDATE ON user_personalized_insights
    FOR EACH ROW EXECUTE FUNCTION update_insights_updated_at();

CREATE TRIGGER trigger_goal_metrics_updated
    BEFORE UPDATE ON user_goal_metrics
    FOR EACH ROW EXECUTE FUNCTION update_insights_updated_at();

CREATE TRIGGER trigger_patterns_updated
    BEFORE UPDATE ON user_behavior_patterns
    FOR EACH ROW EXECUTE FUNCTION update_insights_updated_at();

CREATE TRIGGER trigger_streaks_updated
    BEFORE UPDATE ON user_streak_tracking
    FOR EACH ROW EXECUTE FUNCTION update_insights_updated_at();

-- ============================================================================
-- SAMPLE INSIGHT GENERATION FUNCTION
-- Generate insights based on recent data
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_weekly_insights(p_user_id UUID)
RETURNS INT AS $$
DECLARE
    v_insights_created INT := 0;
    v_protein_streak INT;
    v_weight_change DOUBLE PRECISION;
    v_workout_count INT;
    v_pr_count INT;
    v_goal_type TEXT;
BEGIN
    -- Get user's primary goal
    SELECT fitness_goal INTO v_goal_type
    FROM user_profiles
    WHERE id = p_user_id;
    
    -- Get protein streak
    SELECT current_streak INTO v_protein_streak
    FROM user_streak_tracking
    WHERE user_id = p_user_id AND streak_type = 'protein_goal';
    
    -- Check for protein streak achievement (7+ days)
    IF v_protein_streak >= 7 THEN
        -- Get weight change this week
        SELECT COALESCE(
            (SELECT weight_lbs FROM daily_summaries 
             WHERE user_id = p_user_id AND weight_lbs IS NOT NULL 
             ORDER BY date DESC LIMIT 1)
            -
            (SELECT weight_lbs FROM daily_summaries 
             WHERE user_id = p_user_id AND weight_lbs IS NOT NULL 
             AND date <= CURRENT_DATE - 7
             ORDER BY date DESC LIMIT 1)
        , 0) INTO v_weight_change;
        
        -- Generate insight based on goal
        IF v_goal_type = 'Build Muscle' AND v_weight_change > 0 THEN
            INSERT INTO user_personalized_insights (
                user_id, insight_type, insight_category, title, message, detail_message,
                data_points, related_goal, time_period, priority, icon, accent_color, valid_until
            ) VALUES (
                p_user_id, 'achievement', 'nutrition',
                'Protein Consistency Paying Off! 💪',
                format('You hit your protein goal %s days in a row and gained %.1f lbs this week. The grind matters!', v_protein_streak, v_weight_change),
                'Consistent protein intake is crucial for muscle protein synthesis. Your body is responding to the extra fuel.',
                jsonb_build_object('protein_streak', v_protein_streak, 'weight_change', v_weight_change, 'goal', v_goal_type),
                v_goal_type, 'this_week', 9, 'flame.fill', 'orange',
                CURRENT_DATE + 7
            );
            v_insights_created := v_insights_created + 1;
        ELSIF v_goal_type = 'Lose Weight' AND v_weight_change < 0 THEN
            INSERT INTO user_personalized_insights (
                user_id, insight_type, insight_category, title, message, detail_message,
                data_points, related_goal, time_period, priority, icon, accent_color, valid_until
            ) VALUES (
                p_user_id, 'achievement', 'nutrition',
                'High Protein + Deficit = Fat Loss! 🔥',
                format('You hit your protein goal %s days in a row while losing %.1f lbs. Preserving muscle while cutting!', v_protein_streak, ABS(v_weight_change)),
                'High protein during a cut helps preserve lean muscle mass. You''re doing it right!',
                jsonb_build_object('protein_streak', v_protein_streak, 'weight_change', v_weight_change, 'goal', v_goal_type),
                v_goal_type, 'this_week', 9, 'flame.fill', 'green',
                CURRENT_DATE + 7
            );
            v_insights_created := v_insights_created + 1;
        END IF;
    END IF;
    
    -- Get workout count this week
    SELECT COALESCE(SUM(workout_count), 0) INTO v_workout_count
    FROM daily_summaries
    WHERE user_id = p_user_id
    AND date >= CURRENT_DATE - 7;
    
    -- Get PR count this week  
    SELECT COUNT(*) INTO v_pr_count
    FROM exercise_personal_records
    WHERE user_id = p_user_id
    AND (max_weight_date >= CURRENT_DATE - 7 OR max_reps_date >= CURRENT_DATE - 7);
    
    -- Generate workout insights
    IF v_workout_count >= 4 AND v_pr_count > 0 THEN
        INSERT INTO user_personalized_insights (
            user_id, insight_type, insight_category, title, message, detail_message,
            data_points, time_period, priority, icon, accent_color, valid_until
        ) VALUES (
            p_user_id, 'achievement', 'workout',
            'Strong Week! 🏆',
            format('You completed %s workouts and hit %s personal record(s) this week!', v_workout_count, v_pr_count),
            'Consistent training combined with progressive overload is the recipe for gains.',
            jsonb_build_object('workouts', v_workout_count, 'prs', v_pr_count),
            'this_week', 8, 'trophy.fill', 'yellow',
            CURRENT_DATE + 7
        );
        v_insights_created := v_insights_created + 1;
    END IF;
    
    RETURN v_insights_created;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- NOTES:
-- Run this SQL in Supabase SQL Editor to create the schema.
-- The PersonalizedInsightsService.swift will populate these tables and
-- generate insights based on the correlations detected.
-- ============================================================================
