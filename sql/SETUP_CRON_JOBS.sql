-- ============================================================================
-- CRON JOBS SETUP FOR FIT33 APP
-- ============================================================================
-- Run this in Supabase SQL Editor to set up automated background tasks
-- Note: pg_cron must be enabled in your Supabase project (it's enabled by default)
-- ============================================================================

-- ============================================================================
-- 1. RETRY FAILED PUSH NOTIFICATIONS (Every minute)
-- ============================================================================
-- Retries notifications that failed to send (up to 3 attempts)

SELECT cron.schedule(
    'retry-failed-notifications',
    '* * * * *',  -- Every minute
    $$
    UPDATE push_notification_queue
    SET 
        status = 'pending',
        retry_count = retry_count + 1,
        updated_at = NOW()
    WHERE 
        status = 'failed'
        AND retry_count < 3
        AND created_at > NOW() - INTERVAL '1 hour';
    $$
);

-- ============================================================================
-- 2. CLEANUP OLD SENT NOTIFICATIONS (Daily at 3 AM UTC)
-- ============================================================================
-- Removes successfully sent notifications older than 7 days

SELECT cron.schedule(
    'cleanup-sent-notifications',
    '0 3 * * *',  -- Daily at 3 AM UTC
    $$
    DELETE FROM push_notification_queue
    WHERE 
        status = 'sent'
        AND created_at < NOW() - INTERVAL '7 days';
    $$
);

-- ============================================================================
-- 3. AUTO-ACTIVATE CHALLENGES (Every 5 minutes)
-- ============================================================================
-- Activates challenges when start_date is reached and all participants accepted

SELECT cron.schedule(
    'activate-pending-challenges',
    '*/5 * * * *',  -- Every 5 minutes
    $$
    UPDATE friend_challenges
    SET 
        status = 'active',
        updated_at = NOW()
    WHERE 
        status = 'pending'
        AND start_date <= CURRENT_DATE
        AND NOT EXISTS (
            SELECT 1 FROM challenge_participants cp
            WHERE cp.challenge_id = friend_challenges.id
            AND cp.status = 'pending'
        );
    $$
);

-- ============================================================================
-- 4. AUTO-COMPLETE CHALLENGES (Daily at midnight UTC)
-- ============================================================================
-- Marks active challenges as completed when end_date is passed

SELECT cron.schedule(
    'complete-ended-challenges',
    '0 0 * * *',  -- Daily at midnight UTC
    $$
    UPDATE friend_challenges
    SET 
        status = 'completed',
        updated_at = NOW()
    WHERE 
        status = 'active'
        AND end_date < CURRENT_DATE;
    $$
);

-- ============================================================================
-- 5. EXPIRE OLD PENDING CHALLENGE INVITES (Daily at 4 AM UTC)
-- ============================================================================
-- Auto-declines invites that have been pending for over 7 days

SELECT cron.schedule(
    'expire-old-challenge-invites',
    '0 4 * * *',  -- Daily at 4 AM UTC
    $$
    -- Cancel challenges where invites expired
    UPDATE friend_challenges
    SET 
        status = 'cancelled',
        updated_at = NOW()
    WHERE 
        status = 'pending'
        AND created_at < NOW() - INTERVAL '7 days';
        
    -- Update participant status
    UPDATE challenge_participants
    SET 
        status = 'declined',
        updated_at = NOW()
    WHERE 
        status = 'pending'
        AND created_at < NOW() - INTERVAL '7 days';
    $$
);

-- ============================================================================
-- 6. REFRESH MATERIALIZED VIEWS (Every 15 minutes)
-- ============================================================================
-- Keeps materialized views fresh for analytics

SELECT cron.schedule(
    'refresh-materialized-views',
    '*/15 * * * *',  -- Every 15 minutes
    $$
    REFRESH MATERIALIZED VIEW CONCURRENTLY IF EXISTS user_activity_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY IF EXISTS exercise_popularity_stats;
    $$
);

-- ============================================================================
-- 7. CLEANUP STALE DEVICE TOKENS (Weekly on Sunday at 2 AM UTC)
-- ============================================================================
-- Removes device tokens that haven't been updated in 90 days

SELECT cron.schedule(
    'cleanup-stale-device-tokens',
    '0 2 * * 0',  -- Every Sunday at 2 AM UTC
    $$
    DELETE FROM user_push_tokens
    WHERE updated_at < NOW() - INTERVAL '90 days';
    $$
);

-- ============================================================================
-- VIEW SCHEDULED JOBS
-- ============================================================================
-- Run this to see all scheduled jobs:

SELECT 
    jobid,
    jobname,
    schedule,
    active,
    command
FROM cron.job
ORDER BY jobname;

-- ============================================================================
-- TO UNSCHEDULE A JOB (if needed):
-- ============================================================================
-- SELECT cron.unschedule('job-name-here');
-- Example: SELECT cron.unschedule('retry-failed-notifications');
