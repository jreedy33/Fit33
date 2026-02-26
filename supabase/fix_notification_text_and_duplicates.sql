-- ============================================================================
-- FIX: Push Notification Text & Duplicate Prevention
-- Version: 1.17.1
-- Date: 2026-02-25
--
-- 1. Fixes truncated push notification text by keeping titles short
-- 2. Adds 'processing' status to prevent duplicate sends
-- ============================================================================

-- ============================================================================
-- 1. Add 'processing' status support to push_notification_queue
-- ============================================================================
-- The edge function now claims pending notifications by setting status='processing'
-- before sending. This prevents race conditions where two concurrent invocations
-- both send the same notification.

-- Clean up any stale 'processing' records (from interrupted edge function runs)
-- Mark them back to 'pending' so they get retried
UPDATE push_notification_queue 
SET status = 'pending' 
WHERE status = 'processing' 
  AND created_at < NOW() - INTERVAL '5 minutes';

-- ============================================================================
-- 2. Fix send_friend_request notification text
--    Title: short action label (fits on 1 line)
--    Body: person's name + message (shown on 2nd line)
-- ============================================================================
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
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    IF current_user_uuid = target_user_id THEN
        RAISE EXCEPTION 'Cannot send friend request to yourself';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = target_user_id) THEN
        RAISE EXCEPTION 'Target user does not exist';
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM friendships 
        WHERE ((requester_id = current_user_uuid AND addressee_id = target_user_id)
           OR (requester_id = target_user_id AND addressee_id = current_user_uuid))
          AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'Already friends with this user';
    END IF;
    
    SELECT id INTO existing_request_id
    FROM friendships 
    WHERE ((requester_id = current_user_uuid AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_uuid))
      AND status = 'pending';
    
    IF existing_request_id IS NOT NULL THEN
        RETURN existing_request_id;
    END IF;
    
    SELECT name, username INTO requester_name, requester_username
    FROM user_profiles
    WHERE id = current_user_uuid;
    
    INSERT INTO friendships (requester_id, addressee_id, status, message)
    VALUES (current_user_uuid, target_user_id, 'pending', request_message)
    RETURNING id INTO new_request_id;
    
    -- Queue push notification — short title + descriptive body
    INSERT INTO push_notification_queue (
        recipient_user_id, notification_type, title, body, data, status, created_at
    ) VALUES (
        target_user_id,
        'friend_request',
        'New Friend Request 👋',
        COALESCE(requester_name, requester_username, 'Someone') || ' wants to be your workout buddy!',
        jsonb_build_object(
            'type', 'friend_request',
            'request_id', new_request_id,
            'from_user_id', current_user_uuid,
            'from_user_name', COALESCE(requester_name, requester_username)
        ),
        'pending',
        NOW()
    );
    
    RETURN new_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION send_friend_request(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 3. Summary
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ NOTIFICATION TEXT & DUPLICATE PREVENTION FIXED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Changes:';
  RAISE NOTICE '   - Friend request notification: short title, full body';
  RAISE NOTICE '   - Edge function uses processing status to prevent dupes';
  RAISE NOTICE '   - Stale processing records auto-recovered to pending';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
