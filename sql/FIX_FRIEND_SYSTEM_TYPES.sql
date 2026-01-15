-- =====================================================
-- FIX FRIEND SYSTEM TYPE MISMATCHES
-- Run this to fix "operator does not exist: uuid = text" errors
-- =====================================================

-- First, check if username was saved for joereedis@icloud.com
SELECT id, email, username FROM user_profiles WHERE email = 'joereedis@icloud.com';

-- =====================================================
-- FIX 1: get_pending_friend_requests - fix type casting
-- =====================================================
DROP FUNCTION IF EXISTS get_pending_friend_requests();

CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    from_user_email TEXT,
    message TEXT,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.requester_id as from_user_id,
        up.name as from_user_name,
        u.email as from_user_email,
        f.message,
        f.created_at
    FROM friendships f
    LEFT JOIN user_profiles up ON up.id = f.requester_id::text
    LEFT JOIN auth.users u ON u.id = f.requester_id
    WHERE f.addressee_id = current_user_id
    AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- FIX 2: get_received_workouts - fix type casting
-- =====================================================
DROP FUNCTION IF EXISTS get_received_workouts();

CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    id TEXT,
    from_user_id TEXT,
    sender_name TEXT,
    workout_name TEXT,
    workout_description TEXT,
    exercises JSONB,
    message TEXT,
    status TEXT,
    estimated_duration INT,
    difficulty_level TEXT,
    created_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id::text,
        sw.sender_id::text as from_user_id,
        COALESCE(up.name, u.email, 'Unknown') as sender_name,
        sw.workout_name,
        sw.workout_description,
        sw.exercises,
        sw.message,
        sw.status,
        sw.estimated_duration,
        sw.difficulty_level,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites
    FROM shared_workouts sw
    LEFT JOIN user_profiles up ON up.id = sw.sender_id::text
    LEFT JOIN auth.users u ON u.id = sw.sender_id
    WHERE sw.recipient_id = current_user_id
    ORDER BY sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- CHECK: Verify username column exists and show all usernames
-- =====================================================
SELECT 
    up.id,
    up.name,
    up.email,
    up.username,
    u.email as auth_email
FROM user_profiles up
LEFT JOIN auth.users u ON u.id::text = up.id
ORDER BY up.created_at DESC
LIMIT 10;

-- =====================================================
-- MANUAL FIX: If username wasn't saved, set it manually
-- =====================================================
-- Uncomment and run this if jreedy33 wasn't saved:
-- UPDATE user_profiles 
-- SET username = 'jreedy33' 
-- WHERE email = 'joereedis@icloud.com';
