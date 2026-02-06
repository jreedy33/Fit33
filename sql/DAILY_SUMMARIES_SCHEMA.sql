-- ============================================================================
-- DAILY SUMMARIES SCHEMA
-- Stores archived daily metrics for each user (nutrition, hydration, weight, workouts)
-- This data is used for historical tracking, analytics, and trends
-- ============================================================================

-- 1. Create daily_summaries table
-- ============================================================================
CREATE TABLE IF NOT EXISTS daily_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,  -- The date this summary represents (YYYY-MM-DD)
    
    -- Nutrition metrics
    calories_consumed INT DEFAULT 0,
    protein_g INT DEFAULT 0,
    carbs_g INT DEFAULT 0,
    fat_g INT DEFAULT 0,
    meals_logged INT DEFAULT 0,
    
    -- Hydration metrics
    hydration_ml INT DEFAULT 0,
    hydration_goal_ml INT DEFAULT 2500,
    hydration_goal_met BOOLEAN DEFAULT FALSE,
    
    -- Weight metrics (nullable - user may not log daily)
    weight_kg DOUBLE PRECISION,
    weight_lbs DOUBLE PRECISION,
    
    -- Workout metrics
    workout_count INT DEFAULT 0,
    workout_minutes INT DEFAULT 0,
    calories_burned INT DEFAULT 0,
    
    -- Activity metrics (from HealthKit)
    step_count INT DEFAULT 0,
    active_calories INT DEFAULT 0,
    distance_km DOUBLE PRECISION,
    
    -- Sleep metrics (optional, from HealthKit)
    sleep_hours DOUBLE PRECISION,
    sleep_quality_score INT,  -- 0-100 scale
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure one summary per user per day
    UNIQUE(user_id, date)
);

-- 2. Create indexes for efficient querying
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_daily_summaries_user_date 
    ON daily_summaries(user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_daily_summaries_date 
    ON daily_summaries(date DESC);

-- 3. Enable Row Level Security
-- ============================================================================
ALTER TABLE daily_summaries ENABLE ROW LEVEL SECURITY;

-- Users can only see/modify their own summaries
CREATE POLICY "Users can view own daily summaries" ON daily_summaries
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own daily summaries" ON daily_summaries
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own daily summaries" ON daily_summaries
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own daily summaries" ON daily_summaries
    FOR DELETE USING (auth.uid() = user_id);

-- 4. Create trigger for updated_at
-- ============================================================================
CREATE OR REPLACE FUNCTION update_daily_summaries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_daily_summaries_updated_at
    BEFORE UPDATE ON daily_summaries
    FOR EACH ROW
    EXECUTE FUNCTION update_daily_summaries_updated_at();

-- 5. Create function to get user's weekly summary
-- ============================================================================
CREATE OR REPLACE FUNCTION get_weekly_summary(p_user_id UUID, p_weeks_back INT DEFAULT 0)
RETURNS TABLE (
    week_start DATE,
    week_end DATE,
    avg_calories_consumed NUMERIC,
    avg_protein_g NUMERIC,
    avg_carbs_g NUMERIC,
    avg_fat_g NUMERIC,
    total_meals_logged INT,
    avg_hydration_ml NUMERIC,
    hydration_goals_met INT,
    avg_weight_kg NUMERIC,
    avg_weight_lbs NUMERIC,
    weight_change_kg NUMERIC,
    total_workouts INT,
    total_workout_minutes INT,
    total_calories_burned INT,
    avg_step_count NUMERIC,
    days_with_data INT
) AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
BEGIN
    -- Calculate the week range
    v_week_end := DATE_TRUNC('week', CURRENT_DATE)::DATE - (p_weeks_back * 7) - 1;
    v_week_start := v_week_end - 6;
    
    RETURN QUERY
    SELECT
        v_week_start AS week_start,
        v_week_end AS week_end,
        ROUND(AVG(calories_consumed)::NUMERIC, 0) AS avg_calories_consumed,
        ROUND(AVG(protein_g)::NUMERIC, 0) AS avg_protein_g,
        ROUND(AVG(carbs_g)::NUMERIC, 0) AS avg_carbs_g,
        ROUND(AVG(fat_g)::NUMERIC, 0) AS avg_fat_g,
        SUM(meals_logged)::INT AS total_meals_logged,
        ROUND(AVG(hydration_ml)::NUMERIC, 0) AS avg_hydration_ml,
        SUM(CASE WHEN hydration_goal_met THEN 1 ELSE 0 END)::INT AS hydration_goals_met,
        ROUND(AVG(weight_kg)::NUMERIC, 2) AS avg_weight_kg,
        ROUND(AVG(weight_lbs)::NUMERIC, 2) AS avg_weight_lbs,
        ROUND((
            (SELECT ds2.weight_kg FROM daily_summaries ds2 
             WHERE ds2.user_id = p_user_id AND ds2.weight_kg IS NOT NULL 
             AND ds2.date BETWEEN v_week_start AND v_week_end
             ORDER BY ds2.date DESC LIMIT 1)
            -
            (SELECT ds3.weight_kg FROM daily_summaries ds3 
             WHERE ds3.user_id = p_user_id AND ds3.weight_kg IS NOT NULL 
             AND ds3.date BETWEEN v_week_start AND v_week_end
             ORDER BY ds3.date ASC LIMIT 1)
        )::NUMERIC, 2) AS weight_change_kg,
        SUM(workout_count)::INT AS total_workouts,
        SUM(workout_minutes)::INT AS total_workout_minutes,
        SUM(calories_burned)::INT AS total_calories_burned,
        ROUND(AVG(step_count)::NUMERIC, 0) AS avg_step_count,
        COUNT(*)::INT AS days_with_data
    FROM daily_summaries
    WHERE user_id = p_user_id
    AND date BETWEEN v_week_start AND v_week_end;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Create function to get user's monthly trends
-- ============================================================================
CREATE OR REPLACE FUNCTION get_monthly_trends(p_user_id UUID, p_months INT DEFAULT 3)
RETURNS TABLE (
    month_year TEXT,
    avg_daily_calories INT,
    avg_daily_protein INT,
    avg_weight_kg NUMERIC,
    total_workouts INT,
    total_workout_minutes INT,
    avg_daily_steps INT,
    days_logged INT,
    consistency_score NUMERIC  -- Percentage of days with data
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        TO_CHAR(ds.date, 'YYYY-MM') AS month_year,
        ROUND(AVG(ds.calories_consumed))::INT AS avg_daily_calories,
        ROUND(AVG(ds.protein_g))::INT AS avg_daily_protein,
        ROUND(AVG(ds.weight_kg)::NUMERIC, 2) AS avg_weight_kg,
        SUM(ds.workout_count)::INT AS total_workouts,
        SUM(ds.workout_minutes)::INT AS total_workout_minutes,
        ROUND(AVG(ds.step_count))::INT AS avg_daily_steps,
        COUNT(*)::INT AS days_logged,
        ROUND((COUNT(*)::NUMERIC / 
            EXTRACT(DAY FROM (DATE_TRUNC('month', ds.date) + INTERVAL '1 month - 1 day'))
        ) * 100, 1) AS consistency_score
    FROM daily_summaries ds
    WHERE ds.user_id = p_user_id
    AND ds.date >= (CURRENT_DATE - (p_months || ' months')::INTERVAL)
    GROUP BY TO_CHAR(ds.date, 'YYYY-MM')
    ORDER BY month_year DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Create function to get streak information
-- ============================================================================
CREATE OR REPLACE FUNCTION get_logging_streaks(p_user_id UUID)
RETURNS TABLE (
    current_logging_streak INT,
    longest_logging_streak INT,
    total_days_logged INT,
    current_workout_streak INT,
    longest_workout_streak INT,
    current_hydration_streak INT,  -- Days meeting hydration goal
    longest_hydration_streak INT
) AS $$
DECLARE
    v_current_logging INT := 0;
    v_longest_logging INT := 0;
    v_temp_streak INT := 0;
    v_current_workout INT := 0;
    v_longest_workout INT := 0;
    v_current_hydration INT := 0;
    v_longest_hydration INT := 0;
    v_total_days INT := 0;
    v_prev_date DATE := NULL;
    v_rec RECORD;
BEGIN
    -- Calculate logging streak (consecutive days with any data)
    FOR v_rec IN (
        SELECT date, workout_count, hydration_goal_met
        FROM daily_summaries
        WHERE user_id = p_user_id
        ORDER BY date DESC
    ) LOOP
        v_total_days := v_total_days + 1;
        
        IF v_prev_date IS NULL OR (v_prev_date - v_rec.date) = 1 THEN
            v_current_logging := v_current_logging + 1;
        ELSE
            IF v_current_logging > v_longest_logging THEN
                v_longest_logging := v_current_logging;
            END IF;
            v_current_logging := 1;
        END IF;
        
        v_prev_date := v_rec.date;
    END LOOP;
    
    IF v_current_logging > v_longest_logging THEN
        v_longest_logging := v_current_logging;
    END IF;
    
    -- Calculate workout streak
    v_prev_date := NULL;
    v_current_workout := 0;
    FOR v_rec IN (
        SELECT date, workout_count
        FROM daily_summaries
        WHERE user_id = p_user_id AND workout_count > 0
        ORDER BY date DESC
    ) LOOP
        IF v_prev_date IS NULL OR (v_prev_date - v_rec.date) = 1 THEN
            v_current_workout := v_current_workout + 1;
        ELSE
            IF v_current_workout > v_longest_workout THEN
                v_longest_workout := v_current_workout;
            END IF;
            v_current_workout := 1;
        END IF;
        v_prev_date := v_rec.date;
    END LOOP;
    
    IF v_current_workout > v_longest_workout THEN
        v_longest_workout := v_current_workout;
    END IF;
    
    -- Calculate hydration streak
    v_prev_date := NULL;
    v_current_hydration := 0;
    FOR v_rec IN (
        SELECT date
        FROM daily_summaries
        WHERE user_id = p_user_id AND hydration_goal_met = TRUE
        ORDER BY date DESC
    ) LOOP
        IF v_prev_date IS NULL OR (v_prev_date - v_rec.date) = 1 THEN
            v_current_hydration := v_current_hydration + 1;
        ELSE
            IF v_current_hydration > v_longest_hydration THEN
                v_longest_hydration := v_current_hydration;
            END IF;
            v_current_hydration := 1;
        END IF;
        v_prev_date := v_rec.date;
    END LOOP;
    
    IF v_current_hydration > v_longest_hydration THEN
        v_longest_hydration := v_current_hydration;
    END IF;
    
    RETURN QUERY SELECT 
        v_current_logging,
        v_longest_logging,
        v_total_days,
        v_current_workout,
        v_longest_workout,
        v_current_hydration,
        v_longest_hydration;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Create function to backfill historical data (one-time migration)
-- ============================================================================
CREATE OR REPLACE FUNCTION backfill_daily_summaries(p_user_id UUID, p_days INT DEFAULT 30)
RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    v_date DATE;
BEGIN
    FOR i IN 0..p_days LOOP
        v_date := CURRENT_DATE - i;
        
        -- Insert if not exists (won't overwrite existing data)
        INSERT INTO daily_summaries (user_id, date)
        VALUES (p_user_id, v_date)
        ON CONFLICT (user_id, date) DO NOTHING;
        
        IF FOUND THEN
            v_count := v_count + 1;
        END IF;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- NOTES:
-- 1. Run this SQL in Supabase SQL Editor to create the schema
-- 2. The daily_summaries table will be populated by DailyResetService.swift
-- 3. Use get_weekly_summary() and get_monthly_trends() for analytics dashboards
-- 4. Use get_logging_streaks() to display user streaks
-- ============================================================================
