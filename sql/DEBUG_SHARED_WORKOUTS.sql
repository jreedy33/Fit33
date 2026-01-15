-- =====================================================
-- DEBUG SHARED WORKOUTS
-- Check why workouts aren't being received
-- =====================================================

-- 1. Check all shared workouts in the table
SELECT 
    sw.id,
    sw.sender_id,
    sw.recipient_id,
    sw.workout_name,
    sw.status,
    sw.created_at,
    sender_profile.name as sender_name,
    recipient_profile.name as recipient_name
FROM shared_workouts sw
LEFT JOIN user_profiles sender_profile ON sender_profile.id = sw.sender_id::text
LEFT JOIN user_profiles recipient_profile ON recipient_profile.id = sw.recipient_id::text
ORDER BY sw.created_at DESC
LIMIT 20;

-- 2. Check friendships between users
SELECT 
    f.id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.created_at,
    requester.name as requester_name,
    addressee.name as addressee_name
FROM friendships f
LEFT JOIN user_profiles requester ON requester.id = f.requester_id::text
LEFT JOIN user_profiles addressee ON addressee.id = f.addressee_id::text
ORDER BY f.created_at DESC;

-- 3. Check user_profiles to find jreedy33 and jreedy36
SELECT id, name, username, email
FROM user_profiles
WHERE username LIKE '%jreedy%' OR name LIKE '%jreedy%' OR name LIKE '%Joe%';

-- 4. Check auth.users for the same
SELECT id, email
FROM auth.users
WHERE email LIKE '%jreedy%' OR email LIKE '%joe%';

-- 5. Test the get_received_workouts function directly
-- (Run this while logged in as jreedy33)
-- SELECT * FROM get_received_workouts();
