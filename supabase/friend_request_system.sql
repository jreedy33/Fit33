-- Friend Request System
-- Ensures friend requests sent during onboarding show up correctly
-- and that all friendship data is properly managed

-- Drop existing functions first to avoid type conflicts
DROP FUNCTION IF EXISTS get_sent_friend_requests();
DROP FUNCTION IF EXISTS get_pending_friend_requests();
DROP FUNCTION IF EXISTS send_friend_request(UUID, TEXT);
DROP FUNCTION IF EXISTS accept_friend_request(UUID);
DROP FUNCTION IF EXISTS reject_friend_request(UUID);

-- Function to get sent friend requests (outgoing requests the user has sent)
CREATE OR REPLACE FUNCTION get_sent_friend_requests()
RETURNS TABLE (
    request_id UUID,
    to_user_id UUID,
    to_user_name TEXT,
    to_user_username TEXT,
    to_user_profile_photo_url TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    message TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return sent friend requests (where current user is the requester)
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.addressee_id as to_user_id,
        up.name as to_user_name,
        up.username as to_user_username,
        up.profile_photo_url as to_user_profile_photo_url,
        f.status::TEXT as status,
        f.created_at,
        f.message as message
    FROM friendships f
    JOIN user_profiles up ON up.id = f.addressee_id
    WHERE f.requester_id = current_user_uuid
      AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_sent_friend_requests() IS 
  'Returns all pending friend requests sent by the current user. Shows up in "Sent Requests" section.';

GRANT EXECUTE ON FUNCTION get_sent_friend_requests() TO authenticated;

-- Function to get pending friend requests (incoming requests to the user)
CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    from_user_username TEXT,
    from_user_profile_photo_url TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    message TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return pending friend requests (where current user is the addressee)
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.requester_id as from_user_id,
        up.name as from_user_name,
        up.username as from_user_username,
        up.profile_photo_url as from_user_profile_photo_url,
        f.status::TEXT as status,
        f.created_at,
        f.message as message
    FROM friendships f
    JOIN user_profiles up ON up.id = f.requester_id
    WHERE f.addressee_id = current_user_uuid
      AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_pending_friend_requests() IS 
  'Returns all pending friend requests received by the current user. Shows up in "Requests" section.';

GRANT EXECUTE ON FUNCTION get_pending_friend_requests() TO authenticated;

-- Function to send a friend request
CREATE OR REPLACE FUNCTION send_friend_request(
    target_user_id UUID,
    request_message TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    new_request_id UUID;
    existing_request_id UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Can't send request to yourself
    IF current_user_uuid = target_user_id THEN
        RAISE EXCEPTION 'Cannot send friend request to yourself';
    END IF;
    
    -- Check if target user exists
    IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = target_user_id) THEN
        RAISE EXCEPTION 'Target user does not exist';
    END IF;
    
    -- Check if already friends (accepted friendship exists)
    IF EXISTS (
        SELECT 1 FROM friendships 
        WHERE ((requester_id = current_user_uuid AND addressee_id = target_user_id)
           OR (requester_id = target_user_id AND addressee_id = current_user_uuid))
          AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'Already friends with this user';
    END IF;
    
    -- Check if a pending request already exists (either direction)
    SELECT id INTO existing_request_id
    FROM friendships 
    WHERE ((requester_id = current_user_uuid AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_uuid))
      AND status = 'pending';
    
    IF existing_request_id IS NOT NULL THEN
        -- If request already exists, return its ID (treat as success)
        RAISE NOTICE 'Friend request already exists with ID: %', existing_request_id;
        RETURN existing_request_id;
    END IF;
    
    -- Create new friend request
    INSERT INTO friendships (requester_id, addressee_id, status, message)
    VALUES (current_user_uuid, target_user_id, 'pending', request_message)
    RETURNING id INTO new_request_id;
    
    -- TODO: Queue push notification to target user
    -- This would insert into push_notification_queue table
    
    RETURN new_request_id;
END;
$$;

COMMENT ON FUNCTION send_friend_request(UUID, TEXT) IS 
  'Sends a friend request to another user. Returns the request ID. Can be called during onboarding.';

GRANT EXECUTE ON FUNCTION send_friend_request(UUID, TEXT) TO authenticated;

-- Function to accept a friend request
CREATE OR REPLACE FUNCTION accept_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
    accepter_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Get the request
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Friend request not found or already processed';
    END IF;
    
    -- Verify current user is the addressee (recipient)
    IF request_record.addressee_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only accept requests sent to you';
    END IF;
    
    -- Accept the request
    UPDATE friendships
    SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id;
    
    -- Get accepter's display name for the notification
    SELECT COALESCE(name, username, 'Someone') INTO accepter_name
    FROM user_profiles
    WHERE id = current_user_uuid;
    
    -- Queue push notification to the original requester
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            request_record.requester_id,
            'friend_accepted',
            'Friend Request Accepted 🎉',
            accepter_name || ' accepted your friend request!',
            jsonb_build_object(
                'type', 'friend_accepted',
                'friendship_id', request_id::TEXT,
                'friend_id', current_user_uuid::TEXT
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue accept notification: %', SQLERRM;
    END;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_friend_request(UUID) TO authenticated;

-- Function to reject/cancel a friend request
CREATE OR REPLACE FUNCTION reject_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Get the request
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Friend request not found';
    END IF;
    
    -- Can reject if you're the addressee OR cancel if you're the requester
    IF request_record.addressee_id != current_user_uuid 
       AND request_record.requester_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only reject/cancel your own requests';
    END IF;
    
    -- Delete the request
    DELETE FROM friendships WHERE id = request_id;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_friend_request(UUID) TO authenticated;

-- Summary
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ FRIEND REQUEST SYSTEM CONFIGURED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Friend requests sent during onboarding:';
  RAISE NOTICE '   - Show up in "Sent Requests" section';
  RAISE NOTICE '   - Status = pending';
  RAISE NOTICE '   - Visible immediately after account creation';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Available functions:';
  RAISE NOTICE '   - send_friend_request(user_id, message)';
  RAISE NOTICE '   - get_sent_friend_requests()';
  RAISE NOTICE '   - get_pending_friend_requests()';
  RAISE NOTICE '   - accept_friend_request(request_id)';
  RAISE NOTICE '   - reject_friend_request(request_id)';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
