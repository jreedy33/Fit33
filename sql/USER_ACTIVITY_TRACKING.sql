-- =====================================================
-- USER ACTIVITY & INTEGRATION TRACKING
-- Tracks last login time and connected integrations
-- =====================================================

-- Add last login tracking column
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ DEFAULT NOW();

-- Add integration connection status columns
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS is_strava_connected BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS is_fitbit_connected BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS is_apple_health_connected BOOLEAN DEFAULT FALSE;

ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS is_inbody_connected BOOLEAN DEFAULT FALSE;

-- Create index on last_login_at for analytics queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_last_login 
ON user_profiles(last_login_at DESC);

-- Create a composite index for integration analytics
CREATE INDEX IF NOT EXISTS idx_user_profiles_integrations 
ON user_profiles(is_strava_connected, is_fitbit_connected, is_apple_health_connected, is_inbody_connected);

-- Add comments for documentation
COMMENT ON COLUMN user_profiles.last_login_at IS 'Timestamp of the most recent app open/login';
COMMENT ON COLUMN user_profiles.is_strava_connected IS 'Whether user has connected their Strava account';
COMMENT ON COLUMN user_profiles.is_fitbit_connected IS 'Whether user has connected their Fitbit account';
COMMENT ON COLUMN user_profiles.is_apple_health_connected IS 'Whether user has enabled Apple Health sync';
COMMENT ON COLUMN user_profiles.is_inbody_connected IS 'Whether user has connected their InBody account';

-- =====================================================
-- FUNCTION: Update last login timestamp
-- Called when user opens the app
-- =====================================================
CREATE OR REPLACE FUNCTION update_last_login(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE user_profiles 
    SET last_login_at = NOW()
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- FUNCTION: Update integration status
-- Called when user connects/disconnects an integration
-- =====================================================
CREATE OR REPLACE FUNCTION update_integration_status(
    p_user_id UUID,
    p_integration TEXT,
    p_is_connected BOOLEAN
)
RETURNS VOID AS $$
BEGIN
    CASE p_integration
        WHEN 'strava' THEN
            UPDATE user_profiles 
            SET is_strava_connected = p_is_connected
            WHERE id = p_user_id;
        WHEN 'fitbit' THEN
            UPDATE user_profiles 
            SET is_fitbit_connected = p_is_connected
            WHERE id = p_user_id;
        WHEN 'apple_health' THEN
            UPDATE user_profiles 
            SET is_apple_health_connected = p_is_connected
            WHERE id = p_user_id;
        WHEN 'inbody' THEN
            UPDATE user_profiles 
            SET is_inbody_connected = p_is_connected
            WHERE id = p_user_id;
        ELSE
            RAISE EXCEPTION 'Unknown integration: %', p_integration;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- ANALYTICS VIEW: Active users and integration stats
-- =====================================================
CREATE OR REPLACE VIEW user_activity_stats AS
SELECT 
    COUNT(*) AS total_users,
    COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '1 day') AS daily_active_users,
    COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '7 days') AS weekly_active_users,
    COUNT(*) FILTER (WHERE last_login_at > NOW() - INTERVAL '30 days') AS monthly_active_users,
    COUNT(*) FILTER (WHERE is_strava_connected = TRUE) AS strava_connected_count,
    COUNT(*) FILTER (WHERE is_fitbit_connected = TRUE) AS fitbit_connected_count,
    COUNT(*) FILTER (WHERE is_apple_health_connected = TRUE) AS apple_health_connected_count,
    COUNT(*) FILTER (WHERE is_inbody_connected = TRUE) AS inbody_connected_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_strava_connected = TRUE) / NULLIF(COUNT(*), 0), 2) AS strava_adoption_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_fitbit_connected = TRUE) / NULLIF(COUNT(*), 0), 2) AS fitbit_adoption_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_apple_health_connected = TRUE) / NULLIF(COUNT(*), 0), 2) AS apple_health_adoption_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_inbody_connected = TRUE) / NULLIF(COUNT(*), 0), 2) AS inbody_adoption_pct
FROM user_profiles;

-- Grant permissions
GRANT EXECUTE ON FUNCTION update_last_login(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_integration_status(UUID, TEXT, BOOLEAN) TO authenticated;

-- =====================================================
-- VERIFICATION: Check that columns were added
-- =====================================================
SELECT column_name, data_type, column_default
FROM information_schema.columns 
WHERE table_name = 'user_profiles' 
AND column_name IN ('last_login_at', 'is_strava_connected', 'is_fitbit_connected', 'is_apple_health_connected', 'is_inbody_connected')
ORDER BY column_name;
