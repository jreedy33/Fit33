-- ============================================================================
-- PUSH NOTIFICATIONS FOR FRIEND REQUESTS
-- ============================================================================
-- This SQL adds real-time push notifications when someone sends a friend request
-- Notification: "[Name] sent you a friend request!"
-- ============================================================================

-- ============================================================================
-- STEP 1: Create function to queue friend request notification
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_friend_request_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    sender_username TEXT;
    display_name TEXT;
BEGIN
    -- Only trigger for new pending friend requests
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get sender's name and username from user_profiles
    SELECT 
        COALESCE(up.name, 'Someone'),
        up.username
    INTO sender_name, sender_username
    FROM user_profiles up
    WHERE up.id::text = NEW.requester_id::text;
    
    -- Fallback if no profile found
    IF sender_name IS NULL THEN
        sender_name := 'Someone';
    END IF;
    
    -- Build display name (prefer name, fallback to @username)
    IF sender_name IS NOT NULL AND sender_name != 'Someone' THEN
        display_name := sender_name;
    ELSIF sender_username IS NOT NULL AND sender_username != '' THEN
        display_name := '@' || sender_username;
    ELSE
        display_name := 'Someone';
    END IF;
    
    -- Insert into notification queue
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.addressee_id,
        'friend_request',
        display_name || ' sent you a friend request! 👋',
        'Tap to view and respond to the request.',
        jsonb_build_object(
            'type', 'friend_request',
            'friendship_id', NEW.id::text,
            'sender_id', NEW.requester_id::text,
            'sender_name', display_name
        )
    );
    
    -- Log for debugging
    RAISE NOTICE 'Friend request notification queued: % -> %', NEW.requester_id, NEW.addressee_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STEP 2: Create trigger on friendships table
-- ============================================================================

-- Drop existing trigger if exists (safe to re-run)
DROP TRIGGER IF EXISTS on_friend_request_sent ON friendships;

-- Create the trigger - fires after a new friendship row is inserted
CREATE TRIGGER on_friend_request_sent
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_notification();

-- ============================================================================
-- STEP 3: Grant permissions
-- ============================================================================

-- Ensure the queue table is accessible
GRANT INSERT ON push_notification_queue TO authenticated;

-- ============================================================================
-- VERIFICATION: Test the trigger
-- ============================================================================

-- Run this query to verify the trigger exists:
-- SELECT trigger_name, event_manipulation, action_statement 
-- FROM information_schema.triggers 
-- WHERE trigger_name = 'on_friend_request_sent';

-- Check pending notifications:
-- SELECT * FROM push_notification_queue WHERE notification_type = 'friend_request' ORDER BY created_at DESC LIMIT 10;

-- ============================================================================
-- OPTIONAL: Also notify when friend request is ACCEPTED
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_friend_request_accepted_notification()
RETURNS TRIGGER AS $$
DECLARE
    accepter_name TEXT;
    accepter_username TEXT;
    display_name TEXT;
BEGIN
    -- Only trigger when status changes from 'pending' to 'accepted'
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        
        -- Get accepter's name (the addressee who accepted)
        SELECT 
            COALESCE(up.name, 'Someone'),
            up.username
        INTO accepter_name, accepter_username
        FROM user_profiles up
        WHERE up.id::text = NEW.addressee_id::text;
        
        -- Build display name
        IF accepter_name IS NOT NULL AND accepter_name != 'Someone' THEN
            display_name := accepter_name;
        ELSIF accepter_username IS NOT NULL AND accepter_username != '' THEN
            display_name := '@' || accepter_username;
        ELSE
            display_name := 'Someone';
        END IF;
        
        -- Notify the original requester that their request was accepted
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data
        ) VALUES (
            NEW.requester_id,  -- Notify the person who sent the original request
            'friend_request_accepted',
            display_name || ' accepted your friend request! 🎉',
            'You''re now friends. Start sharing workouts!',
            jsonb_build_object(
                'type', 'friend_request_accepted',
                'friendship_id', NEW.id::text,
                'friend_id', NEW.addressee_id::text,
                'friend_name', display_name
            )
        );
        
        RAISE NOTICE 'Friend request accepted notification queued: % accepted request from %', NEW.addressee_id, NEW.requester_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS on_friend_request_accepted ON friendships;

-- Create the trigger for accepted requests
CREATE TRIGGER on_friend_request_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_accepted_notification();

-- ============================================================================
-- SUMMARY OF NOTIFICATIONS
-- ============================================================================
-- 
-- 1. FRIEND REQUEST SENT (on INSERT to friendships with status='pending')
--    - Recipient: addressee_id (person receiving the request)
--    - Title: "[Name] sent you a friend request! 👋"
--    - Body: "Tap to view and respond to the request."
--    - notification_type: 'friend_request'
--
-- 2. FRIEND REQUEST ACCEPTED (on UPDATE when status changes to 'accepted')
--    - Recipient: requester_id (person who originally sent the request)
--    - Title: "[Name] accepted your friend request! 🎉"
--    - Body: "You're now friends. Start sharing workouts!"
--    - notification_type: 'friend_request_accepted'
--
-- Both notifications are queued in push_notification_queue and processed
-- by the existing send-push-notification Edge Function.
-- ============================================================================
