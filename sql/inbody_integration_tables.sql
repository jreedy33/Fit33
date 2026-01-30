-- InBody Integration Tables for Fit33
-- Run this migration to add InBody body composition tracking
-- Based on InBody data integration: https://inbody.com/en/data

-- =====================================================
-- 1. BODY COMPOSITION LOGS TABLE
-- Stores body composition measurements from InBody devices
-- =====================================================
CREATE TABLE IF NOT EXISTS body_composition_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Core Metrics (always present)
    weight_kg DECIMAL(6,2) NOT NULL,
    weight_lbs DECIMAL(6,2) NOT NULL,
    
    -- Body Composition Metrics
    body_fat_percentage DECIMAL(5,2),          -- e.g., 18.5%
    body_fat_mass_kg DECIMAL(6,2),             -- Fat mass in kg
    skeletal_muscle_mass_kg DECIMAL(6,2),      -- SMM in kg
    lean_body_mass_kg DECIMAL(6,2),            -- Lean mass (weight - fat)
    body_water_kg DECIMAL(6,2),                -- Total body water
    
    -- Derived Metrics
    bmi DECIMAL(4,1),                          -- Body Mass Index
    bmr DECIMAL(7,1),                          -- Basal Metabolic Rate (kcal/day)
    visceral_fat_level INT,                    -- 1-20 scale typically
    
    -- Segmental Analysis (optional, advanced InBody devices only)
    -- Left Arm, Right Arm, Trunk, Left Leg, Right Leg
    segmental_lean_left_arm_kg DECIMAL(5,2),
    segmental_lean_right_arm_kg DECIMAL(5,2),
    segmental_lean_trunk_kg DECIMAL(6,2),
    segmental_lean_left_leg_kg DECIMAL(6,2),
    segmental_lean_right_leg_kg DECIMAL(6,2),
    
    segmental_fat_left_arm_kg DECIMAL(5,2),
    segmental_fat_right_arm_kg DECIMAL(5,2),
    segmental_fat_trunk_kg DECIMAL(6,2),
    segmental_fat_left_leg_kg DECIMAL(6,2),
    segmental_fat_right_leg_kg DECIMAL(6,2),
    
    -- Fitness Score (InBody score 0-100)
    inbody_score INT,
    
    -- Metadata
    source TEXT NOT NULL DEFAULT 'inbody',     -- 'inbody', 'manual', 'apple_health'
    device_model TEXT,                          -- e.g., 'InBody Dial H30', 'InBody 270'
    measured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    raw_data JSONB,                             -- Store full InBody response for reference
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_body_fat_percentage CHECK (body_fat_percentage >= 0 AND body_fat_percentage <= 100),
    CONSTRAINT valid_visceral_fat CHECK (visceral_fat_level IS NULL OR (visceral_fat_level >= 1 AND visceral_fat_level <= 30)),
    CONSTRAINT valid_inbody_score CHECK (inbody_score IS NULL OR (inbody_score >= 0 AND inbody_score <= 100))
);

-- Index for efficient user queries
CREATE INDEX IF NOT EXISTS idx_body_composition_user_date 
ON body_composition_logs(user_id, measured_at DESC);

-- Enable RLS
ALTER TABLE body_composition_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own body composition logs"
ON body_composition_logs FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own body composition logs"
ON body_composition_logs FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own body composition logs"
ON body_composition_logs FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own body composition logs"
ON body_composition_logs FOR DELETE
USING (auth.uid() = user_id);


-- =====================================================
-- 2. BODY COMPOSITION GOALS TABLE
-- Stores user's body composition goals (beyond just weight)
-- =====================================================
CREATE TABLE IF NOT EXISTS body_composition_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Weight Goals
    target_weight_kg DECIMAL(6,2),
    target_weight_lbs DECIMAL(6,2),
    
    -- Body Composition Goals
    target_body_fat_percentage DECIMAL(5,2),
    target_muscle_mass_kg DECIMAL(6,2),
    
    -- Goal Type
    primary_goal TEXT NOT NULL DEFAULT 'recomposition', -- 'lose_fat', 'gain_muscle', 'recomposition', 'maintain'
    
    -- Timeline
    target_date DATE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT valid_target_body_fat CHECK (target_body_fat_percentage IS NULL OR (target_body_fat_percentage >= 3 AND target_body_fat_percentage <= 50))
);

-- Enable RLS
ALTER TABLE body_composition_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own body composition goals"
ON body_composition_goals FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own body composition goals"
ON body_composition_goals FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own body composition goals"
ON body_composition_goals FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own body composition goals"
ON body_composition_goals FOR DELETE
USING (auth.uid() = user_id);


-- =====================================================
-- 3. INBODY CONNECTION TABLE
-- Stores OAuth tokens for InBody cloud sync
-- =====================================================
CREATE TABLE IF NOT EXISTS inbody_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- OAuth Tokens (encrypted in practice)
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    
    -- InBody User Info
    inbody_user_id TEXT,
    inbody_email TEXT,
    
    -- Sync Settings
    auto_sync_enabled BOOLEAN NOT NULL DEFAULT true,
    last_sync_at TIMESTAMPTZ,
    sync_frequency_hours INT NOT NULL DEFAULT 24,
    
    -- Connection Status
    is_active BOOLEAN NOT NULL DEFAULT true,
    connection_error TEXT,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE inbody_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own inbody connection"
ON inbody_connections FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own inbody connection"
ON inbody_connections FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own inbody connection"
ON inbody_connections FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own inbody connection"
ON inbody_connections FOR DELETE
USING (auth.uid() = user_id);


-- =====================================================
-- 4. BODY COMPOSITION STATISTICS VIEW
-- Computed statistics for each user
-- =====================================================
CREATE OR REPLACE VIEW body_composition_statistics AS
SELECT 
    user_id,
    
    -- Current values (most recent)
    (SELECT body_fat_percentage FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) as current_body_fat,
     
    (SELECT skeletal_muscle_mass_kg FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) as current_muscle_mass,
     
    (SELECT weight_kg FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) as current_weight,
    
    -- Starting values (first entry)
    (SELECT body_fat_percentage FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at ASC LIMIT 1) as starting_body_fat,
     
    (SELECT skeletal_muscle_mass_kg FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at ASC LIMIT 1) as starting_muscle_mass,
    
    -- Changes
    (SELECT body_fat_percentage FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) -
    (SELECT body_fat_percentage FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at ASC LIMIT 1) as total_body_fat_change,
     
    (SELECT skeletal_muscle_mass_kg FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) -
    (SELECT skeletal_muscle_mass_kg FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at ASC LIMIT 1) as total_muscle_gain,
    
    -- Monthly change (30 days)
    (SELECT body_fat_percentage FROM body_composition_logs bcl2 
     WHERE bcl2.user_id = bcl.user_id 
     ORDER BY measured_at DESC LIMIT 1) -
    COALESCE(
        (SELECT body_fat_percentage FROM body_composition_logs bcl2 
         WHERE bcl2.user_id = bcl.user_id 
         AND measured_at <= NOW() - INTERVAL '30 days'
         ORDER BY measured_at DESC LIMIT 1),
        (SELECT body_fat_percentage FROM body_composition_logs bcl2 
         WHERE bcl2.user_id = bcl.user_id 
         ORDER BY measured_at DESC LIMIT 1)
    ) as monthly_body_fat_change,
    
    -- Best values
    MIN(body_fat_percentage) as lowest_body_fat,
    MAX(skeletal_muscle_mass_kg) as highest_muscle_mass,
    MAX(inbody_score) as best_inbody_score,
    
    -- Averages
    ROUND(AVG(body_fat_percentage)::numeric, 1) as average_body_fat,
    ROUND(AVG(skeletal_muscle_mass_kg)::numeric, 1) as average_muscle_mass,
    
    -- Entry count
    COUNT(*) as total_scans,
    
    -- Last scan date
    MAX(measured_at)::date as last_scan_date
    
FROM body_composition_logs bcl
GROUP BY user_id;


-- =====================================================
-- 5. FUNCTION: Sync Profile from Body Composition
-- Updates user_profiles with latest body composition data
-- =====================================================
CREATE OR REPLACE FUNCTION sync_profile_from_body_composition()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the user's profile with the new weight and BMR
    UPDATE user_profiles
    SET 
        weight_kg = NEW.weight_kg,
        weight_lbs = NEW.weight_lbs,
        bmr = COALESCE(NEW.bmr, bmr),
        updated_at = NOW()
    WHERE id = NEW.user_id::text;
    
    -- Also sync to weight_logs for unified weight tracking
    INSERT INTO weight_logs (user_id, weight_kg, weight_lbs, logged_at, source)
    VALUES (NEW.user_id, NEW.weight_kg, NEW.weight_lbs, NEW.measured_at, 'inbody')
    ON CONFLICT DO NOTHING;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_sync_profile_from_body_composition ON body_composition_logs;
CREATE TRIGGER trigger_sync_profile_from_body_composition
AFTER INSERT ON body_composition_logs
FOR EACH ROW
EXECUTE FUNCTION sync_profile_from_body_composition();


-- =====================================================
-- 6. GRANT PERMISSIONS
-- =====================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON body_composition_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON body_composition_goals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON inbody_connections TO authenticated;
GRANT SELECT ON body_composition_statistics TO authenticated;


-- =====================================================
-- 7. HELPFUL INDEXES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_body_composition_measured_at 
ON body_composition_logs(measured_at DESC);

CREATE INDEX IF NOT EXISTS idx_body_composition_source 
ON body_composition_logs(source);


-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE '✅ InBody integration tables created successfully!';
    RAISE NOTICE 'Tables: body_composition_logs, body_composition_goals, inbody_connections';
    RAISE NOTICE 'View: body_composition_statistics';
    RAISE NOTICE 'Trigger: sync_profile_from_body_composition';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Contact InBody for OAuth API credentials: https://inbody.com/en/data';
    RAISE NOTICE '2. Configure OAuth redirect URI: fit33://inbody/callback';
    RAISE NOTICE '3. Deploy InBodyService.swift and InBodySettingsView.swift';
END $$;
