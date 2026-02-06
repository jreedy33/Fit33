-- =====================================================
-- INFRASTRUCTURE AUDIT & FIXES - February 2026
-- Senior Engineering Analysis & Recommendations
-- =====================================================
-- 
-- SUMMARY OF FINDINGS:
-- ✅ WORKING WELL: Exercise queries, friend requests, received workouts, step tracking
-- ⚠️ NEEDS IMPROVEMENT: Push notification delivery, query performance, missing indexes
-- 🔴 CRITICAL: Notification queue not processing reliably, no cron jobs for challenges
--
-- =====================================================

-- =====================================================
-- SECTION 1: PERFORMANCE METRICS FROM LOGS
-- =====================================================
/*
TOP QUERIES BY EXECUTION TIME (from pg_stat_statements):

1. mv_public_exercises (materialized view)
   - Calls: 14,984 | Avg: 50ms | Max: 872ms | Total: 749s
   - Cache hit rate: 99.99% (8,079,534 hits vs 830 reads)
   - VERDICT: Good cache, but high variance suggests occasional full scans

2. exercises table (is_custom filter)
   - Calls: 6,817 | Avg: 45ms | Max: 938ms | Total: 307s
   - VERDICT: Needs index optimization

3. exercises table (video_filename NOT NULL)
   - Calls: 7,973 | Avg: 41ms | Max: 952ms | Total: 334s
   - VERDICT: Needs partial index on video_filename

4. step_tracking INSERT (with upsert)
   - Calls: 13,952 | Avg: 6.4ms | Max: 387ms | Total: 89s
   - VERDICT: Working well, good upsert pattern

5. get_received_workouts()
   - Calls: 4,660 | Avg: 9.2ms | Max: 562ms | Total: 42s
   - VERDICT: Good performance, working correctly

6. get_pending_friend_requests()
   - Calls: 3,328 | Avg: 10ms | Max: 499ms | Total: 33s
   - VERDICT: Good performance, working correctly

7. pg_timezone_names (INTERNAL)
   - Calls: 292 | Avg: 589ms | Max: 2,618ms | Total: 172s
   - VERDICT: Internal Supabase query, expected overhead
*/

-- =====================================================
-- SECTION 2: INDEX OPTIMIZATIONS
-- =====================================================

-- 2.1: Exercise table indexes for common query patterns
-- These patterns appear frequently in logs

-- Index for is_custom = false queries (public exercises)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_exercises_is_custom_false 
ON exercises(name, id) WHERE is_custom = false;

-- Partial index for exercises with video files
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_exercises_with_video 
ON exercises(name, video_filename, video_code, gender) 
WHERE video_filename IS NOT NULL;

-- Index for video_code lookups (used by video player)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_exercises_video_code 
ON exercises(video_code) WHERE video_code IS NOT NULL;

-- 2.2: Shared workouts indexes for faster inbox queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shared_workouts_recipient_status 
ON shared_workouts(recipient_id, status, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_shared_workouts_sender_created 
ON shared_workouts(sender_id, created_at DESC);

-- 2.3: Friendships indexes for faster friend lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_friendships_requester_status 
ON friendships(requester_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_friendships_addressee_status 
ON friendships(addressee_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_friendships_accepted_both 
ON friendships(requester_id, addressee_id) WHERE status = 'accepted';

-- 2.4: Challenge tables indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_challenge_participants_user_status 
ON challenge_participants(user_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_challenge_daily_progress_user_date 
ON challenge_daily_progress(user_id, progress_date DESC);

-- 2.5: Push notification queue indexes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_push_queue_pending_created 
ON push_notification_queue(created_at ASC) WHERE status = 'pending';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_push_queue_recipient_pending 
ON push_notification_queue(recipient_user_id) WHERE status = 'pending';

-- 2.6: User profiles search optimization
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_profiles_username_lower 
ON user_profiles(LOWER(username));

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_user_profiles_name_trgm 
ON user_profiles USING gin(name gin_trgm_ops);

-- Enable trigram extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================
-- SECTION 3: REFRESH MATERIALIZED VIEW OPTIMIZATION
-- =====================================================

-- The mv_public_exercises view should be refreshed periodically
-- Create a function to do this efficiently

CREATE OR REPLACE FUNCTION refresh_public_exercises_view()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_public_exercises;
    RAISE NOTICE 'mv_public_exercises refreshed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION refresh_public_exercises_view() TO service_role;

-- =====================================================
-- SECTION 4: PUSH NOTIFICATION RELIABILITY FIX
-- =====================================================

-- 4.1: Add retry logic and tracking columns to notification queue
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS retry_count INTEGER DEFAULT 0;

ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS device_token TEXT;

-- 4.2: Create improved notification processing function
-- This handles retries and fallback delivery

CREATE OR REPLACE FUNCTION process_pending_notifications()
RETURNS TABLE(
    processed_count INTEGER,
    failed_count INTEGER,
    skipped_count INTEGER
) AS $$
DECLARE
    v_processed INTEGER := 0;
    v_failed INTEGER := 0;
    v_skipped INTEGER := 0;
    v_notification RECORD;
    v_device_token TEXT;
BEGIN
    -- Process notifications that are pending and either:
    -- 1. Have no retry scheduled, or
    -- 2. Are past their retry time
    FOR v_notification IN
        SELECT pnq.*, upt.device_token
        FROM push_notification_queue pnq
        LEFT JOIN user_push_tokens upt ON upt.user_id = pnq.recipient_user_id
        WHERE pnq.status = 'pending'
        AND (pnq.next_retry_at IS NULL OR pnq.next_retry_at <= NOW())
        AND pnq.retry_count < 3  -- Max 3 retries
        ORDER BY pnq.created_at ASC
        LIMIT 100  -- Process in batches
        FOR UPDATE SKIP LOCKED  -- Don't block on locked rows
    LOOP
        IF v_notification.device_token IS NULL THEN
            -- No device token, mark as skipped
            UPDATE push_notification_queue 
            SET status = 'skipped', 
                error_message = 'No device token registered'
            WHERE id = v_notification.id;
            v_skipped := v_skipped + 1;
        ELSE
            -- Store device token for Edge Function processing
            UPDATE push_notification_queue 
            SET device_token = v_notification.device_token,
                retry_count = retry_count + 1,
                next_retry_at = NOW() + (retry_count + 1) * INTERVAL '5 minutes'
            WHERE id = v_notification.id;
            v_processed := v_processed + 1;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT v_processed, v_failed, v_skipped;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION process_pending_notifications() TO service_role;

-- 4.3: Function to get notifications ready for sending
-- This is called by the Edge Function

CREATE OR REPLACE FUNCTION get_notifications_to_send(p_limit INTEGER DEFAULT 50)
RETURNS TABLE(
    queue_id UUID,
    recipient_id UUID,
    device_token TEXT,
    notification_type TEXT,
    title TEXT,
    body TEXT,
    data JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pnq.id as queue_id,
        pnq.recipient_user_id as recipient_id,
        upt.device_token,
        pnq.notification_type,
        pnq.title,
        pnq.body,
        pnq.data
    FROM push_notification_queue pnq
    JOIN user_push_tokens upt ON upt.user_id = pnq.recipient_user_id
    WHERE pnq.status = 'pending'
    AND pnq.retry_count < 3
    ORDER BY pnq.created_at ASC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_notifications_to_send(INTEGER) TO service_role;

-- 4.4: Function to mark notifications as sent/failed

CREATE OR REPLACE FUNCTION mark_notification_result(
    p_queue_id UUID,
    p_success BOOLEAN,
    p_error_message TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    IF p_success THEN
        UPDATE push_notification_queue 
        SET status = 'sent', sent_at = NOW()
        WHERE id = p_queue_id;
    ELSE
        UPDATE push_notification_queue 
        SET status = CASE WHEN retry_count >= 3 THEN 'failed' ELSE 'pending' END,
            error_message = p_error_message,
            next_retry_at = NOW() + (retry_count * INTERVAL '5 minutes')
        WHERE id = p_queue_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION mark_notification_result(UUID, BOOLEAN, TEXT) TO service_role;

-- =====================================================
-- SECTION 5: CHALLENGE SYSTEM AUTOMATION
-- =====================================================

-- 5.1: Function to activate challenges that should start today
CREATE OR REPLACE FUNCTION activate_pending_challenges()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    -- Activate challenges where:
    -- 1. All participants have accepted
    -- 2. Start date is today or earlier
    -- 3. Challenge is still pending
    UPDATE friend_challenges fc
    SET status = 'active', updated_at = NOW()
    WHERE fc.status = 'pending'
    AND fc.start_date <= CURRENT_DATE
    AND NOT EXISTS (
        SELECT 1 FROM challenge_participants cp
        WHERE cp.challenge_id = fc.id AND cp.status = 'pending'
    );
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Activated % challenges', v_count;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION activate_pending_challenges() TO service_role;

-- 5.2: Function to complete expired challenges
CREATE OR REPLACE FUNCTION complete_expired_challenges()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    UPDATE friend_challenges
    SET status = 'completed', updated_at = NOW()
    WHERE status = 'active'
    AND end_date < CURRENT_DATE;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Completed % expired challenges', v_count;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION complete_expired_challenges() TO service_role;

-- 5.3: Cleanup stale pending challenge invites (older than 7 days)
CREATE OR REPLACE FUNCTION cleanup_stale_challenge_invites()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    -- Mark invites older than 7 days as declined
    UPDATE challenge_participants
    SET status = 'declined', responded_at = NOW()
    WHERE status = 'pending'
    AND invited_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Also cancel challenges that have no accepted participants
    UPDATE friend_challenges fc
    SET status = 'cancelled', updated_at = NOW()
    WHERE fc.status = 'pending'
    AND NOT EXISTS (
        SELECT 1 FROM challenge_participants cp
        WHERE cp.challenge_id = fc.id AND cp.status = 'accepted'
    )
    AND fc.created_at < NOW() - INTERVAL '7 days';
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cleanup_stale_challenge_invites() TO service_role;

-- =====================================================
-- SECTION 6: REALTIME METRICS SYNC OPTIMIZATION
-- =====================================================

-- 6.1: Optimized step tracking upsert
-- The current implementation is good, but let's add a batch version

CREATE OR REPLACE FUNCTION batch_upsert_step_tracking(
    p_user_id UUID,
    p_data JSONB  -- Array of {date, steps, goal}
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_item JSONB;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        INSERT INTO step_tracking (user_id, date, steps, goal, synced_at)
        VALUES (
            p_user_id,
            (v_item->>'date')::DATE,
            (v_item->>'steps')::INTEGER,
            COALESCE((v_item->>'goal')::INTEGER, 10000),
            NOW()
        )
        ON CONFLICT (user_id, date) 
        DO UPDATE SET 
            steps = GREATEST(step_tracking.steps, EXCLUDED.steps),
            goal = EXCLUDED.goal,
            synced_at = NOW();
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION batch_upsert_step_tracking(UUID, JSONB) TO authenticated;

-- 6.2: Optimized activity correlation upsert
CREATE OR REPLACE FUNCTION batch_upsert_activity_recovery(
    p_user_id UUID,
    p_data JSONB  -- Array of {date, steps, activity_level}
)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_item JSONB;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
    LOOP
        INSERT INTO activity_recovery_correlation (user_id, date, steps, activity_level)
        VALUES (
            p_user_id,
            (v_item->>'date')::DATE,
            (v_item->>'steps')::INTEGER,
            v_item->>'activity_level'
        )
        ON CONFLICT (user_id, date) 
        DO UPDATE SET 
            steps = EXCLUDED.steps,
            activity_level = EXCLUDED.activity_level;
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION batch_upsert_activity_recovery(UUID, JSONB) TO authenticated;

-- =====================================================
-- SECTION 7: HEALTH CHECK QUERIES (FOR MONITORING)
-- =====================================================

-- 7.1: Create a health check function that can be called periodically

CREATE OR REPLACE FUNCTION get_system_health_metrics()
RETURNS TABLE(
    metric_name TEXT,
    metric_value BIGINT,
    status TEXT
) AS $$
BEGIN
    -- Pending notifications count
    RETURN QUERY
    SELECT 
        'pending_notifications'::TEXT,
        COUNT(*)::BIGINT,
        CASE WHEN COUNT(*) > 100 THEN 'warning' ELSE 'ok' END
    FROM push_notification_queue 
    WHERE status = 'pending';
    
    -- Failed notifications in last 24h
    RETURN QUERY
    SELECT 
        'failed_notifications_24h'::TEXT,
        COUNT(*)::BIGINT,
        CASE WHEN COUNT(*) > 50 THEN 'warning' ELSE 'ok' END
    FROM push_notification_queue 
    WHERE status = 'failed' 
    AND created_at > NOW() - INTERVAL '24 hours';
    
    -- Active challenges
    RETURN QUERY
    SELECT 
        'active_challenges'::TEXT,
        COUNT(*)::BIGINT,
        'ok'::TEXT
    FROM friend_challenges 
    WHERE status = 'active';
    
    -- Pending challenge invites older than 3 days
    RETURN QUERY
    SELECT 
        'stale_challenge_invites'::TEXT,
        COUNT(*)::BIGINT,
        CASE WHEN COUNT(*) > 20 THEN 'warning' ELSE 'ok' END
    FROM challenge_participants 
    WHERE status = 'pending' 
    AND invited_at < NOW() - INTERVAL '3 days';
    
    -- Users with device tokens
    RETURN QUERY
    SELECT 
        'users_with_push_enabled'::TEXT,
        COUNT(*)::BIGINT,
        'info'::TEXT
    FROM user_push_tokens;
    
    -- Unread shared workouts
    RETURN QUERY
    SELECT 
        'unread_shared_workouts'::TEXT,
        COUNT(*)::BIGINT,
        'info'::TEXT
    FROM shared_workouts 
    WHERE viewed_at IS NULL;
    
    -- Pending friend requests older than 7 days
    RETURN QUERY
    SELECT 
        'stale_friend_requests'::TEXT,
        COUNT(*)::BIGINT,
        CASE WHEN COUNT(*) > 50 THEN 'warning' ELSE 'ok' END
    FROM friendships 
    WHERE status = 'pending' 
    AND created_at < NOW() - INTERVAL '7 days';
    
    -- Active users in last 24h (if last_login_at exists)
    RETURN QUERY
    SELECT 
        'dau_24h'::TEXT,
        COUNT(*)::BIGINT,
        'info'::TEXT
    FROM user_profiles 
    WHERE last_login_at > NOW() - INTERVAL '24 hours';
    
    -- Active users in last 7 days
    RETURN QUERY
    SELECT 
        'wau_7d'::TEXT,
        COUNT(*)::BIGINT,
        'info'::TEXT
    FROM user_profiles 
    WHERE last_login_at > NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_system_health_metrics() TO service_role;

-- =====================================================
-- SECTION 8: CLEANUP OLD DATA
-- =====================================================

-- 8.1: Clean up old sent notifications (keep 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM push_notification_queue
    WHERE status IN ('sent', 'skipped')
    AND created_at < NOW() - INTERVAL '30 days';
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cleanup_old_notifications() TO service_role;

-- 8.2: Archive old completed challenges (move to archive table)
-- First, create archive table if not exists
CREATE TABLE IF NOT EXISTS friend_challenges_archive (
    LIKE friend_challenges INCLUDING ALL
);

CREATE TABLE IF NOT EXISTS challenge_participants_archive (
    LIKE challenge_participants INCLUDING ALL
);

CREATE TABLE IF NOT EXISTS challenge_daily_progress_archive (
    LIKE challenge_daily_progress INCLUDING ALL
);

CREATE OR REPLACE FUNCTION archive_old_challenges()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_challenge_ids UUID[];
BEGIN
    -- Get challenges completed more than 90 days ago
    SELECT ARRAY_AGG(id) INTO v_challenge_ids
    FROM friend_challenges
    WHERE status IN ('completed', 'cancelled')
    AND updated_at < NOW() - INTERVAL '90 days';
    
    IF v_challenge_ids IS NULL OR array_length(v_challenge_ids, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Archive daily progress
    INSERT INTO challenge_daily_progress_archive
    SELECT * FROM challenge_daily_progress
    WHERE challenge_id = ANY(v_challenge_ids);
    
    DELETE FROM challenge_daily_progress
    WHERE challenge_id = ANY(v_challenge_ids);
    
    -- Archive participants
    INSERT INTO challenge_participants_archive
    SELECT * FROM challenge_participants
    WHERE challenge_id = ANY(v_challenge_ids);
    
    DELETE FROM challenge_participants
    WHERE challenge_id = ANY(v_challenge_ids);
    
    -- Archive challenges
    INSERT INTO friend_challenges_archive
    SELECT * FROM friend_challenges
    WHERE id = ANY(v_challenge_ids);
    
    DELETE FROM friend_challenges
    WHERE id = ANY(v_challenge_ids);
    
    v_count := array_length(v_challenge_ids, 1);
    RAISE NOTICE 'Archived % old challenges', v_count;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION archive_old_challenges() TO service_role;

-- =====================================================
-- SECTION 9: CRON JOBS (pg_cron extension)
-- =====================================================
-- These need to be run after enabling pg_cron extension in Supabase

/*
-- Enable pg_cron (do this in Supabase Dashboard > Database > Extensions)
-- Then run these to schedule the maintenance jobs:

-- Process pending notifications every minute
SELECT cron.schedule(
    'process-notifications',
    '* * * * *',  -- Every minute
    $$SELECT process_pending_notifications()$$
);

-- Activate pending challenges every hour
SELECT cron.schedule(
    'activate-challenges',
    '0 * * * *',  -- Every hour at minute 0
    $$SELECT activate_pending_challenges()$$
);

-- Complete expired challenges daily at midnight
SELECT cron.schedule(
    'complete-challenges',
    '0 0 * * *',  -- Daily at midnight
    $$SELECT complete_expired_challenges()$$
);

-- Cleanup stale challenge invites daily
SELECT cron.schedule(
    'cleanup-stale-invites',
    '0 2 * * *',  -- Daily at 2 AM
    $$SELECT cleanup_stale_challenge_invites()$$
);

-- Cleanup old notifications weekly
SELECT cron.schedule(
    'cleanup-old-notifications',
    '0 3 * * 0',  -- Weekly on Sunday at 3 AM
    $$SELECT cleanup_old_notifications()$$
);

-- Refresh materialized view every 6 hours
SELECT cron.schedule(
    'refresh-exercises-view',
    '0 */6 * * *',  -- Every 6 hours
    $$SELECT refresh_public_exercises_view()$$
);

-- Archive old challenges monthly
SELECT cron.schedule(
    'archive-old-challenges',
    '0 4 1 * *',  -- 4 AM on the 1st of each month
    $$SELECT archive_old_challenges()$$
);

-- System health check every 15 minutes (logs to postgres logs)
SELECT cron.schedule(
    'health-check',
    '*/15 * * * *',  -- Every 15 minutes
    $$SELECT * FROM get_system_health_metrics() WHERE status = 'warning'$$
);
*/

-- =====================================================
-- SECTION 10: VERIFICATION QUERIES
-- =====================================================

-- Check all indexes were created
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(schemaname || '.' || indexname)) as index_size
FROM pg_indexes 
WHERE schemaname = 'public'
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- Check trigger status
SELECT 
    trigger_name,
    event_object_table,
    action_timing,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- Check function permissions
SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN (
    'process_pending_notifications',
    'get_notifications_to_send',
    'activate_pending_challenges',
    'complete_expired_challenges',
    'get_system_health_metrics'
);

-- =====================================================
-- DONE! Summary of changes:
-- =====================================================
/*
1. INDEXES ADDED:
   - idx_exercises_is_custom_false
   - idx_exercises_with_video
   - idx_exercises_video_code
   - idx_shared_workouts_recipient_status
   - idx_shared_workouts_sender_created
   - idx_friendships_requester_status
   - idx_friendships_addressee_status
   - idx_friendships_accepted_both
   - idx_challenge_participants_user_status
   - idx_challenge_daily_progress_user_date
   - idx_push_queue_pending_created
   - idx_push_queue_recipient_pending
   - idx_user_profiles_username_lower
   - idx_user_profiles_name_trgm

2. NOTIFICATION IMPROVEMENTS:
   - Added retry logic (max 3 retries)
   - Added batch processing function
   - Added proper status tracking

3. CHALLENGE AUTOMATION:
   - activate_pending_challenges()
   - complete_expired_challenges()
   - cleanup_stale_challenge_invites()

4. MONITORING:
   - get_system_health_metrics() function
   - Health check for notifications, challenges, etc.

5. CLEANUP:
   - cleanup_old_notifications()
   - archive_old_challenges()

6. BATCH OPERATIONS:
   - batch_upsert_step_tracking()
   - batch_upsert_activity_recovery()

7. CRON JOBS (need to be enabled manually):
   - Notification processing every minute
   - Challenge activation hourly
   - Challenge completion daily
   - Cleanup tasks weekly/monthly
*/

SELECT 'Infrastructure audit and fixes complete!' AS status;
