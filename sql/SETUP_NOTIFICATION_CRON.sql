-- =====================================================================
-- PUSH NOTIFICATION CRON JOB SETUP
-- Ensures notifications are processed even if Edge Function isn't triggered
-- =====================================================================
-- 
-- This sets up a pg_cron job to process pending push notifications
-- Run this AFTER enabling the pg_cron extension in Supabase Dashboard:
-- Extensions → pg_cron → Enable
--
-- =====================================================================

-- Enable pg_cron extension (must be done in Supabase Dashboard first)
-- CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- =====================================================================
-- CRON JOB 1: Process pending notifications every 30 seconds
-- This is the main notification delivery job
-- =====================================================================

-- First, remove existing cron job if it exists (prevents duplicates)
SELECT cron.unschedule('process-push-notifications')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'process-push-notifications'
);

-- Schedule the notification processing job
-- Runs every 30 seconds to ensure quick delivery
SELECT cron.schedule(
    'process-push-notifications',  -- Job name
    '*/1 * * * *',                 -- Every minute (pg_cron minimum is 1 minute)
    $$
    -- Call the Edge Function to process pending notifications
    -- This uses pg_net to make HTTP request to the Edge Function
    SELECT net.http_post(
        url := 'https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/send-push-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.supabase_service_role_key', true)
        ),
        body := '{"batch": true}'::jsonb
    )
    WHERE EXISTS (
        SELECT 1 FROM push_notification_queue 
        WHERE status = 'pending' 
        AND (next_retry_at IS NULL OR next_retry_at <= NOW())
        LIMIT 1
    );
    $$
);

-- =====================================================================
-- CRON JOB 2: Cleanup old notifications (daily at 3 AM UTC)
-- Prevents the queue table from growing unbounded
-- =====================================================================

SELECT cron.unschedule('cleanup-old-notifications')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'cleanup-old-notifications'
);

SELECT cron.schedule(
    'cleanup-old-notifications',
    '0 3 * * *',  -- Daily at 3 AM UTC
    $$
    SELECT cleanup_old_notifications();
    $$
);

-- =====================================================================
-- CRON JOB 3: Auto-complete challenges at end date (daily at midnight)
-- =====================================================================

SELECT cron.unschedule('auto-complete-challenges')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-complete-challenges'
);

SELECT cron.schedule(
    'auto-complete-challenges',
    '0 0 * * *',  -- Daily at midnight UTC
    $$
    SELECT auto_complete_challenges();
    $$
);

-- =====================================================================
-- CRON JOB 4: Auto-activate challenges when start date is reached
-- Runs hourly to check for challenges that should become active
-- =====================================================================

-- Create function to auto-activate challenges at start date
CREATE OR REPLACE FUNCTION auto_activate_pending_challenges()
RETURNS void AS $$
BEGIN
    -- Activate challenges where:
    -- 1. Status is 'pending'
    -- 2. Start date is today or past
    -- 3. All participants have accepted
    UPDATE friend_challenges fc
    SET 
        status = 'active',
        updated_at = NOW()
    WHERE fc.status = 'pending'
    AND fc.start_date <= CURRENT_DATE
    AND NOT EXISTS (
        SELECT 1 FROM challenge_participants cp
        WHERE cp.challenge_id = fc.id
        AND cp.status = 'pending'
    );
    
    -- Log how many were activated
    RAISE NOTICE 'Auto-activated challenges at start date';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT cron.unschedule('auto-activate-challenges')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'auto-activate-challenges'
);

SELECT cron.schedule(
    'auto-activate-challenges',
    '0 * * * *',  -- Every hour
    $$
    SELECT auto_activate_pending_challenges();
    $$
);

-- =====================================================================
-- VERIFICATION: Check cron jobs are scheduled
-- =====================================================================

SELECT jobid, schedule, command, nodename, nodeport, database, username
FROM cron.job
WHERE jobname IN (
    'process-push-notifications',
    'cleanup-old-notifications',
    'auto-complete-challenges',
    'auto-activate-challenges'
);

SELECT 'Cron jobs configured successfully!' AS status;
SELECT 'Note: Make sure pg_cron extension is enabled in Supabase Dashboard' AS note;
