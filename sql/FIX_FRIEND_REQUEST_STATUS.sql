-- ============================================================================
-- FIX FRIEND REQUEST STATUS IN SEARCH
-- 
-- Problem: When searching for a user, `has_pending_request` returns true for
-- BOTH directions (I sent them OR they sent me). This causes "Pending" to 
-- show incorrectly in some cases.
--
-- Solution: Split into two separate flags:
-- - has_outgoing_request: I sent them a request (show "Pending")
-- - has_incoming_request: They sent me a request (show "Respond" or navigate to requests)
-- ============================================================================

-- Step 1: Update search_users to have separate outgoing/incoming flags
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
    has_pending_request BOOLEAN,  -- Kept for backwards compatibility (true if either direction)
    has_outgoing_request BOOLEAN, -- I sent THEM a pending request
    has_incoming_request BOOLEAN  -- THEY sent ME a pending request
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
        -- Is friend: accepted friendship exists
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as is_friend,
        -- Has pending request (either direction) - for backwards compatibility
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as has_pending_request,
        -- Has OUTGOING request: I sent THEM a pending request
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND f.requester_id = current_user_uuid 
            AND f.addressee_id = u.id
        ) as has_outgoing_request,
        -- Has INCOMING request: THEY sent ME a pending request
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND f.requester_id = u.id 
            AND f.addressee_id = current_user_uuid
        ) as has_incoming_request
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

-- Step 2: Clean up any orphaned or duplicate friendship records
-- This fixes cases where there are multiple records between the same users
-- (e.g., both pending and accepted, or duplicate pending requests)

-- First, delete any 'declined' records (they should be removed, not kept)
DELETE FROM friendships WHERE status = 'declined';

-- Delete duplicate pending requests where an accepted friendship already exists
DELETE FROM friendships f1
WHERE f1.status = 'pending'
AND EXISTS (
    SELECT 1 FROM friendships f2 
    WHERE f2.status = 'accepted'
    AND (
        (f2.requester_id = f1.requester_id AND f2.addressee_id = f1.addressee_id)
        OR (f2.requester_id = f1.addressee_id AND f2.addressee_id = f1.requester_id)
    )
);

-- Step 3: Update accept_friend_request to clean up any reverse pending requests
DROP FUNCTION IF EXISTS accept_friend_request(UUID);

CREATE OR REPLACE FUNCTION accept_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
    v_requester_id UUID;
    v_addressee_id UUID;
BEGIN
    -- Get the request details
    SELECT requester_id, addressee_id INTO v_requester_id, v_addressee_id
    FROM friendships
    WHERE id = request_id
    AND addressee_id = current_user_id
    AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    -- Accept this request
    UPDATE friendships
    SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id;
    
    -- Delete any reverse pending request (if they also sent us a request)
    DELETE FROM friendships
    WHERE requester_id = v_addressee_id  -- current user
    AND addressee_id = v_requester_id    -- the person who sent the request
    AND status = 'pending';
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION accept_friend_request(UUID) TO authenticated;

-- Step 4: Update decline_friend_request to DELETE the record instead of just updating status
-- This prevents "ghost" declined requests from causing issues
DROP FUNCTION IF EXISTS decline_friend_request(UUID);

CREATE OR REPLACE FUNCTION decline_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    -- Delete the request entirely (not just update status)
    DELETE FROM friendships
    WHERE id = request_id
    AND addressee_id = current_user_id
    AND status = 'pending';
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION decline_friend_request(UUID) TO authenticated;

-- Step 5: Update remove_friend to delete ALL records between the two users
-- This ensures a clean slate when unfriending
DROP FUNCTION IF EXISTS remove_friend(UUID);

CREATE OR REPLACE FUNCTION remove_friend(friendship_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
    v_other_user_id UUID;
BEGIN
    -- Get the other user's ID from the friendship
    SELECT 
        CASE 
            WHEN requester_id = current_user_id THEN addressee_id
            ELSE requester_id 
        END INTO v_other_user_id
    FROM friendships
    WHERE id = friendship_id
    AND (requester_id = current_user_id OR addressee_id = current_user_id);
    
    IF v_other_user_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Delete ALL friendship records between these two users (both directions)
    DELETE FROM friendships
    WHERE (requester_id = current_user_id AND addressee_id = v_other_user_id)
       OR (requester_id = v_other_user_id AND addressee_id = current_user_id);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION remove_friend(UUID) TO authenticated;

-- Done!
SELECT 'Friend request status fix complete!' AS status;
SELECT '- search_users now returns has_outgoing_request and has_incoming_request separately' AS info1;
SELECT '- Cleaned up declined and orphaned friendship records' AS info2;
SELECT '- accept_friend_request now cleans up reverse pending requests' AS info3;
SELECT '- decline_friend_request now deletes the record entirely' AS info4;
SELECT '- remove_friend now deletes ALL records between users' AS info5;
