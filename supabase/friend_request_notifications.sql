-- Friend Request Notification System
-- Ensures friend requests trigger push notifications
-- and that contact joined notifications don't duplicate friend requests

-- Update the send_friend_request function to queue push notifications
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
    requester_name TEXT;
    requester_username TEXT;
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
    
    -- Get requester's name for notification
    SELECT name, username INTO requester_name, requester_username
    FROM user_profiles
    WHERE id = current_user_uuid;
    
    -- Create new friend request
    INSERT INTO friendships (requester_id, addressee_id, status, message)
    VALUES (current_user_uuid, target_user_id, 'pending', request_message)
    RETURNING id INTO new_request_id;
    
    -- Queue push notification to target user
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status,
        created_at
    ) VALUES (
        target_user_id,
        'friend_request',
        COALESCE(requester_name, requester_username, 'Someone') || ' sent you a friend request',
        COALESCE(request_message, 'Tap to view'),
        jsonb_build_object(
            'type', 'friend_request',
            'request_id', new_request_id,
            'from_user_id', current_user_uuid,
            'from_user_name', COALESCE(requester_name, requester_username)
        ),
        'pending',
        NOW()
    );
    
    RAISE NOTICE 'Friend request created and notification queued: %', new_request_id;
    
    RETURN new_request_id;
END;
$$;

COMMENT ON FUNCTION send_friend_request(UUID, TEXT) IS 
  'Sends a friend request and queues a push notification to the recipient. Returns the request ID.';

GRANT EXECUTE ON FUNCTION send_friend_request(UUID, TEXT) TO authenticated;

-- Summary
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ FRIEND REQUEST NOTIFICATIONS ENABLED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 What changed:';
  RAISE NOTICE '   - send_friend_request() now queues push notifications';
  RAISE NOTICE '   - Friend requests during onboarding will notify recipients';
  RAISE NOTICE '   - Works with new account creation';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Next step:';
  RAISE NOTICE '   - Deploy updated edge function to exclude friend request';
  RAISE NOTICE '     recipients from "contact joined" notifications';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
