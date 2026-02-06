-- Check for duplicate triggers on app_notifications table
-- (this table triggers push_notification_queue inserts)

SELECT 
    tgname AS trigger_name,
    tgtype AS trigger_type,
    proname AS function_name,
    tgenabled AS is_enabled,
    pg_get_triggerdef(tg.oid) AS trigger_definition
FROM pg_trigger tg
JOIN pg_class c ON tg.tgrelid = c.oid
JOIN pg_proc p ON tg.tgfoid = p.oid
WHERE c.relname = 'app_notifications'
AND tgname NOT LIKE 'RI_%'  -- Exclude referential integrity triggers
ORDER BY tgname;

-- This will show if there are duplicate triggers that queue notifications
