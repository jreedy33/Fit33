-- ============================================================================
-- NOTIFICATION END-TO-END TEST SUITE
-- Run these queries INDIVIDUALLY to test the notification pipeline
-- ============================================================================

-- ============================================================================
-- TEST 1: Check current token status
-- ============================================================================

SELECT 
    u.name,
    t.user_id,
    t.is_valid,
    t.apns_environment,
    t.platform,
    t.updated_at,
    LEFT(t.device_token, 20) || '...' AS token_preview
FROM user_push_tokens t
JOIN users u ON u.id = t.user_id
ORDER BY t.updated_at DESC;

-- ============================================================================
-- TEST 2: Check queue status
-- ============================================================================

SELECT 
    status,
    COUNT(*) as count,
    MAX(created_at) as latest
FROM push_notification_queue
GROUP BY status
ORDER BY count DESC;

-- ============================================================================
-- TEST 3: View recent notifications (all statuses)
-- ============================================================================

SELECT 
    id,
    notification_type,
    title,
    status,
    CASE 
        WHEN error_message IS NOT NULL THEN LEFT(error_message, 50) || '...'
        ELSE NULL 
    END as error_preview,
    created_at
FROM push_notification_queue
ORDER BY created_at DESC
LIMIT 20;

-- ============================================================================
-- TEST 4: Send a TEST notification to yourself (Joseph Reed)
-- Replace the user_id with your actual user_id
-- ============================================================================

-- First, find your user_id:
SELECT id, name FROM users WHERE name ILIKE '%joseph%' LIMIT 5;

-- Then insert a test notification:
-- UNCOMMENT AND MODIFY THE user_id BELOW TO SEND A TEST:

/*
INSERT INTO push_notification_queue (
    recipient_user_id,
    notification_type,
    title,
    body,
    data,
    status,
    created_at
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a',  -- Joseph Reed's user_id
    'test',
    '🔔 Test Notification',
    'This is a test from the notification pipeline!',
    '{"test": true, "timestamp": "' || NOW()::text || '"}'::jsonb,
    'pending',
    NOW()
);
*/

-- ============================================================================
-- TEST 5: Check if the trigger exists on app_notifications
-- ============================================================================

SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'app_notifications';

-- ============================================================================
-- TEST 6: Check cron jobs are running
-- ============================================================================

SELECT 
    jobname,
    schedule,
    active,
    nodename
FROM cron.job
WHERE jobname LIKE '%notification%' OR jobname LIKE '%push%';

-- ============================================================================
-- TEST 7: Manually trigger the notification processor
-- Run this in the Supabase Dashboard via "Invoke" on the send-push-notification function
-- Or via curl:
-- ============================================================================

-- The cron job runs every minute, but you can also manually invoke:
-- curl -X POST https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notification \
--   -H "Authorization: Bearer YOUR_ANON_KEY" \
--   -H "Content-Type: application/json"

-- ============================================================================
-- TEST 8: Check for any pending notifications waiting
-- ============================================================================

SELECT 
    pq.id,
    u.name as recipient,
    pq.notification_type,
    pq.title,
    pq.status,
    pq.retry_count,
    pq.created_at
FROM push_notification_queue pq
JOIN users u ON u.id = pq.recipient_user_id
WHERE pq.status = 'pending'
ORDER BY pq.created_at ASC;

-- ============================================================================
-- CLEANUP: Remove old failed notifications with BadDeviceToken errors
-- ============================================================================

-- View what will be deleted:
SELECT COUNT(*) as to_delete
FROM push_notification_queue 
WHERE status = 'failed' 
AND error_message LIKE '%BadDeviceToken%';

-- UNCOMMENT TO DELETE:
/*
DELETE FROM push_notification_queue 
WHERE status = 'failed' 
AND error_message LIKE '%BadDeviceToken%';
*/
