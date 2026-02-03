-- ============================================================================
-- ONBOARDING LOGS TABLE
-- Tracks all onboarding events for debugging user registration issues
-- Specifically designed to track WHY fields might not save to the database
-- Created: 2026-02-02
-- ============================================================================

-- Drop existing objects (CASCADE to handle dependencies)
DROP VIEW IF EXISTS v_onboarding_problems CASCADE;
DROP VIEW IF EXISTS v_field_comparison CASCADE;
DROP VIEW IF EXISTS v_onboarding_summary CASCADE;
DROP VIEW IF EXISTS v_onboarding_issues CASCADE;
DROP TABLE IF EXISTS onboarding_field_logs CASCADE;
DROP TABLE IF EXISTS onboarding_logs CASCADE;

-- Create the onboarding logs table
CREATE TABLE onboarding_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT, -- To group logs from the same onboarding session
    event_type TEXT NOT NULL, -- 'step_started', 'step_completed', 'data_saved', 'error', 'profile_created', etc.
    step_name TEXT, -- Which onboarding step (e.g., 'name', 'age', 'goals', etc.)
    event_data JSONB, -- Any relevant data for this event
    error_message TEXT, -- If this is an error event
    device_info JSONB, -- Device model, OS version, app version, locale, timezone
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Indexes for efficient querying
    CONSTRAINT valid_event_type CHECK (event_type IN (
        'session_started',
        'step_started', 
        'step_completed',
        'step_skipped',
        'data_validation_failed',
        'profile_create_started',
        'profile_create_success',
        'profile_create_error',
        'profile_update_started',
        'profile_update_success',
        'profile_update_error',
        'onboarding_completed',
        'onboarding_abandoned',
        'error'
    ))
);

-- Create indexes for efficient querying
CREATE INDEX idx_onboarding_logs_user_id ON onboarding_logs(user_id);
CREATE INDEX idx_onboarding_logs_session_id ON onboarding_logs(session_id);
CREATE INDEX idx_onboarding_logs_event_type ON onboarding_logs(event_type);
CREATE INDEX idx_onboarding_logs_created_at ON onboarding_logs(created_at DESC);

-- Enable RLS
ALTER TABLE onboarding_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Users can insert their own logs
CREATE POLICY "Users can insert their own onboarding logs"
ON onboarding_logs FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can view their own logs
CREATE POLICY "Users can view their own onboarding logs"
ON onboarding_logs FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Policy: Allow anonymous inserts (for pre-auth logging)
CREATE POLICY "Allow anonymous onboarding logs"
ON onboarding_logs FOR INSERT
TO anon
WITH CHECK (user_id IS NULL);

-- Create a function to log onboarding events (can be called via RPC)
CREATE OR REPLACE FUNCTION log_onboarding_event(
    p_user_id UUID DEFAULT NULL,
    p_session_id TEXT DEFAULT NULL,
    p_event_type TEXT DEFAULT 'error',
    p_step_name TEXT DEFAULT NULL,
    p_event_data JSONB DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_device_info JSONB DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER -- Bypass RLS to always allow logging
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO onboarding_logs (
        user_id,
        session_id,
        event_type,
        step_name,
        event_data,
        error_message,
        device_info
    ) VALUES (
        COALESCE(p_user_id, auth.uid()),
        p_session_id,
        p_event_type,
        p_step_name,
        p_event_data,
        p_error_message,
        p_device_info
    )
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION log_onboarding_event TO authenticated;
GRANT EXECUTE ON FUNCTION log_onboarding_event TO anon;

-- Create a view for easy querying of recent onboarding issues
CREATE OR REPLACE VIEW v_onboarding_issues AS
SELECT 
    ol.id,
    ol.user_id,
    up.email,
    up.name as user_name,
    ol.session_id,
    ol.event_type,
    ol.step_name,
    ol.event_data,
    ol.error_message,
    ol.device_info->>'device_model' as device_model,
    ol.device_info->>'os_version' as os_version,
    ol.device_info->>'app_version' as app_version,
    ol.device_info->>'locale' as locale,
    ol.device_info->>'timezone' as timezone,
    ol.created_at
FROM onboarding_logs ol
LEFT JOIN user_profiles up ON ol.user_id = up.id
ORDER BY ol.created_at DESC;

-- Grant access to the view (for admin queries)
GRANT SELECT ON v_onboarding_issues TO authenticated;

-- Create a summary view for debugging
CREATE OR REPLACE VIEW v_onboarding_summary AS
SELECT 
    session_id,
    user_id,
    MIN(created_at) as started_at,
    MAX(created_at) as last_activity,
    COUNT(*) as total_events,
    COUNT(*) FILTER (WHERE event_type = 'error') as error_count,
    COUNT(*) FILTER (WHERE event_type = 'profile_create_error') as profile_errors,
    BOOL_OR(event_type = 'onboarding_completed') as completed,
    ARRAY_AGG(DISTINCT step_name) FILTER (WHERE step_name IS NOT NULL) as steps_visited,
    MAX(device_info->>'locale') as locale,
    MAX(device_info->>'timezone') as timezone
FROM onboarding_logs
GROUP BY session_id, user_id
ORDER BY started_at DESC;

GRANT SELECT ON v_onboarding_summary TO authenticated;

-- ============================================================================
-- HELPFUL QUERIES FOR DEBUGGING
-- ============================================================================

-- View all logs for a specific user (replace with actual user ID):
-- SELECT * FROM onboarding_logs WHERE user_id = 'USER_UUID_HERE' ORDER BY created_at;

-- View all errors in the last 24 hours:
-- SELECT * FROM v_onboarding_issues WHERE event_type LIKE '%error%' AND created_at > NOW() - INTERVAL '24 hours';

-- View incomplete onboarding sessions:
-- SELECT * FROM v_onboarding_summary WHERE NOT completed AND started_at > NOW() - INTERVAL '7 days';

-- View logs by timezone (useful for finding UK users):
-- SELECT * FROM v_onboarding_issues WHERE timezone LIKE '%London%' OR locale LIKE '%GB%' ORDER BY created_at DESC;

COMMENT ON TABLE onboarding_logs IS 'Tracks all onboarding events for debugging user registration issues';

-- ============================================================================
-- FIELD-LEVEL LOGGING TABLE
-- Tracks individual field values at each stage: collected → sent → saved
-- ============================================================================

CREATE TABLE onboarding_field_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT,
    field_name TEXT NOT NULL, -- 'birthday', 'weight', 'height', 'goals', etc.
    stage TEXT NOT NULL, -- 'collected', 'sent_to_db', 'verified_in_db'
    field_value TEXT, -- The actual value (as string for comparison)
    field_type TEXT, -- 'string', 'number', 'array', 'null'
    is_null BOOLEAN DEFAULT FALSE,
    is_empty BOOLEAN DEFAULT FALSE,
    raw_input TEXT, -- What the user actually typed/selected
    converted_value TEXT, -- After any conversions (e.g., lbs to kg)
    device_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_field_logs_user_id ON onboarding_field_logs(user_id);
CREATE INDEX idx_field_logs_session_id ON onboarding_field_logs(session_id);
CREATE INDEX idx_field_logs_field_name ON onboarding_field_logs(field_name);
CREATE INDEX idx_field_logs_created_at ON onboarding_field_logs(created_at DESC);

-- Enable RLS
ALTER TABLE onboarding_field_logs ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can insert their own field logs"
ON onboarding_field_logs FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own field logs"
ON onboarding_field_logs FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Allow anonymous field logs"
ON onboarding_field_logs FOR INSERT
TO anon
WITH CHECK (user_id IS NULL);

-- Function to log individual fields
CREATE OR REPLACE FUNCTION log_onboarding_field(
    p_user_id UUID DEFAULT NULL,
    p_session_id TEXT DEFAULT NULL,
    p_field_name TEXT DEFAULT NULL,
    p_stage TEXT DEFAULT 'collected',
    p_field_value TEXT DEFAULT NULL,
    p_field_type TEXT DEFAULT 'string',
    p_raw_input TEXT DEFAULT NULL,
    p_converted_value TEXT DEFAULT NULL,
    p_device_info JSONB DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_log_id UUID;
    v_is_null BOOLEAN;
    v_is_empty BOOLEAN;
BEGIN
    v_is_null := p_field_value IS NULL;
    v_is_empty := p_field_value IS NOT NULL AND TRIM(p_field_value) = '';
    
    INSERT INTO onboarding_field_logs (
        user_id,
        session_id,
        field_name,
        stage,
        field_value,
        field_type,
        is_null,
        is_empty,
        raw_input,
        converted_value,
        device_info
    ) VALUES (
        COALESCE(p_user_id, auth.uid()),
        p_session_id,
        p_field_name,
        p_stage,
        p_field_value,
        p_field_type,
        v_is_null,
        v_is_empty,
        p_raw_input,
        p_converted_value,
        p_device_info
    )
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;

GRANT EXECUTE ON FUNCTION log_onboarding_field TO authenticated;
GRANT EXECUTE ON FUNCTION log_onboarding_field TO anon;

-- ============================================================================
-- VIEW: Compare what was collected vs what's in the database
-- ============================================================================

CREATE OR REPLACE VIEW v_field_comparison AS
WITH collected AS (
    SELECT 
        user_id,
        session_id,
        field_name,
        field_value as collected_value,
        raw_input,
        converted_value,
        is_null as collected_is_null,
        is_empty as collected_is_empty,
        created_at as collected_at
    FROM onboarding_field_logs
    WHERE stage = 'collected'
),
sent AS (
    SELECT 
        user_id,
        session_id,
        field_name,
        field_value as sent_value,
        is_null as sent_is_null,
        created_at as sent_at
    FROM onboarding_field_logs
    WHERE stage = 'sent_to_db'
),
verified AS (
    SELECT 
        user_id,
        session_id,
        field_name,
        field_value as db_value,
        is_null as db_is_null,
        created_at as verified_at
    FROM onboarding_field_logs
    WHERE stage = 'verified_in_db'
)
SELECT 
    COALESCE(c.user_id, s.user_id, v.user_id) as user_id,
    COALESCE(c.session_id, s.session_id, v.session_id) as session_id,
    COALESCE(c.field_name, s.field_name, v.field_name) as field_name,
    c.raw_input,
    c.collected_value,
    c.converted_value,
    s.sent_value,
    v.db_value,
    -- Flag mismatches
    CASE 
        WHEN c.collected_value IS NOT NULL AND v.db_value IS NULL THEN 'DATA_LOST'
        WHEN c.collected_value != v.db_value THEN 'VALUE_MISMATCH'
        WHEN c.collected_value IS NULL AND v.db_value IS NULL THEN 'BOTH_NULL'
        ELSE 'OK'
    END as status,
    c.collected_at,
    s.sent_at,
    v.verified_at
FROM collected c
FULL OUTER JOIN sent s ON c.user_id = s.user_id AND c.session_id = s.session_id AND c.field_name = s.field_name
FULL OUTER JOIN verified v ON COALESCE(c.user_id, s.user_id) = v.user_id 
    AND COALESCE(c.session_id, s.session_id) = v.session_id 
    AND COALESCE(c.field_name, s.field_name) = v.field_name
ORDER BY COALESCE(c.collected_at, s.sent_at, v.verified_at) DESC;

GRANT SELECT ON v_field_comparison TO authenticated;

-- ============================================================================
-- VIEW: Quick diagnosis - shows fields that didn't save correctly
-- ============================================================================

CREATE OR REPLACE VIEW v_onboarding_problems AS
SELECT 
    user_id,
    session_id,
    field_name,
    raw_input,
    collected_value,
    sent_value,
    db_value,
    status,
    collected_at
FROM v_field_comparison
WHERE status IN ('DATA_LOST', 'VALUE_MISMATCH')
ORDER BY collected_at DESC;

GRANT SELECT ON v_onboarding_problems TO authenticated;

-- ============================================================================
-- HELPFUL QUERIES FOR YOUR UK FRIEND'S ISSUE
-- ============================================================================

-- 1. See what fields were collected but are NULL in the database:
-- SELECT * FROM v_onboarding_problems WHERE user_id = 'USER_UUID_HERE';

-- 2. See the full journey of a specific field (e.g., 'weight'):
-- SELECT * FROM onboarding_field_logs WHERE field_name = 'weight' ORDER BY created_at DESC LIMIT 10;

-- 3. Compare all fields for a user:
-- SELECT * FROM v_field_comparison WHERE user_id = 'USER_UUID_HERE' ORDER BY field_name;

-- 4. Find users where data was lost:
-- SELECT DISTINCT user_id, session_id, COUNT(*) as lost_fields
-- FROM v_onboarding_problems
-- WHERE status = 'DATA_LOST'
-- GROUP BY user_id, session_id
-- ORDER BY lost_fields DESC;
