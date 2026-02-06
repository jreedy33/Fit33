-- =====================================================
-- REALTIME AND NOTIFICATIONS FIX
-- Fit33 App - February 2026
-- =====================================================
-- This script:
-- 1. Adds retry logic columns to push_notification_queue
-- 2. Creates optimized indexes
-- 3. Creates notification cleanup function
-- 4. Creates notification health monitoring view
-- =====================================================

-- =====================================================
-- STEP 1: Add retry columns to push_notification_queue
-- =====================================================

-- Add retry_count column if it doesn't exist
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS retry_count INTEGER DEFAULT 0;

-- Add last_attempt_at column if it doesn't exist
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

-- Add next_retry_at column for exponential backoff
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

-- Add error_message column if it doesn't exist
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS error_message TEXT;

-- =====================================================
-- STEP 2: Create optimized indexes
-- =====================================================

-- Index for pending notifications processing
CREATE INDEX IF NOT EXISTS idx_push_queue_pending_retry
ON push_notification_queue(status, next_retry_at, created_at)
WHERE status = 'pending';

-- Index for recipient user lookups
CREATE INDEX IF NOT EXISTS idx_push_queue_recipient
ON push_notification_queue(recipient_user_id, status);

-- Index for cleanup queries (old sent/failed notifications)
CREATE INDEX IF NOT EXISTS idx_push_queue_cleanup
ON push_notification_queue(status, created_at)
WHERE status IN ('sent', 'failed');

-- Friendships indexes
CREATE INDEX IF NOT EXISTS idx_friendships_addressee_pending 
ON friendships(addressee_id, status) 
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_friendships_requester_pending 
ON friendships(requester_id, status) 
WHERE status = 'pending';

-- Challenge indexes
CREATE INDEX IF NOT EXISTS idx_challenge_participants_user_pending
ON challenge_participants(user_id, status) 
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_challenge_participants_user_accepted
ON challenge_participants(user_id, status) 
WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_friend_challenges_status_dates
ON friend_challenges(status, start_date, end_date);

-- Shared workouts index
CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient_pending
ON shared_workouts(recipient_id, status) 
WHERE status = 'pending';

-- =====================================================
-- STEP 3: Create notification cleanup function
-- =====================================================

CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS TABLE(sent_deleted INTEGER, failed_deleted INTEGER) AS $$
DECLARE
    v_sent_deleted INTEGER;
    v_failed_deleted INTEGER;
BEGIN
    -- Delete sent notifications older than 7 days
    DELETE FROM push_notification_queue
    WHERE status = 'sent'
    AND created_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS v_sent_deleted = ROW_COUNT;
    
    -- Delete failed notifications older than 30 days
    DELETE FROM push_notification_queue
    WHERE status = 'failed'
    AND created_at < NOW() - INTERVAL '30 days';
    
    GET DIAGNOSTICS v_failed_deleted = ROW_COUNT;
    
    RAISE NOTICE 'Cleanup complete: % sent deleted, % failed deleted', 
        v_sent_deleted, v_failed_deleted;
    
    RETURN QUERY SELECT v_sent_deleted, v_failed_deleted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cleanup_old_notifications() TO service_role;

-- =====================================================
-- STEP 4: Create notification health monitoring view
-- =====================================================

CREATE OR REPLACE VIEW notification_health_stats AS
SELECT 
    status,
    COUNT(*) as count,
    AVG(retry_count)::NUMERIC(3,1) as avg_retries,
    MIN(created_at) as oldest,
    MAX(created_at) as newest
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY status
ORDER BY 
    CASE status 
        WHEN 'pending' THEN 1 
        WHEN 'sent' THEN 2 
        WHEN 'failed' THEN 3 
    END;

-- =====================================================
-- STEP 5: Add is_valid column to user_push_tokens
-- =====================================================

ALTER TABLE user_push_tokens 
ADD COLUMN IF NOT EXISTS is_valid BOOLEAN DEFAULT true;

-- Index for valid tokens
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_valid
ON user_push_tokens(user_id, is_valid)
WHERE is_valid = true;

-- =====================================================
-- VERIFICATION
-- =====================================================

-- Show all new columns
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'push_notification_queue'
AND column_name IN ('retry_count', 'last_attempt_at', 'next_retry_at', 'error_message')
ORDER BY column_name;

-- Show all new indexes
SELECT indexname, tablename
FROM pg_indexes
WHERE schemaname = 'public'
AND (
    indexname LIKE 'idx_push_%' 
    OR indexname LIKE 'idx_friendships_%'
    OR indexname LIKE 'idx_challenge_%'
    OR indexname LIKE 'idx_shared_workouts_%'
)
ORDER BY tablename, indexname;

-- Show notification health
SELECT * FROM notification_health_stats;

SELECT '✅ Realtime and notifications fix applied successfully!' AS status;
