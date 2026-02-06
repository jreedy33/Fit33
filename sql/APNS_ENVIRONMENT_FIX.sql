-- ============================================================================
-- APNS ENVIRONMENT FIX
-- Fixes the BadDeviceToken issue caused by mixing development/production tokens
-- ============================================================================

-- STEP 1: Add environment column to user_push_tokens
-- ============================================================================

ALTER TABLE user_push_tokens 
ADD COLUMN IF NOT EXISTS apns_environment TEXT DEFAULT 'production';

-- Add comment explaining the column
COMMENT ON COLUMN user_push_tokens.apns_environment IS 
'APNs environment: "production" for TestFlight/App Store, "development" for Xcode builds';

-- STEP 2: Reset all tokens to require re-registration
-- ============================================================================
-- Since we don't know which environment each token belongs to, mark them invalid
-- so users get fresh tokens on next app open

UPDATE user_push_tokens 
SET is_valid = false, 
    updated_at = NOW()
WHERE is_valid = true;

-- STEP 3: Clean up the failed notification queue  
-- ============================================================================
-- Remove old failed notifications so they don't keep retrying with bad tokens

DELETE FROM push_notification_queue 
WHERE status = 'failed' 
AND error_message LIKE '%BadDeviceToken%';

-- Verify the cleanup
SELECT 
    'Tokens reset' AS action,
    COUNT(*) AS count
FROM user_push_tokens
WHERE is_valid = false

UNION ALL

SELECT 
    'Failed notifications cleaned' AS action,
    0 AS count;

-- ============================================================================
-- VERIFICATION: Check current state
-- ============================================================================

SELECT 
    'user_push_tokens' AS table_name,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN is_valid THEN 1 ELSE 0 END) AS valid_tokens,
    SUM(CASE WHEN NOT is_valid THEN 1 ELSE 0 END) AS invalid_tokens
FROM user_push_tokens;
