-- ============================================================================
-- CARDIO TRACKING - COMPLETE DATABASE SETUP
-- ============================================================================
-- Run this script in your Supabase SQL Editor to enable full cardio tracking
-- ============================================================================

-- ============================================================================
-- TABLE 1: Cardio Workouts - Main table for all cardio sessions
-- ============================================================================
CREATE TABLE IF NOT EXISTS cardio_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Activity details
    activity_type TEXT NOT NULL, -- 'outdoor_run', 'treadmill', 'indoor_cycle', etc.
    workout_name TEXT, -- Optional custom name
    
    -- Goal tracking
    goal_type TEXT NOT NULL, -- 'open_goal', 'time', 'distance', 'calories'
    goal_value DOUBLE PRECISION, -- The target (minutes, km, or calories depending on goal_type)
    goal_achieved BOOLEAN DEFAULT FALSE,
    
    -- Core metrics
    duration_seconds INTEGER NOT NULL,
    distance_meters DOUBLE PRECISION DEFAULT 0,
    calories_burned DOUBLE PRECISION DEFAULT 0,
    
    -- Pace & Speed
    average_pace DOUBLE PRECISION, -- min/km
    best_pace DOUBLE PRECISION, -- min/km (fastest segment)
    average_speed DOUBLE PRECISION, -- km/h
    max_speed DOUBLE PRECISION, -- km/h
    
    -- Heart rate (from equipment or watch)
    average_heart_rate INTEGER,
    max_heart_rate INTEGER,
    min_heart_rate INTEGER,
    
    -- Activity-specific metrics
    cadence INTEGER, -- steps/min for running, RPM for cycling
    average_power INTEGER, -- watts (cycling, rowing)
    max_power INTEGER,
    total_elevation_gain DOUBLE PRECISION, -- meters
    average_incline DOUBLE PRECISION, -- percentage (treadmill)
    
    -- Equipment data (from Bluetooth devices)
    equipment_name TEXT, -- e.g., "Peloton Bike", "NordicTrack Treadmill"
    equipment_type TEXT, -- 'treadmill', 'bike', 'rower', etc.
    
    -- GPS Route data (for outdoor activities)
    route_coordinates JSONB, -- Array of {lat, lng, elevation, timestamp}
    route_summary JSONB, -- {start_location, end_location, total_distance, bounds}
    
    -- Splits/Laps data
    splits JSONB, -- Array of {distance, time, pace, heart_rate} per km/mile
    
    -- Weather conditions (for outdoor)
    weather_conditions JSONB, -- {temperature, humidity, wind_speed, conditions}
    
    -- Timestamps
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_user ON cardio_workouts(user_id);
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_activity ON cardio_workouts(activity_type);
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_date ON cardio_workouts(completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_user_activity ON cardio_workouts(user_id, activity_type);
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_user_date ON cardio_workouts(user_id, completed_at DESC);

-- Row Level Security
ALTER TABLE cardio_workouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own cardio workouts" ON cardio_workouts;
CREATE POLICY "Users can view own cardio workouts" ON cardio_workouts 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own cardio workouts" ON cardio_workouts;
CREATE POLICY "Users can insert own cardio workouts" ON cardio_workouts 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own cardio workouts" ON cardio_workouts;
CREATE POLICY "Users can update own cardio workouts" ON cardio_workouts 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own cardio workouts" ON cardio_workouts;
CREATE POLICY "Users can delete own cardio workouts" ON cardio_workouts 
    FOR DELETE TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- TABLE 2: Cardio Personal Records - Track PRs across different metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS cardio_personal_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Record details
    activity_type TEXT NOT NULL, -- 'outdoor_run', 'indoor_cycle', etc.
    record_type TEXT NOT NULL, -- 'fastest_5k', 'longest_run', 'most_calories_1hr', etc.
    record_category TEXT NOT NULL, -- 'speed', 'distance', 'duration', 'calories', 'power'
    
    -- Record value
    value DOUBLE PRECISION NOT NULL,
    unit TEXT NOT NULL, -- 'seconds', 'meters', 'calories', 'watts', 'min/km'
    
    -- Context
    workout_id UUID REFERENCES cardio_workouts(id) ON DELETE SET NULL,
    previous_value DOUBLE PRECISION, -- What the old record was
    improvement_percentage DOUBLE PRECISION, -- How much better than previous
    
    -- Timestamps
    achieved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cardio_prs_user ON cardio_personal_records(user_id);
CREATE INDEX IF NOT EXISTS idx_cardio_prs_activity ON cardio_personal_records(activity_type);
CREATE INDEX IF NOT EXISTS idx_cardio_prs_type ON cardio_personal_records(record_type);
CREATE INDEX IF NOT EXISTS idx_cardio_prs_user_activity ON cardio_personal_records(user_id, activity_type);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_prs_unique ON cardio_personal_records(user_id, activity_type, record_type);

-- Row Level Security
ALTER TABLE cardio_personal_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own cardio PRs" ON cardio_personal_records;
CREATE POLICY "Users can view own cardio PRs" ON cardio_personal_records 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own cardio PRs" ON cardio_personal_records;
CREATE POLICY "Users can insert own cardio PRs" ON cardio_personal_records 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own cardio PRs" ON cardio_personal_records;
CREATE POLICY "Users can update own cardio PRs" ON cardio_personal_records 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- TABLE 3: Cardio Goals - Weekly/Monthly goals and challenges
-- ============================================================================
CREATE TABLE IF NOT EXISTS cardio_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Goal definition
    goal_name TEXT NOT NULL, -- "Run 20km this week", "Burn 2000 calories"
    goal_type TEXT NOT NULL, -- 'distance', 'duration', 'calories', 'workouts', 'streak'
    activity_type TEXT, -- NULL means all cardio activities count
    
    -- Target and progress
    target_value DOUBLE PRECISION NOT NULL,
    current_value DOUBLE PRECISION DEFAULT 0,
    unit TEXT NOT NULL, -- 'meters', 'seconds', 'calories', 'count', 'days'
    
    -- Period
    period_type TEXT NOT NULL, -- 'daily', 'weekly', 'monthly', 'custom'
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    
    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cardio_goals_user ON cardio_goals(user_id);
CREATE INDEX IF NOT EXISTS idx_cardio_goals_active ON cardio_goals(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_cardio_goals_period ON cardio_goals(period_start, period_end);

-- Row Level Security
ALTER TABLE cardio_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own cardio goals" ON cardio_goals;
CREATE POLICY "Users can view own cardio goals" ON cardio_goals 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own cardio goals" ON cardio_goals;
CREATE POLICY "Users can insert own cardio goals" ON cardio_goals 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own cardio goals" ON cardio_goals;
CREATE POLICY "Users can update own cardio goals" ON cardio_goals 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own cardio goals" ON cardio_goals;
CREATE POLICY "Users can delete own cardio goals" ON cardio_goals 
    FOR DELETE TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- TABLE 4: Cardio Streaks - Track consistency
-- ============================================================================
CREATE TABLE IF NOT EXISTS cardio_streaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Streak type
    streak_type TEXT NOT NULL, -- 'daily_cardio', 'weekly_goal', 'activity_specific'
    activity_type TEXT, -- NULL for general cardio streak
    
    -- Streak data
    current_streak INTEGER DEFAULT 0,
    longest_streak INTEGER DEFAULT 0,
    last_activity_date DATE,
    streak_start_date DATE,
    
    -- Timestamps
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint: one streak record per user per type/activity
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_streaks_unique 
    ON cardio_streaks(user_id, streak_type, COALESCE(activity_type, ''));

-- Row Level Security
ALTER TABLE cardio_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own cardio streaks" ON cardio_streaks;
CREATE POLICY "Users can manage own cardio streaks" ON cardio_streaks 
    FOR ALL TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- TABLE 5: Cardio Weekly Summaries - Aggregated stats for trends
-- ============================================================================
CREATE TABLE IF NOT EXISTS cardio_weekly_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Week identifier
    week_start DATE NOT NULL,
    week_end DATE NOT NULL,
    
    -- Aggregated stats
    total_workouts INTEGER DEFAULT 0,
    total_duration_seconds INTEGER DEFAULT 0,
    total_distance_meters DOUBLE PRECISION DEFAULT 0,
    total_calories DOUBLE PRECISION DEFAULT 0,
    
    -- Averages
    avg_workout_duration INTEGER,
    avg_pace DOUBLE PRECISION,
    avg_heart_rate INTEGER,
    
    -- By activity breakdown (JSONB)
    activity_breakdown JSONB, -- {outdoor_run: {count, distance, duration}, treadmill: {...}}
    
    -- Goals achieved
    goals_completed INTEGER DEFAULT 0,
    prs_achieved INTEGER DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint: one summary per user per week
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_weekly_unique 
    ON cardio_weekly_summaries(user_id, week_start);

-- Row Level Security
ALTER TABLE cardio_weekly_summaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own cardio summaries" ON cardio_weekly_summaries;
CREATE POLICY "Users can manage own cardio summaries" ON cardio_weekly_summaries 
    FOR ALL TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- HELPER FUNCTION: Update cardio streak after workout
-- ============================================================================
CREATE OR REPLACE FUNCTION update_cardio_streak()
RETURNS TRIGGER AS $$
DECLARE
    v_last_date DATE;
    v_today DATE;
    v_current_streak INT;
    v_longest_streak INT;
BEGIN
    v_today := DATE(NEW.completed_at);
    
    -- Get or create streak record
    SELECT last_activity_date, current_streak, longest_streak
    INTO v_last_date, v_current_streak, v_longest_streak
    FROM cardio_streaks
    WHERE user_id = NEW.user_id 
      AND streak_type = 'daily_cardio'
      AND activity_type IS NULL;
    
    IF NOT FOUND THEN
        -- Create new streak record
        INSERT INTO cardio_streaks (user_id, streak_type, current_streak, longest_streak, last_activity_date, streak_start_date)
        VALUES (NEW.user_id, 'daily_cardio', 1, 1, v_today, v_today);
    ELSE
        -- Update existing streak
        IF v_last_date = v_today THEN
            -- Same day, no change
            NULL;
        ELSIF v_last_date = v_today - INTERVAL '1 day' THEN
            -- Consecutive day, increment streak
            v_current_streak := v_current_streak + 1;
            IF v_current_streak > v_longest_streak THEN
                v_longest_streak := v_current_streak;
            END IF;
            
            UPDATE cardio_streaks
            SET current_streak = v_current_streak,
                longest_streak = v_longest_streak,
                last_activity_date = v_today,
                updated_at = NOW()
            WHERE user_id = NEW.user_id 
              AND streak_type = 'daily_cardio'
              AND activity_type IS NULL;
        ELSE
            -- Streak broken, reset to 1
            UPDATE cardio_streaks
            SET current_streak = 1,
                last_activity_date = v_today,
                streak_start_date = v_today,
                updated_at = NOW()
            WHERE user_id = NEW.user_id 
              AND streak_type = 'daily_cardio'
              AND activity_type IS NULL;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update streak on new workout
DROP TRIGGER IF EXISTS trigger_update_cardio_streak ON cardio_workouts;
CREATE TRIGGER trigger_update_cardio_streak
    AFTER INSERT ON cardio_workouts
    FOR EACH ROW
    EXECUTE FUNCTION update_cardio_streak();

-- ============================================================================
-- HELPER FUNCTION: Update weekly summary
-- ============================================================================
CREATE OR REPLACE FUNCTION update_cardio_weekly_summary()
RETURNS TRIGGER AS $$
DECLARE
    v_week_start DATE;
    v_week_end DATE;
BEGIN
    -- Calculate week boundaries (Monday to Sunday)
    v_week_start := DATE_TRUNC('week', NEW.completed_at)::DATE;
    v_week_end := v_week_start + INTERVAL '6 days';
    
    -- Upsert weekly summary
    INSERT INTO cardio_weekly_summaries (
        user_id, week_start, week_end,
        total_workouts, total_duration_seconds, total_distance_meters, total_calories
    )
    VALUES (
        NEW.user_id, v_week_start, v_week_end,
        1, NEW.duration_seconds, COALESCE(NEW.distance_meters, 0), COALESCE(NEW.calories_burned, 0)
    )
    ON CONFLICT (user_id, week_start) DO UPDATE SET
        total_workouts = cardio_weekly_summaries.total_workouts + 1,
        total_duration_seconds = cardio_weekly_summaries.total_duration_seconds + EXCLUDED.total_duration_seconds,
        total_distance_meters = cardio_weekly_summaries.total_distance_meters + EXCLUDED.total_distance_meters,
        total_calories = cardio_weekly_summaries.total_calories + EXCLUDED.total_calories,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update weekly summary on new workout
DROP TRIGGER IF EXISTS trigger_update_cardio_weekly ON cardio_workouts;
CREATE TRIGGER trigger_update_cardio_weekly
    AFTER INSERT ON cardio_workouts
    FOR EACH ROW
    EXECUTE FUNCTION update_cardio_weekly_summary();

-- ============================================================================
-- VERIFICATION: Check tables were created
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Cardio tables setup complete!';
    RAISE NOTICE 'Tables created: cardio_workouts, cardio_personal_records, cardio_goals, cardio_streaks, cardio_weekly_summaries';
END $$;
