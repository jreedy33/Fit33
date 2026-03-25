-- Fix: "friend accepted" only went to push_notification_queue, never to
-- app_notifications.  The requester never saw an in-app notification.
-- This adds the app_notifications insert alongside the existing push queue insert.

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

    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Friend request not found or already processed';
    END IF;

    IF request_record.addressee_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only accept requests sent to you';
    END IF;

    UPDATE friendships
    SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id;

    SELECT COALESCE(name, username, 'Someone') INTO accepter_name
    FROM user_profiles
    WHERE id = current_user_uuid;

    -- Queue push notification with dedup guard
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM push_notification_queue
            WHERE recipient_user_id = request_record.requester_id
              AND notification_type = 'friend_accepted'
              AND data->>'friendship_id' = request_id::TEXT
              AND created_at > NOW() - INTERVAL '5 minutes'
        ) THEN
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
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue accept push notification: %', SQLERRM;
    END;

    -- Insert in-app notification so it appears in the notification feed
    BEGIN
        INSERT INTO app_notifications (
            user_id, notification_type, reference_id, from_user_id, title, body, is_read, created_at
        ) VALUES (
            request_record.requester_id,
            'friend_request_accepted',
            request_id,
            current_user_uuid,
            'Friend Request Accepted',
            accepter_name || ' accepted your friend request!',
            FALSE,
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to insert app_notification for accept: %', SQLERRM;
    END;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_friend_request(UUID) TO authenticated;
