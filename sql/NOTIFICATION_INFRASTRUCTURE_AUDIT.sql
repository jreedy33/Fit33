-- =====================================================================
-- 🔬 COMPREHENSIVE NOTIFICATION INFRASTRUCTURE AUDIT
-- =====================================================================
-- Run this ENTIRE file to get a complete diagnostic report
-- Author: Infrastructure Lead - Notification Pipeline Analysis
-- Date: 2026-02-05
-- =====================================================================

-- =====================================================================
-- SECTION 1: FAILED NOTIFICATIONS ANALYSIS
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '📊 SECTION 1: FAILED NOTIFICATIONS ANALYSIS' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 1a. All failed notifications in push queue (last 7 days)
SELECT '1a. Failed Push Notifications (Last 7 Days)' AS subsection;
SELECT 
    id,
    notification_type,
    title,
    SUBSTRING(body, 1, 50) || '...' AS body_preview,
    error_message,
    retry_count,
    created_at,
    last_attempt_at,
    recipient_user_id
FROM push_notification_queue
WHERE status = 'failed'
AND created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 50;

-- 1b. Summary of failures by error type
SELECT '1b. Failure Summary by Error Type' AS subsection;
SELECT 
    CASE 
        WHEN error_message LIKE '%BadDeviceToken%' THEN '❌ Bad Device Token'
        WHEN error_message LIKE '%No device token%' THEN '⚠️ No Token Registered'
        WHEN error_message LIKE '%Unregistered%' THEN '📱 Device Unregistered'
        WHEN error_message LIKE '%Network error%' THEN '🌐 Network Error'
        WHEN error_message LIKE '%TopicDisallowed%' THEN '🔒 Topic Disallowed'
        WHEN error_message IS NULL THEN '❓ Unknown (No Error Message)'
        ELSE '⚡ Other: ' || LEFT(error_message, 40)
    END AS error_category,
    COUNT(*) AS count,
    MAX(created_at) AS latest_failure
FROM push_notification_queue
WHERE status = 'failed'
AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1
ORDER BY count DESC;

-- 1c. Failure rate by notification type
SELECT '1c. Failure Rate by Notification Type (Last 24h)' AS subsection;
SELECT 
    notification_type,
    COUNT(*) AS total,
    SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) AS sent,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
    SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending,
    ROUND(100.0 * SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS success_rate_pct
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY notification_type
ORDER BY total DESC;

-- =====================================================================
-- SECTION 2: PIPELINE HEALTH CHECK
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🔧 SECTION 2: PIPELINE HEALTH CHECK' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 2a. Required tables
SELECT '2a. Required Tables' AS subsection;
SELECT 
    t.table_name,
    CASE WHEN t.table_name IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status,
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) AS columns
FROM (
    VALUES 
        ('app_notifications'),
        ('push_notification_queue'),
        ('user_push_tokens'),
        ('contact_joined_notifications'),
        ('friendships'),
        ('challenge_participants'),
        ('friend_challenges')
) AS required(table_name)
LEFT JOIN information_schema.tables t 
    ON t.table_name = required.table_name 
    AND t.table_schema = 'public';

-- 2b. Critical triggers
SELECT '2b. Critical Triggers' AS subsection;
SELECT 
    tg.event_object_table AS trigger_table,
    tg.trigger_name,
    tg.event_manipulation AS trigger_event,
    '✅ ACTIVE' AS status
FROM information_schema.triggers tg
WHERE tg.trigger_name IN (
    'trigger_queue_push_notification',
    'on_challenge_invite', 
    'trigger_contact_joined_notification',
    'on_friend_request_notification',
    'on_challenge_response_notification'
)
ORDER BY tg.event_object_table;

-- 2c. Required functions
SELECT '2c. Required Functions' AS subsection;
SELECT 
    p.proname AS function_name,
    CASE WHEN p.proname IS NOT NULL THEN '✅ EXISTS' ELSE '❌ MISSING' END AS status,
    CASE WHEN p.prosecdef THEN '🔒 SECURITY DEFINER' ELSE '👤 INVOKER' END AS security
FROM pg_proc p
WHERE p.proname IN (
    'send_friend_request',
    'accept_friend_request',
    'queue_push_notification',
    'queue_challenge_invite_notification',
    'queue_contact_joined_notification',
    'respond_to_challenge',
    'create_challenge',
    'cancel_challenge'
)
ORDER BY p.proname;

-- 2d. Cron jobs status
SELECT '2d. Cron Jobs Status' AS subsection;
SELECT 
    jobid,
    jobname,
    schedule,
    CASE WHEN active THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END AS status,
    (SELECT MAX(end_time) FROM cron.job_run_details WHERE jobid = cron.job.jobid) AS last_run
FROM cron.job
WHERE jobname LIKE '%push%' 
   OR jobname LIKE '%notification%'
   OR jobname LIKE '%challenge%';

-- =====================================================================
-- SECTION 3: TOKEN HEALTH
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '📱 SECTION 3: DEVICE TOKEN HEALTH' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 3a. Token statistics
SELECT '3a. Token Statistics' AS subsection;
SELECT 
    COUNT(*) AS total_tokens,
    SUM(CASE WHEN is_valid = true THEN 1 ELSE 0 END) AS valid_tokens,
    SUM(CASE WHEN is_valid = false THEN 1 ELSE 0 END) AS invalid_tokens,
    ROUND(100.0 * SUM(CASE WHEN is_valid = true THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) AS valid_percentage
FROM user_push_tokens;

-- 3b. Users without tokens (can't receive push notifications)
SELECT '3b. Users Without Push Tokens' AS subsection;
SELECT 
    up.id AS user_id,
    up.name,
    up.email,
    up.last_login_at,
    'Cannot receive push notifications' AS issue
FROM user_profiles up
LEFT JOIN user_push_tokens upt ON upt.user_id = up.id
WHERE upt.user_id IS NULL
AND up.last_login_at > NOW() - INTERVAL '30 days'  -- Active users only
ORDER BY up.last_login_at DESC
LIMIT 20;

-- 3c. Stale tokens (not updated in 30 days)
SELECT '3c. Stale Tokens (>30 days old)' AS subsection;
SELECT 
    upt.user_id,
    up.name,
    upt.updated_at AS token_last_updated,
    upt.is_valid,
    CASE 
        WHEN upt.updated_at < NOW() - INTERVAL '90 days' THEN '🔴 CRITICAL'
        WHEN upt.updated_at < NOW() - INTERVAL '60 days' THEN '🟡 WARNING'
        ELSE '🟢 OK'
    END AS staleness
FROM user_push_tokens upt
JOIN user_profiles up ON up.id = upt.user_id
WHERE upt.updated_at < NOW() - INTERVAL '30 days'
ORDER BY upt.updated_at ASC
LIMIT 20;

-- =====================================================================
-- SECTION 4: RECENT NOTIFICATION FLOW ANALYSIS
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '📬 SECTION 4: NOTIFICATION FLOW ANALYSIS (Last 24h)' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 4a. app_notifications created (source)
SELECT '4a. app_notifications Created (Last 24h)' AS subsection;
SELECT 
    notification_type,
    COUNT(*) AS created,
    MAX(created_at) AS latest
FROM app_notifications
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY notification_type
ORDER BY created DESC;

-- 4b. push_notification_queue entries (should match app_notifications)
SELECT '4b. push_notification_queue Entries (Last 24h)' AS subsection;
SELECT 
    notification_type,
    status,
    COUNT(*) AS count,
    MAX(created_at) AS latest
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY notification_type, status
ORDER BY notification_type, status;

-- 4c. Orphaned notifications (in app_notifications but NOT in push_queue)
SELECT '4c. Orphaned Notifications (Not Queued for Push)' AS subsection;
SELECT 
    an.id,
    an.notification_type,
    an.title,
    an.created_at,
    '❌ MISSING FROM PUSH QUEUE' AS issue
FROM app_notifications an
LEFT JOIN push_notification_queue pnq 
    ON pnq.notification_type = an.notification_type 
    AND pnq.title = an.title
    AND pnq.recipient_user_id = an.user_id
    AND pnq.created_at BETWEEN an.created_at - INTERVAL '1 second' AND an.created_at + INTERVAL '5 seconds'
WHERE an.created_at > NOW() - INTERVAL '24 hours'
AND pnq.id IS NULL
ORDER BY an.created_at DESC
LIMIT 20;

-- =====================================================================
-- SECTION 5: SPECIFIC NOTIFICATION TYPE ANALYSIS
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🔍 SECTION 5: NOTIFICATION TYPE DEEP DIVE' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 5a. Friend request notifications
SELECT '5a. Friend Request Notifications (Last 7 Days)' AS subsection;
SELECT 
    'app_notifications' AS source,
    notification_type,
    COUNT(*) AS count,
    COUNT(DISTINCT user_id) AS unique_recipients
FROM app_notifications
WHERE notification_type IN ('friend_request', 'friend_request_received', 'friend_request_accepted')
AND created_at > NOW() - INTERVAL '7 days'
GROUP BY notification_type
UNION ALL
SELECT 
    'push_queue' AS source,
    notification_type,
    COUNT(*) AS count,
    COUNT(DISTINCT recipient_user_id) AS unique_recipients
FROM push_notification_queue
WHERE notification_type IN ('friend_request', 'friend_request_received', 'friend_request_accepted')
AND created_at > NOW() - INTERVAL '7 days'
GROUP BY notification_type
ORDER BY source, notification_type;

-- 5b. Challenge notifications
SELECT '5b. Challenge Notifications (Last 7 Days)' AS subsection;
SELECT 
    notification_type,
    status,
    COUNT(*) AS count
FROM push_notification_queue
WHERE notification_type LIKE 'challenge%'
AND created_at > NOW() - INTERVAL '7 days'
GROUP BY notification_type, status
ORDER BY notification_type, status;

-- 5c. Contact joined notifications
SELECT '5c. Contact Joined Notifications (Last 7 Days)' AS subsection;
SELECT 
    'contact_joined_notifications' AS source,
    COUNT(*) AS entries
FROM contact_joined_notifications
WHERE created_at > NOW() - INTERVAL '7 days'
UNION ALL
SELECT 
    'push_queue (contact_joined)' AS source,
    COUNT(*) AS entries
FROM push_notification_queue
WHERE notification_type = 'contact_joined'
AND created_at > NOW() - INTERVAL '7 days';

-- =====================================================================
-- SECTION 6: TRIGGER VERIFICATION (Does trigger actually fire?)
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '⚡ SECTION 6: TRIGGER VERIFICATION' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- 6a. Check if trigger exists on app_notifications
SELECT '6a. app_notifications Trigger Check' AS subsection;
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'app_notifications';

-- 6b. Inspect trigger function definition
SELECT '6b. queue_push_notification Function Definition' AS subsection;
SELECT pg_get_functiondef(oid) AS function_definition
FROM pg_proc 
WHERE proname = 'queue_push_notification'
LIMIT 1;

-- =====================================================================
-- SECTION 7: CRITICAL METRICS SUMMARY
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '📈 SECTION 7: CRITICAL METRICS SUMMARY' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

SELECT 
    (SELECT COUNT(*) FROM push_notification_queue WHERE created_at > NOW() - INTERVAL '24 hours') AS notifications_24h,
    (SELECT COUNT(*) FROM push_notification_queue WHERE status = 'sent' AND created_at > NOW() - INTERVAL '24 hours') AS sent_24h,
    (SELECT COUNT(*) FROM push_notification_queue WHERE status = 'failed' AND created_at > NOW() - INTERVAL '24 hours') AS failed_24h,
    (SELECT COUNT(*) FROM push_notification_queue WHERE status = 'pending') AS currently_pending,
    (SELECT COUNT(*) FROM user_push_tokens WHERE is_valid = true) AS valid_tokens,
    (SELECT COUNT(*) FROM user_profiles) AS total_users,
    CASE 
        WHEN (SELECT COUNT(*) FROM push_notification_queue WHERE status = 'failed' AND created_at > NOW() - INTERVAL '24 hours') > 10 
        THEN '🔴 HIGH FAILURE RATE'
        WHEN (SELECT COUNT(*) FROM push_notification_queue WHERE status = 'pending') > 50 
        THEN '🟡 QUEUE BACKUP'
        ELSE '🟢 HEALTHY'
    END AS overall_health;

-- =====================================================================
-- END OF AUDIT
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '✅ AUDIT COMPLETE - Review results above for issues' AS status;
SELECT 'Run NOTIFICATION_TESTING_SUITE.sql to test each notification type' AS next_step;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
