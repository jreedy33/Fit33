-- =====================================================
-- COMPLETE NOTIFICATION SYSTEM VERIFICATION
-- Run this to verify everything is correctly set up
-- =====================================================

-- ===========================================
-- 1. REQUIRED TABLES
-- ===========================================
SELECT '1. REQUIRED TABLES' AS section;

SELECT 
    table_name,
    CASE WHEN table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('app_notifications', 'push_notification_queue', 'user_push_tokens', 'contact_joined_notifications', 'friendships', 'challenge_participants', 'friend_challenges')
ORDER BY table_name;


-- ===========================================
-- 2. APP_NOTIFICATIONS TABLE COLUMNS
-- ===========================================
SELECT '2. APP_NOTIFICATIONS COLUMNS' AS section;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'app_notifications'
ORDER BY ordinal_position;


-- ===========================================
-- 3. PUSH_NOTIFICATION_QUEUE TABLE COLUMNS
-- ===========================================
SELECT '3. PUSH_NOTIFICATION_QUEUE COLUMNS' AS section;

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'push_notification_queue'
ORDER BY ordinal_position;


-- ===========================================
-- 4. ALL REQUIRED TRIGGERS
-- ===========================================
SELECT '4. REQUIRED TRIGGERS' AS section;

SELECT 
    event_object_table AS table_name,
    trigger_name,
    event_manipulation AS event,
    '✅' AS status
FROM information_schema.triggers
WHERE (event_object_table = 'app_notifications' AND trigger_name = 'trigger_queue_push_notification')
   OR (event_object_table = 'challenge_participants' AND trigger_name = 'on_challenge_invite')
   OR (event_object_table = 'contact_joined_notifications' AND trigger_name = 'trigger_contact_joined_notification')
ORDER BY event_object_table;


-- ===========================================
-- 5. REQUIRED FUNCTIONS
-- ===========================================
SELECT '5. REQUIRED FUNCTIONS' AS section;

SELECT 
    proname AS function_name,
    '✅ EXISTS' AS status
FROM pg_proc
WHERE proname IN (
    'send_friend_request',
    'accept_friend_request', 
    'respond_to_challenge',
    'queue_challenge_invite_notification',
    'queue_push_notification',
    'queue_contact_joined_notification',
    'notify_contacts_of_new_user'
)
ORDER BY proname;


-- ===========================================
-- 6. CRON JOB STATUS
-- ===========================================
SELECT '6. CRON JOB STATUS' AS section;

SELECT 
    jobid,
    jobname,
    schedule,
    CASE WHEN active THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END AS status
FROM cron.job
WHERE jobname LIKE '%push%' OR jobname LIKE '%notification%';


-- ===========================================
-- 7. USERS WITH PUSH TOKENS
-- ===========================================
SELECT '7. USERS WITH VALID PUSH TOKENS' AS section;

SELECT 
    COUNT(*) AS total_tokens,
    COUNT(*) FILTER (WHERE is_valid = true) AS valid_tokens,
    COUNT(*) FILTER (WHERE is_valid = false) AS invalid_tokens
FROM user_push_tokens;


-- ===========================================
-- 8. PUSH NOTIFICATION QUEUE STATUS
-- ===========================================
SELECT '8. PUSH QUEUE STATUS (Last 24 Hours)' AS section;

SELECT 
    status,
    COUNT(*) AS count,
    MAX(created_at) AS latest
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY status
ORDER BY count DESC;


-- ===========================================
-- 9. RECENT APP NOTIFICATIONS BY TYPE
-- ===========================================
SELECT '9. RECENT APP NOTIFICATIONS BY TYPE (Last 7 Days)' AS section;

SELECT 
    notification_type,
    COUNT(*) AS count,
    MAX(created_at) AS latest
FROM app_notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY notification_type
ORDER BY count DESC;


-- ===========================================
-- 10. FUNCTION VERIFICATION - send_friend_request
-- ===========================================
SELECT '10. VERIFY send_friend_request CREATES app_notifications' AS section;

SELECT 
    CASE 
        WHEN pg_get_functiondef(oid) LIKE '%INSERT INTO app_notifications%' 
        THEN '✅ Creates app_notifications'
        ELSE '❌ Missing app_notifications insert'
    END AS status
FROM pg_proc 
WHERE proname = 'send_friend_request';


-- ===========================================
-- 11. FUNCTION VERIFICATION - accept_friend_request
-- ===========================================
SELECT '11. VERIFY accept_friend_request CREATES app_notifications' AS section;

SELECT 
    CASE 
        WHEN pg_get_functiondef(oid) LIKE '%INSERT INTO app_notifications%' 
        THEN '✅ Creates app_notifications'
        ELSE '❌ Missing app_notifications insert'
    END AS status
FROM pg_proc 
WHERE proname = 'accept_friend_request';


-- ===========================================
-- 12. FUNCTION VERIFICATION - respond_to_challenge
-- ===========================================
SELECT '12. VERIFY respond_to_challenge CREATES app_notifications' AS section;

SELECT 
    CASE 
        WHEN pg_get_functiondef(oid) LIKE '%INSERT INTO app_notifications%' 
        THEN '✅ Creates app_notifications'
        ELSE '❌ Missing app_notifications insert'
    END AS status
FROM pg_proc 
WHERE proname = 'respond_to_challenge';


-- ===========================================
-- 13. FUNCTION VERIFICATION - queue_challenge_invite_notification
-- ===========================================
SELECT '13. VERIFY queue_challenge_invite_notification CREATES app_notifications' AS section;

SELECT 
    CASE 
        WHEN pg_get_functiondef(oid) LIKE '%INSERT INTO app_notifications%' 
        THEN '✅ Creates app_notifications'
        ELSE '❌ Missing app_notifications insert (goes direct to push_queue)'
    END AS status
FROM pg_proc 
WHERE proname = 'queue_challenge_invite_notification';


-- ===========================================
-- 14. END-TO-END TEST (Optional - Uncomment to run)
-- ===========================================
/*
SELECT '14. END-TO-END TEST' AS section;

-- Insert a test notification
INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a',  -- Your user ID
    'test',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a',
    'System Verification Test',
    'If you receive this push, the system is working!',
    false
)
RETURNING id, 'Test notification created - check push_notification_queue' AS status;

-- Check if it appeared in the push queue
SELECT 
    id,
    notification_type,
    title,
    status,
    created_at
FROM push_notification_queue 
WHERE notification_type = 'test'
ORDER BY created_at DESC 
LIMIT 1;
*/


-- ===========================================
-- SUMMARY
-- ===========================================
SELECT '========== VERIFICATION COMPLETE ==========' AS section;
SELECT 'Review results above. All items should show ✅' AS instruction;
SELECT 'If any show ❌, re-run COMPLETE_NOTIFICATION_FIXES.sql' AS action;
