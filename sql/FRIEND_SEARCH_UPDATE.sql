-- ============================================================================
-- FRIEND SEARCH UPDATE
-- 1. Make search_users require exact username match
-- 2. Add profile_photo_url to get_pending_friend_requests
-- ============================================================================

-- Step 1: Update search_users to require EXACT username match only
-- NOTE: Field aliases MUST be snake_case to match Swift CodingKeys!
DROP FUNCTION IF EXISTS search_users(TEXT, INT);

CREATE OR REPLACE FUNCTION search_users(
    search_query TEXT,
    result_limit INT DEFAULT 20
)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    profile_photo_url TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        u.id as user_id,
        up.name,
        u.email::TEXT,
        up.username,
        up.fitness_goal,
        up.experience_level,
        up.profile_photo_url,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as is_friend,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as has_pending_request
    FROM auth.users u
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    WHERE u.id != current_user_uuid
    -- EXACT match only on username (case insensitive)
    AND up.username IS NOT NULL
    AND LOWER(up.username) = LOWER(search_query)
    LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- Step 2: Update get_pending_friend_requests to include profile_photo_url and username
DROP FUNCTION IF EXISTS get_pending_friend_requests();

CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    from_user_email TEXT,
    from_user_username TEXT,
    profile_photo_url TEXT,
    message TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.requester_id as from_user_id,
        up.name as from_user_name,
        u.email::TEXT as from_user_email,
        up.username as from_user_username,
        up.profile_photo_url,
        f.message,
        f.created_at
    FROM friendships f
    LEFT JOIN user_profiles up ON up.id::TEXT = f.requester_id::TEXT
    LEFT JOIN auth.users u ON u.id = f.requester_id
    WHERE f.addressee_id = current_user_id
    AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pending_friend_requests() TO authenticated;

-- Step 3: Fix get_friends function - MUST use snake_case to match Swift CodingKeys!
-- This ensures both users see each other after accepting a friend request
DROP FUNCTION IF EXISTS get_friends();

CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID,
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    friend_username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    profile_photo_url TEXT,
    friends_since TIMESTAMPTZ,
    total_workouts_shared INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as friendship_id,
        -- Return the OTHER user's ID (the friend, not the current user)
        CASE 
            WHEN f.requester_id = current_user_uuid THEN f.addressee_id
            ELSE f.requester_id 
        END as friend_id,
        up.name as friend_name,
        u.email::TEXT as friend_email,
        up.username as friend_username,
        up.fitness_goal,
        up.experience_level,
        up.profile_photo_url,
        f.updated_at as friends_since,
        COALESCE((
            SELECT COUNT(*)::INT FROM shared_workouts sw
            WHERE (sw.sender_id = current_user_uuid AND sw.recipient_id = CASE 
                WHEN f.requester_id = current_user_uuid THEN f.addressee_id
                ELSE f.requester_id 
            END)
            OR (sw.recipient_id = current_user_uuid AND sw.sender_id = CASE 
                WHEN f.requester_id = current_user_uuid THEN f.addressee_id
                ELSE f.requester_id 
            END)
        ), 0) as total_workouts_shared
    FROM friendships f
    -- Join to get the friend's user record (the OTHER person)
    JOIN auth.users u ON u.id = CASE 
        WHEN f.requester_id = current_user_uuid THEN f.addressee_id
        ELSE f.requester_id 
    END
    -- Join to get the friend's profile (the OTHER person)
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    -- Only accepted friendships (both users see each other)
    WHERE f.status = 'accepted'
    -- Current user is either requester OR addressee (bidirectional)
    AND (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid)
    ORDER BY f.updated_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;

-- Done!
SELECT 'Friend system update complete!' AS status;
SELECT '- search_users: exact username match with snake_case fields' AS info1;
SELECT '- get_pending_friend_requests: includes profile photo and username' AS info2;
SELECT '- get_friends: snake_case fields, bidirectional friendships work correctly' AS info3;
