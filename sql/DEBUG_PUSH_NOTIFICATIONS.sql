-- =====================================================
-- DEBUG PUSH NOTIFICATIONS
-- Run these queries to diagnose notification issues
-- =====================================================

-- Joseph's ID: e31f9d3b-a43e-44a8-a31f-6826e9d17e1a
-- Nick's ID: 6b52c679-fe99-4834-b3d4-648cbdeef93b

-- =====================================================
-- 1. CHECK WHAT NOTIFICATION-RELATED TABLES EXIST
-- =====================================================
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND (table_name LIKE '%push%' 
     OR table_name LIKE '%notif%' 
     OR table_name LIKE '%token%'
     OR table_name LIKE '%device%')
ORDER BY table_name;

-- =====================================================
-- 1b. CHECK COLUMNS IN app_notifications TABLE
-- =====================================================
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'app_notifications'
ORDER BY ordinal_position;

-- =====================================================
-- 2. CHECK APP NOTIFICATIONS FOR JOSEPH (recent)
-- =====================================================
SELECT *
FROM app_notifications 
WHERE user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'
ORDER BY created_at DESC
LIMIT 20;

-- =====================================================
-- 3. CHECK FRIEND REQUEST NOTIFICATIONS SPECIFICALLY
-- =====================================================
SELECT *
FROM app_notifications
WHERE user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'
AND notification_type = 'friend_request_received'
ORDER BY created_at DESC
LIMIT 10;

-- =====================================================
-- 4. CHECK IF PUSH TOKENS TABLE EXISTS AND HAS DATA
-- =====================================================
-- Try push_tokens table
SELECT * FROM push_tokens 
WHERE user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a';

-- =====================================================
-- 5. CHECK USER_PROFILES FOR TOKEN COLUMNS
-- =====================================================
SELECT 
    column_name, 
    data_type 
FROM information_schema.columns 
WHERE table_name = 'user_profiles' 
AND (column_name LIKE '%token%' 
     OR column_name LIKE '%push%' 
     OR column_name LIKE '%apns%'
     OR column_name LIKE '%fcm%'
     OR column_name LIKE '%device%');

-- =====================================================
-- 6. CHECK JOSEPH'S PROFILE FOR ANY TOKEN FIELDS
-- =====================================================
SELECT 
    id, 
    name,
    username,
    email
    -- Add token columns if they exist (uncomment as needed):
    -- , push_token
    -- , apns_token  
    -- , fcm_token
    -- , device_token
FROM user_profiles 
WHERE id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a';

-- =====================================================
-- 7. CHECK ALL USERS WITH PUSH TOKENS (if column exists)
-- =====================================================
-- Uncomment the appropriate one based on what columns exist:

-- SELECT id, name, push_token IS NOT NULL as has_token
-- FROM user_profiles WHERE push_token IS NOT NULL;

-- SELECT id, name, apns_token IS NOT NULL as has_token  
-- FROM user_profiles WHERE apns_token IS NOT NULL;

-- SELECT id, name, fcm_token IS NOT NULL as has_token
-- FROM user_profiles WHERE fcm_token IS NOT NULL;

-- =====================================================
-- 8. CHECK IF THERE'S A NOTIFICATION SEND LOG
-- =====================================================
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND (table_name LIKE '%log%' OR table_name LIKE '%send%' OR table_name LIKE '%queue%');

-- =====================================================
-- 9. CHECK EDGE FUNCTIONS (if using Supabase Edge Functions)
-- =====================================================
-- This needs to be checked in Supabase Dashboard > Edge Functions
-- Look for functions like:
--   - send-push-notification
--   - notify-friend-request
--   - push-notification-handler

-- =====================================================
-- 10. CHECK DATABASE TRIGGERS ON app_notifications
-- =====================================================
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'app_notifications';

-- =====================================================
-- 11. CHECK IF send_friend_request CREATES NOTIFICATIONS
-- =====================================================
-- View the function definition
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'send_friend_request';

-- =====================================================
-- SUMMARY: What to look for
-- =====================================================
-- 1. If app_notifications has the friend request → in-app notif was created ✓
-- 2. If no push token columns/tables exist → push notifications aren't set up
-- 3. If tokens exist but no trigger → need Edge Function to send to APNs
-- 4. If trigger exists → check Edge Function logs in Supabase Dashboard

-- =====================================================
-- QUICK FIX: Check if notification was created for Nick → Joseph request
-- =====================================================
SELECT *
FROM app_notifications 
WHERE user_id = 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'
AND created_at >= '2026-02-04 22:40:00'  -- Around when Nick sent request
ORDER BY created_at ASC;
