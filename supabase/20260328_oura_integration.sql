-- Oura Ring Integration Schema
-- Creates oura_readiness_data table, adds is_oura_connected to user_profiles.
-- Sleep data reuses existing sleep_logs table (source: 'oura') with columns added by WHOOP migration.

BEGIN;

-- 1. Add Oura connection flag to user_profiles
ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS is_oura_connected BOOLEAN DEFAULT false;

-- 2. Create oura_readiness_data table (readiness + activity + sleep scores in one row per day)
CREATE TABLE IF NOT EXISTS oura_readiness_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    -- Readiness metrics
    readiness_score INTEGER,
    temperature_deviation DOUBLE PRECISION,
    temperature_trend_deviation DOUBLE PRECISION,
    hrv_balance INTEGER,
    resting_heart_rate INTEGER,
    -- Activity metrics
    activity_score INTEGER,
    steps INTEGER,
    active_calories INTEGER,
    total_calories INTEGER,
    equivalent_walking_distance INTEGER,
    -- Sleep score (from daily_sleep summary)
    sleep_score INTEGER,
    -- SpO2
    spo2_percentage DOUBLE PRECISION,
    breathing_disturbance_index DOUBLE PRECISION,
    -- Stress
    stress_high INTEGER,
    recovery_high INTEGER,
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_oura_readiness_user_id ON oura_readiness_data(user_id);
CREATE INDEX IF NOT EXISTS idx_oura_readiness_date ON oura_readiness_data(user_id, date DESC);

ALTER TABLE oura_readiness_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own oura readiness"
    ON oura_readiness_data FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own oura readiness"
    ON oura_readiness_data FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own oura readiness"
    ON oura_readiness_data FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own oura readiness"
    ON oura_readiness_data FOR DELETE USING (auth.uid() = user_id);

COMMIT;
