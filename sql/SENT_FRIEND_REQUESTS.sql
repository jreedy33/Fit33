-- ============================================================================
-- SENT FRIEND REQUESTS
-- Add ability to view and cancel friend requests you've sent
-- Uses the 'friendships' table (requester_id/addressee_id) NOT 'friend_requests'
-- ============================================================================

-- Function to get friend requests sent BY the current user (outgoing/pending)
DROP FUNCTION IF EXISTS get_sent_friend_requests();

CREATE OR REPLACE FUNCTION get_sent_friend_requests()
RETURNS TABLE (
    request_id UUID,
    to_user_id UUID,
    to_user_name TEXT,
    to_user_email TEXT,
    to_user_username TEXT,
    profile_photo_url TEXT,
    message TEXT,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.addressee_id as to_user_id,
        up.name as to_user_name,
        u.email::TEXT as to_user_email,
        up.username as to_user_username,
        up.profile_photo_url,
        f.message,
        f.created_at
    FROM friendships f
    JOIN auth.users u ON u.id = f.addressee_id
    LEFT JOIN user_profiles up ON up.id::TEXT = f.addressee_id::TEXT
    WHERE f.requester_id = current_user_uuid
      AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_sent_friend_requests() TO authenticated;

-- Function to cancel a friend request you sent
DROP FUNCTION IF EXISTS cancel_friend_request(UUID);

CREATE OR REPLACE FUNCTION cancel_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    -- Delete the request (only if sent by current user and still pending)
    DELETE FROM friendships 
    WHERE id = request_id 
      AND requester_id = current_user_uuid
      AND status = 'pending';
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cancel_friend_request(UUID) TO authenticated;

-- Done!
SELECT 'Sent friend requests functions created!' AS status;
SELECT '- get_sent_friend_requests(): returns pending requests you sent (from friendships table)' AS info1;
SELECT '- cancel_friend_request(request_id): cancels/unsends a request' AS info2;
