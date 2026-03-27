-- WHOOP Integration Schema
-- Creates whoop_recovery_data table, enhances sleep_logs with WHOOP-specific columns,
-- adds is_whoop_connected to user_profiles.

BEGIN;

-- 1. Add WHOOP connection flag to user_profiles
ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS is_whoop_connected BOOLEAN DEFAULT false;

-- 2. Create whoop_recovery_data table (recovery + strain in one row per day)
CREATE TABLE IF NOT EXISTS whoop_recovery_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    cycle_id BIGINT,
    -- Recovery metrics
    recovery_score INTEGER,
    hrv_rmssd_milli DOUBLE PRECISION,
    resting_heart_rate INTEGER,
    spo2_percentage DOUBLE PRECISION,
    skin_temp_celsius DOUBLE PRECISION,
    -- Strain metrics (from the same day's cycle)
    strain DOUBLE PRECISION,
    kilojoules DOUBLE PRECISION,
    avg_heart_rate INTEGER,
    max_heart_rate INTEGER,
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, date)
);

CREATE INDEX IF NOT EXISTS idx_whoop_recovery_user_id ON whoop_recovery_data(user_id);
CREATE INDEX IF NOT EXISTS idx_whoop_recovery_date ON whoop_recovery_data(user_id, date DESC);

ALTER TABLE whoop_recovery_data ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own whoop recovery"
    ON whoop_recovery_data FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own whoop recovery"
    ON whoop_recovery_data FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own whoop recovery"
    ON whoop_recovery_data FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own whoop recovery"
    ON whoop_recovery_data FOR DELETE USING (auth.uid() = user_id);

-- 3. Enhance sleep_logs with WHOOP-specific columns (nullable, no impact on existing rows)
ALTER TABLE sleep_logs
    ADD COLUMN IF NOT EXISTS sleep_performance_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS sleep_consistency_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS sleep_efficiency_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS respiratory_rate DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS disturbance_count INTEGER,
    ADD COLUMN IF NOT EXISTS sleep_debt_milli BIGINT,
    ADD COLUMN IF NOT EXISTS light_sleep_milli BIGINT,
    ADD COLUMN IF NOT EXISTS deep_sleep_milli BIGINT,
    ADD COLUMN IF NOT EXISTS rem_sleep_milli BIGINT,
    ADD COLUMN IF NOT EXISTS awake_milli BIGINT;

-- 4. Add whoop_recovery_data to delete_user_account() cleanup
-- (The CASCADE on user_id FK handles this automatically, but documenting intent)

COMMIT;
