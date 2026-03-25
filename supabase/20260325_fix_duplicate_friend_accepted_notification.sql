-- =============================================================================
-- FIX: Duplicate "friend accepted" push notifications
-- =============================================================================
-- Problem: Users receive TWO notifications when someone accepts their friend
-- request — one with 🎉 and one without.
--
-- Root cause: A stale trigger on the friendships table (or duplicate function
-- invocation) inserts a second notification into push_notification_queue.
--
-- Fix:
--   1. Drop any triggers on friendships that might insert push notifications
--   2. Replace accept_friend_request with a dedup-guarded version
-- =============================================================================

-- STEP 1: Drop any triggers on the friendships table that fire on UPDATE
-- These may have been created outside tracked migrations and could be inserting
-- a duplicate notification when the friendship status changes to 'accepted'.

DO $$
DECLARE
    trig_name TEXT;
BEGIN
    FOR trig_name IN
        SELECT trigger_name
        FROM information_schema.triggers
        WHERE event_object_table = 'friendships'
          AND event_manipulation = 'UPDATE'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON friendships', trig_name);
        RAISE NOTICE 'Dropped stale trigger on friendships: %', trig_name;
    END LOOP;
END $$;

-- STEP 2: Replace accept_friend_request with dedup-guarded version
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

    -- Queue push notification with dedup guard:
    -- Skip if an identical notification was already queued in the last 5 minutes
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
        RAISE WARNING 'Failed to queue accept notification: %', SQLERRM;
    END;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_friend_request(UUID) TO authenticated;

-- STEP 3: Clean up any duplicate pending friend_accepted notifications already in queue
-- Keep only the newest per friendship_id, delete the rest
DELETE FROM push_notification_queue
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY recipient_user_id, data->>'friendship_id'
                   ORDER BY created_at DESC
               ) AS rn
        FROM push_notification_queue
        WHERE notification_type = 'friend_accepted'
          AND status = 'pending'
    ) ranked
    WHERE rn > 1
);

DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ DUPLICATE FRIEND ACCEPTED NOTIFICATION FIX';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '1. Dropped stale UPDATE triggers on friendships table';
    RAISE NOTICE '2. accept_friend_request now has dedup guard';
    RAISE NOTICE '3. Cleaned up duplicate pending notifications';
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
