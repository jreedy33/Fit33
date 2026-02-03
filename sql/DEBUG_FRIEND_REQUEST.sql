-- ============================================================================
-- DEBUG: Friend Request Not Showing for jreedy333
-- Issue: alicia sent friend request, push notification received, but request
--        not visible in app after tapping notification
-- ============================================================================

-- 1. Find both users by username
SELECT 
    id as user_id,
    name,
    username,
    email,
    created_at
FROM user_profiles
WHERE username ILIKE '%alicia%' 
   OR username ILIKE '%jreedy333%'
ORDER BY username;

-- 2. Check ALL pending friendships in the system (most recent first)
SELECT 
    f.id as request_id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.message,
    f.created_at,
    f.updated_at,
    req_profile.username as requester_username,
    req_profile.name as requester_name,
    addr_profile.username as addressee_username,
    addr_profile.name as addressee_name
FROM friendships f
LEFT JOIN user_profiles req_profile ON req_profile.id::text = f.requester_id::text
LEFT JOIN user_profiles addr_profile ON addr_profile.id::text = f.addressee_id::text
ORDER BY f.created_at DESC
LIMIT 30;

-- 3. Check specifically for requests TO jreedy333 (as addressee)
SELECT 
    f.id as request_id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.message,
    f.created_at,
    req_profile.username as from_username,
    req_profile.name as from_name
FROM friendships f
LEFT JOIN user_profiles req_profile ON req_profile.id::text = f.requester_id::text
LEFT JOIN user_profiles addr_profile ON addr_profile.id::text = f.addressee_id::text
WHERE addr_profile.username ILIKE '%jreedy333%'
ORDER BY f.created_at DESC;

-- 4. Check specifically for requests FROM alicia (as requester)
SELECT 
    f.id as request_id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.message,
    f.created_at,
    addr_profile.username as to_username,
    addr_profile.name as to_name
FROM friendships f
LEFT JOIN user_profiles req_profile ON req_profile.id::text = f.requester_id::text
LEFT JOIN user_profiles addr_profile ON addr_profile.id::text = f.addressee_id::text
WHERE req_profile.username ILIKE '%alicia%'
ORDER BY f.created_at DESC;

-- 5. Test the get_pending_friend_requests function as jreedy333
-- First, get jreedy333's user ID, then test the function
-- (Run the SELECT first to get the ID, then uncomment and run the function test)

-- Get jreedy333's auth.users ID
SELECT 
    au.id as auth_user_id,
    up.id as profile_id,
    up.username,
    au.email
FROM auth.users au
JOIN user_profiles up ON up.id::text = au.id::text
WHERE up.username ILIKE '%jreedy333%';

-- 6. Check if there's a data type mismatch issue
-- Compare the types of IDs in friendships vs user_profiles
SELECT 
    column_name, 
    data_type, 
    udt_name
FROM information_schema.columns 
WHERE table_name = 'friendships' 
  AND column_name IN ('requester_id', 'addressee_id', 'id');

SELECT 
    column_name, 
    data_type, 
    udt_name
FROM information_schema.columns 
WHERE table_name = 'user_profiles' 
  AND column_name = 'id';

-- 7. Check push notification logs (if you have logging)
-- This shows if the notification was sent correctly
SELECT *
FROM push_notification_logs
WHERE created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC
LIMIT 20;

-- ============================================================================
-- AFTER RUNNING THE ABOVE, if the request EXISTS but isn't showing:
-- The issue is likely in the Swift app's fetch or display logic.
-- 
-- If the request DOES NOT EXIST with status='pending':
-- Check if it was auto-accepted, declined, or never created.
-- ============================================================================
