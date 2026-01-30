-- ============================================================================
-- SENT FRIEND REQUESTS
-- Add ability to view and cancel friend requests you've sent
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
BEGIN
    RETURN QUERY
    SELECT 
        fr.id as request_id,
        fr.to_user_id,
        up.name::TEXT as to_user_name,
        up.email::TEXT as to_user_email,
        up.username::TEXT as to_user_username,
        up.profile_photo_url::TEXT as profile_photo_url,
        fr.message::TEXT as message,
        fr.created_at
    FROM friend_requests fr
    JOIN user_profiles up ON up.id = fr.to_user_id
    WHERE fr.from_user_id = auth.uid() 
      AND fr.status = 'pending'
    ORDER BY fr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_sent_friend_requests() TO authenticated;

-- Function to cancel a friend request you sent
DROP FUNCTION IF EXISTS cancel_friend_request(UUID);

CREATE OR REPLACE FUNCTION cancel_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    affected_rows INT;
BEGIN
    -- Delete the request (only if sent by current user and still pending)
    DELETE FROM friend_requests 
    WHERE id = request_id 
      AND from_user_id = auth.uid() 
      AND status = 'pending';
    
    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    
    RETURN affected_rows > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cancel_friend_request(UUID) TO authenticated;

-- Done!
SELECT 'Sent friend requests functions created!' AS status;
SELECT '- get_sent_friend_requests(): returns pending requests you sent' AS info1;
SELECT '- cancel_friend_request(request_id): cancels/unsends a request' AS info2;
