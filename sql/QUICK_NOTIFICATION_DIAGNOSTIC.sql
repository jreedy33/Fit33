-- =====================================================================
-- 🚀 QUICK NOTIFICATION DIAGNOSTIC
-- =====================================================================
-- Run this ENTIRE script in Supabase SQL Editor
-- It handles missing tables gracefully
-- =====================================================================

-- =====================================================================
-- 1. CHECK WHAT TABLES EXIST
-- =====================================================================
SELECT '1. CHECKING TABLES...' AS step;

SELECT 
    table_name,
    '✅ EXISTS' AS status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
    'app_notifications', 
    'push_notification_queue', 
    'user_push_tokens',
    'friendships',
    'friend_challenges',
    'challenge_participants'
)
ORDER BY table_name;

-- =====================================================================
-- 2. CHECK PUSH TOKENS
-- =====================================================================
SELECT '2. PUSH TOKENS...' AS step;

SELECT 
    COUNT(*) AS total_tokens,
    SUM(CASE WHEN is_valid THEN 1 ELSE 0 END) AS valid_tokens
FROM user_push_tokens;

-- =====================================================================
-- 3. CHECK PUSH QUEUE STATUS (Last 48 hours)
-- =====================================================================
SELECT '3. PUSH QUEUE STATUS (Last 48h)...' AS step;

SELECT 
    status,
    COUNT(*) AS count,
    MAX(created_at) AS latest
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '48 hours'
GROUP BY status
ORDER BY count DESC;

-- =====================================================================
-- 4. SHOW FAILED NOTIFICATIONS
-- =====================================================================
SELECT '4. FAILED NOTIFICATIONS (Last 7 days)...' AS step;

SELECT 
    id,
    notification_type,
    title,
    error_message,
    retry_count,
    created_at,
    recipient_user_id
FROM push_notification_queue
WHERE status = 'failed'
AND created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 20;

-- =====================================================================
-- 5. CHECK TRIGGERS ON app_notifications
-- =====================================================================
SELECT '5. TRIGGERS ON app_notifications...' AS step;

SELECT 
    trigger_name,
    event_manipulation AS event,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'app_notifications';

-- =====================================================================
-- 6. CHECK CRON JOBS
-- =====================================================================
SELECT '6. CRON JOBS...' AS step;

SELECT 
    jobname,
    schedule,
    active,
    (SELECT MAX(end_time) FROM cron.job_run_details WHERE jobid = cron.job.jobid) AS last_run
FROM cron.job
WHERE jobname LIKE '%notification%' OR jobname LIKE '%push%';

-- =====================================================================
-- 7. RECENT app_notifications (to see if any were created)
-- =====================================================================
SELECT '7. RECENT APP_NOTIFICATIONS...' AS step;

SELECT 
    notification_type,
    COUNT(*) AS count,
    MAX(created_at) AS latest
FROM app_notifications
WHERE created_at > NOW() - INTERVAL '48 hours'
GROUP BY notification_type
ORDER BY count DESC;

-- =====================================================================
-- 8. YOUR USER's TOKEN STATUS
-- =====================================================================
SELECT '8. YOUR TOKEN STATUS (Joseph)...' AS step;

SELECT 
    user_id,
    device_token IS NOT NULL AS has_token,
    is_valid,
    platform,
    updated_at,
    LEFT(device_token, 20) || '...' AS token_preview
FROM user_push_tokens
WHERE user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a';

-- =====================================================================
-- 9. YOUR NOTIFICATIONS IN QUEUE
-- =====================================================================
SELECT '9. YOUR NOTIFICATIONS IN QUEUE...' AS step;

SELECT 
    id,
    notification_type,
    title,
    status,
    error_message,
    created_at,
    sent_at
FROM push_notification_queue
WHERE recipient_user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'
ORDER BY created_at DESC
LIMIT 10;

-- =====================================================================
-- 10. TRIGGER FUNCTION CHECK
-- =====================================================================
SELECT '10. CHECKING queue_push_notification FUNCTION...' AS step;

SELECT 
    proname AS function_name,
    '✅ EXISTS' AS status
FROM pg_proc 
WHERE proname = 'queue_push_notification';

-- =====================================================================
-- SUMMARY
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS line;
SELECT '📊 DIAGNOSTIC COMPLETE - Review all results above' AS status;
SELECT '═══════════════════════════════════════════════════════════════' AS line;
