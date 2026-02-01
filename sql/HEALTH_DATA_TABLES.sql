-- =====================================================
-- HEALTH DATA TABLES
-- Stores aggregated health metrics from Fitbit, Strava, and manual entries
-- =====================================================

-- =====================================================
-- 1. DAILY ACTIVITY SUMMARY
-- Tracks daily steps, calories, active minutes from all sources
-- =====================================================

CREATE TABLE IF NOT EXISTS daily_activity_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    
    -- Steps
    steps INTEGER DEFAULT 0,
    steps_goal INTEGER DEFAULT 10000,
    
    -- Distance (meters)
    distance_meters DOUBLE PRECISION DEFAULT 0,
    
    -- Calories
    calories_burned INTEGER DEFAULT 0,
    calories_bmr INTEGER DEFAULT 0,
    calories_active INTEGER DEFAULT 0,
    
    -- Active Minutes
    sedentary_minutes INTEGER DEFAULT 0,
    lightly_active_minutes INTEGER DEFAULT 0,
    fairly_active_minutes INTEGER DEFAULT 0,
    very_active_minutes INTEGER DEFAULT 0,
    
    -- Floors/Elevation
    floors_climbed INTEGER DEFAULT 0,
    elevation_meters DOUBLE PRECISION DEFAULT 0,
    
    -- Resting Heart Rate (daily average)
    resting_heart_rate INTEGER,
    
    -- Source tracking (which services contributed)
    sources TEXT[] DEFAULT '{}',  -- e.g., ['fitbit', 'strava', 'manual']
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, date)
);

-- Index for fast date range queries
CREATE INDEX IF NOT EXISTS idx_daily_activity_user_date 
ON daily_activity_summary(user_id, date DESC);

-- =====================================================
-- 2. SLEEP LOGS
-- Tracks sleep sessions from Fitbit and manual entries
-- =====================================================

CREATE TABLE IF NOT EXISTS sleep_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Sleep timing
    date_of_sleep DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    
    -- Duration (milliseconds for precision)
    duration_ms BIGINT NOT NULL,
    time_in_bed_ms BIGINT,
    
    -- Sleep quality
    efficiency INTEGER,  -- 0-100 percentage
    minutes_asleep INTEGER,
    minutes_awake INTEGER,
    minutes_to_fall_asleep INTEGER,
    awakenings_count INTEGER,
    
    -- Sleep stages (if available from Fitbit)
    deep_sleep_minutes INTEGER,
    light_sleep_minutes INTEGER,
    rem_sleep_minutes INTEGER,
    wake_minutes INTEGER,
    
    -- Classification
    is_main_sleep BOOLEAN DEFAULT true,
    sleep_type TEXT,  -- 'classic', 'stages', 'manual'
    
    -- Source
    source TEXT NOT NULL DEFAULT 'manual',  -- 'fitbit', 'manual', 'apple_health'
    external_id TEXT,  -- Fitbit log ID
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, source, external_id)
);

-- Index for date range queries
CREATE INDEX IF NOT EXISTS idx_sleep_logs_user_date 
ON sleep_logs(user_id, date_of_sleep DESC);

-- =====================================================
-- 3. HEART RATE LOGS
-- Tracks heart rate data throughout the day
-- =====================================================

CREATE TABLE IF NOT EXISTS heart_rate_daily (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    
    -- Resting heart rate
    resting_heart_rate INTEGER,
    
    -- Heart rate zones (minutes in each zone)
    out_of_range_minutes INTEGER DEFAULT 0,
    fat_burn_minutes INTEGER DEFAULT 0,
    cardio_minutes INTEGER DEFAULT 0,
    peak_minutes INTEGER DEFAULT 0,
    
    -- Zone calorie burn
    out_of_range_calories DOUBLE PRECISION DEFAULT 0,
    fat_burn_calories DOUBLE PRECISION DEFAULT 0,
    cardio_calories DOUBLE PRECISION DEFAULT 0,
    peak_calories DOUBLE PRECISION DEFAULT 0,
    
    -- Zone boundaries (personalized per user)
    out_of_range_max INTEGER,
    fat_burn_min INTEGER,
    fat_burn_max INTEGER,
    cardio_min INTEGER,
    cardio_max INTEGER,
    peak_min INTEGER,
    
    -- Source
    source TEXT NOT NULL DEFAULT 'fitbit',
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, date, source)
);

-- Index for date range queries
CREATE INDEX IF NOT EXISTS idx_heart_rate_user_date 
ON heart_rate_daily(user_id, date DESC);

-- =====================================================
-- 4. WEEKLY/MONTHLY AGGREGATES VIEW
-- Materialized view for fast stats queries
-- =====================================================

CREATE OR REPLACE VIEW weekly_health_stats AS
SELECT 
    user_id,
    DATE_TRUNC('week', date) AS week_start,
    
    -- Steps
    SUM(steps) AS total_steps,
    AVG(steps)::INTEGER AS avg_daily_steps,
    MAX(steps) AS max_steps_day,
    
    -- Calories
    SUM(calories_burned) AS total_calories,
    AVG(calories_burned)::INTEGER AS avg_daily_calories,
    
    -- Active Minutes
    SUM(fairly_active_minutes + very_active_minutes) AS total_active_minutes,
    AVG(fairly_active_minutes + very_active_minutes)::INTEGER AS avg_active_minutes,
    
    -- Distance
    SUM(distance_meters) AS total_distance_meters,
    
    -- Heart Rate
    AVG(resting_heart_rate)::INTEGER AS avg_resting_hr,
    
    -- Days tracked
    COUNT(*) AS days_tracked
    
FROM daily_activity_summary
GROUP BY user_id, DATE_TRUNC('week', date);

-- =====================================================
-- 5. SLEEP AGGREGATES VIEW
-- =====================================================

CREATE OR REPLACE VIEW weekly_sleep_stats AS
SELECT 
    user_id,
    DATE_TRUNC('week', date_of_sleep) AS week_start,
    
    -- Duration
    AVG(duration_ms / 3600000.0) AS avg_sleep_hours,
    MIN(duration_ms / 3600000.0) AS min_sleep_hours,
    MAX(duration_ms / 3600000.0) AS max_sleep_hours,
    
    -- Quality
    AVG(efficiency)::INTEGER AS avg_efficiency,
    
    -- Stages (if available)
    AVG(deep_sleep_minutes)::INTEGER AS avg_deep_sleep,
    AVG(rem_sleep_minutes)::INTEGER AS avg_rem_sleep,
    AVG(light_sleep_minutes)::INTEGER AS avg_light_sleep,
    
    -- Nights tracked
    COUNT(*) AS nights_tracked
    
FROM sleep_logs
WHERE is_main_sleep = true
GROUP BY user_id, DATE_TRUNC('week', date_of_sleep);

-- =====================================================
-- 6. ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE daily_activity_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE heart_rate_daily ENABLE ROW LEVEL SECURITY;

-- Users can only see their own data
CREATE POLICY "Users can view own activity data" ON daily_activity_summary
    FOR SELECT USING (auth.uid() = user_id);
    
CREATE POLICY "Users can insert own activity data" ON daily_activity_summary
    FOR INSERT WITH CHECK (auth.uid() = user_id);
    
CREATE POLICY "Users can update own activity data" ON daily_activity_summary
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own sleep data" ON sleep_logs
    FOR SELECT USING (auth.uid() = user_id);
    
CREATE POLICY "Users can insert own sleep data" ON sleep_logs
    FOR INSERT WITH CHECK (auth.uid() = user_id);
    
CREATE POLICY "Users can update own sleep data" ON sleep_logs
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own heart rate data" ON heart_rate_daily
    FOR SELECT USING (auth.uid() = user_id);
    
CREATE POLICY "Users can insert own heart rate data" ON heart_rate_daily
    FOR INSERT WITH CHECK (auth.uid() = user_id);
    
CREATE POLICY "Users can update own heart rate data" ON heart_rate_daily
    FOR UPDATE USING (auth.uid() = user_id);

-- =====================================================
-- 7. HELPER FUNCTIONS
-- =====================================================

-- Function to upsert daily activity summary
CREATE OR REPLACE FUNCTION upsert_daily_activity(
    p_user_id UUID,
    p_date DATE,
    p_steps INTEGER DEFAULT NULL,
    p_distance_meters DOUBLE PRECISION DEFAULT NULL,
    p_calories_burned INTEGER DEFAULT NULL,
    p_calories_active INTEGER DEFAULT NULL,
    p_sedentary_minutes INTEGER DEFAULT NULL,
    p_lightly_active_minutes INTEGER DEFAULT NULL,
    p_fairly_active_minutes INTEGER DEFAULT NULL,
    p_very_active_minutes INTEGER DEFAULT NULL,
    p_floors_climbed INTEGER DEFAULT NULL,
    p_resting_heart_rate INTEGER DEFAULT NULL,
    p_source TEXT DEFAULT 'manual'
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_sources TEXT[];
BEGIN
    -- Get existing sources
    SELECT sources INTO v_sources 
    FROM daily_activity_summary 
    WHERE user_id = p_user_id AND date = p_date;
    
    -- Add new source if not already present
    IF v_sources IS NULL THEN
        v_sources := ARRAY[p_source];
    ELSIF NOT (p_source = ANY(v_sources)) THEN
        v_sources := array_append(v_sources, p_source);
    END IF;
    
    INSERT INTO daily_activity_summary (
        user_id, date, steps, distance_meters, calories_burned, calories_active,
        sedentary_minutes, lightly_active_minutes, fairly_active_minutes, 
        very_active_minutes, floors_climbed, resting_heart_rate, sources, updated_at
    ) VALUES (
        p_user_id, p_date, 
        COALESCE(p_steps, 0), COALESCE(p_distance_meters, 0),
        COALESCE(p_calories_burned, 0), COALESCE(p_calories_active, 0),
        COALESCE(p_sedentary_minutes, 0), COALESCE(p_lightly_active_minutes, 0),
        COALESCE(p_fairly_active_minutes, 0), COALESCE(p_very_active_minutes, 0),
        COALESCE(p_floors_climbed, 0), p_resting_heart_rate, v_sources, NOW()
    )
    ON CONFLICT (user_id, date) DO UPDATE SET
        steps = GREATEST(daily_activity_summary.steps, COALESCE(p_steps, daily_activity_summary.steps)),
        distance_meters = GREATEST(daily_activity_summary.distance_meters, COALESCE(p_distance_meters, daily_activity_summary.distance_meters)),
        calories_burned = GREATEST(daily_activity_summary.calories_burned, COALESCE(p_calories_burned, daily_activity_summary.calories_burned)),
        calories_active = GREATEST(daily_activity_summary.calories_active, COALESCE(p_calories_active, daily_activity_summary.calories_active)),
        sedentary_minutes = COALESCE(p_sedentary_minutes, daily_activity_summary.sedentary_minutes),
        lightly_active_minutes = COALESCE(p_lightly_active_minutes, daily_activity_summary.lightly_active_minutes),
        fairly_active_minutes = COALESCE(p_fairly_active_minutes, daily_activity_summary.fairly_active_minutes),
        very_active_minutes = COALESCE(p_very_active_minutes, daily_activity_summary.very_active_minutes),
        floors_climbed = GREATEST(daily_activity_summary.floors_climbed, COALESCE(p_floors_climbed, daily_activity_summary.floors_climbed)),
        resting_heart_rate = COALESCE(p_resting_heart_rate, daily_activity_summary.resting_heart_rate),
        sources = v_sources,
        updated_at = NOW()
    RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION upsert_daily_activity TO authenticated;

-- =====================================================
-- Done! Run this in Supabase SQL Editor
-- =====================================================
