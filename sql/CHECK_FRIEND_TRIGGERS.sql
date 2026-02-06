-- Check for duplicate triggers on friend_requests table

SELECT 
    tgname AS trigger_name,
    tgtype AS trigger_type,
    proname AS function_name,
    tgenabled AS is_enabled
FROM pg_trigger tg
JOIN pg_class c ON tg.tgrelid = c.oid
JOIN pg_proc p ON tg.tgfoid = p.oid
WHERE c.relname = 'friend_requests'
AND tgname NOT LIKE 'RI_%'  -- Exclude referential integrity triggers
ORDER BY tgname;

-- Check app_notifications table to see what was inserted
SELECT 
    id,
    user_id,
    notification_type,
    title,
    from_user_name,
    created_at
FROM app_notifications
WHERE notification_type IN ('friend_request', 'friend_request_received')
ORDER BY created_at DESC
LIMIT 20;

-- Check for duplicate notifications in push_notification_queue
SELECT 
    id,
    recipient_user_id,
    notification_type,
    title,
    status,
    created_at
FROM push_notification_queue
WHERE notification_type IN ('friend_request', 'friend_request_received')
ORDER BY created_at DESC
LIMIT 20;
