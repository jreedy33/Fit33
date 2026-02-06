-- =====================================================
-- SIMPLE PUSH NOTIFICATION TRIGGER FIX
-- =====================================================
-- This version hardcodes the Edge Function URL since
-- Supabase doesn't allow setting custom database parameters
-- =====================================================

-- Your Supabase project Edge Function URL
-- This is NOT a secret - it's just a URL
DO $$
BEGIN
    RAISE NOTICE 'Setting up push notification triggers for project: ehooeghabzefgoqzugrc';
END $$;

-- Step 1: Enable pg_net extension (for HTTP calls from database)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Step 2: Create the notification trigger function with hardcoded URL
CREATE OR REPLACE FUNCTION trigger_push_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Make async HTTP POST to Edge Function
    -- The Edge Function will use its own SUPABASE_SERVICE_ROLE_KEY
    -- so we don't need to pass authentication from here
    PERFORM net.http_post(
        url := 'https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/send-push-notification',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := jsonb_build_object(
            'queue_id', NEW.id::text
        )
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Don't fail the insert if HTTP call fails
        -- The cron job will pick up pending notifications
        RAISE NOTICE 'Push notification HTTP call failed: % - will retry via cron', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create/replace trigger on push_notification_queue
DROP TRIGGER IF EXISTS trigger_send_push_notification ON push_notification_queue;
CREATE TRIGGER trigger_send_push_notification
    AFTER INSERT ON push_notification_queue
    FOR EACH ROW
    EXECUTE FUNCTION trigger_push_notification();

-- Step 4: Update friend request notification function
CREATE OR REPLACE FUNCTION queue_friend_request_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
BEGIN
    -- Only trigger for new pending friend requests
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get sender's name
    SELECT COALESCE(name, username, 'Someone') INTO sender_name
    FROM user_profiles
    WHERE id = NEW.requester_id;
    
    -- Insert into notification queue (trigger will fire automatically)
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status
    ) VALUES (
        NEW.addressee_id,
        'friend_request',
        'New Friend Request',
        sender_name || ' sent you a friend request',
        jsonb_build_object(
            'type', 'friend_request',
            'request_id', NEW.id::text,
            'sender_id', NEW.requester_id::text,
            'sender_name', sender_name
        ),
        'pending'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 5: Update friend request accepted notification function
CREATE OR REPLACE FUNCTION queue_friend_accepted_notification()
RETURNS TRIGGER AS $$
DECLARE
    accepter_name TEXT;
BEGIN
    -- Only trigger when status changes to 'accepted'
    IF OLD.status != 'pending' OR NEW.status != 'accepted' THEN
        RETURN NEW;
    END IF;
    
    -- Get accepter's name (the addressee who accepted)
    SELECT COALESCE(name, username, 'Someone') INTO accepter_name
    FROM user_profiles
    WHERE id = NEW.addressee_id;
    
    -- Notify the original requester that their request was accepted
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status
    ) VALUES (
        NEW.requester_id,
        'friend_request_accepted',
        'Friend Request Accepted',
        accepter_name || ' accepted your friend request',
        jsonb_build_object(
            'type', 'friend_request_accepted',
            'friendship_id', NEW.id::text,
            'friend_id', NEW.addressee_id::text,
            'friend_name', accepter_name
        ),
        'pending'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 6: Update shared workout notification function
CREATE OR REPLACE FUNCTION queue_shared_workout_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    workout_name TEXT;
BEGIN
    -- Get sender's name
    SELECT COALESCE(name, username, 'A friend') INTO sender_name
    FROM user_profiles
    WHERE id = NEW.sender_id;
    
    -- Get workout name
    workout_name := COALESCE(NEW.workout_name, 'a workout');
    
    -- Insert into notification queue
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status
    ) VALUES (
        NEW.recipient_id,
        'shared_workout',
        'New Workout Shared',
        sender_name || ' shared "' || workout_name || '" with you',
        jsonb_build_object(
            'type', 'shared_workout',
            'workout_id', NEW.id::text,
            'sender_id', NEW.sender_id::text,
            'sender_name', sender_name,
            'workout_name', workout_name
        ),
        'pending'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 7: Update challenge invite notification function
CREATE OR REPLACE FUNCTION queue_challenge_invite_notification()
RETURNS TRIGGER AS $$
DECLARE
    challenger_name TEXT;
    challenge_title TEXT;
BEGIN
    -- Only for new pending invites (not the creator's own entry)
    IF NEW.status != 'pending' OR NEW.is_creator = true THEN
        RETURN NEW;
    END IF;
    
    -- Get challenge details and creator name
    SELECT 
        fc.title,
        COALESCE(up.name, up.username, 'Someone')
    INTO challenge_title, challenger_name
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.is_creator = true
    JOIN user_profiles up ON up.id = cp.user_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Insert into notification queue
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status
    ) VALUES (
        NEW.user_id,
        'challenge_invite',
        'New Challenge Invite',
        challenger_name || ' challenged you to "' || COALESCE(challenge_title, 'a challenge') || '"',
        jsonb_build_object(
            'type', 'challenge_invite',
            'challenge_id', NEW.challenge_id::text,
            'challenger_name', challenger_name,
            'challenge_title', challenge_title
        ),
        'pending'
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 8: Create/replace triggers
DROP TRIGGER IF EXISTS on_friend_request_sent ON friendships;
CREATE TRIGGER on_friend_request_sent
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_notification();

DROP TRIGGER IF EXISTS on_friend_request_accepted ON friendships;
CREATE TRIGGER on_friend_request_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_accepted_notification();

DROP TRIGGER IF EXISTS on_workout_shared ON shared_workouts;
CREATE TRIGGER on_workout_shared
    AFTER INSERT ON shared_workouts
    FOR EACH ROW
    EXECUTE FUNCTION queue_shared_workout_notification();

DROP TRIGGER IF EXISTS on_challenge_invite ON challenge_participants;
CREATE TRIGGER on_challenge_invite
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION queue_challenge_invite_notification();

-- Step 9: Verify everything is set up
SELECT 'Triggers configured:' as status;

SELECT 
    trigger_name,
    event_object_table as table_name,
    action_timing || ' ' || event_manipulation as event
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND trigger_name IN (
    'trigger_send_push_notification',
    'on_friend_request_sent', 
    'on_friend_request_accepted',
    'on_workout_shared',
    'on_challenge_invite'
)
ORDER BY event_object_table;

SELECT '✅ Push notification triggers configured successfully!' as result;
SELECT 'Notifications will be sent immediately via pg_net HTTP call' as info;
SELECT 'If that fails, the cron job will pick them up' as fallback;
