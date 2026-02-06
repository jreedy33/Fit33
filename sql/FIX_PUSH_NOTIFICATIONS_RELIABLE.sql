-- =====================================================
-- RELIABLE PUSH NOTIFICATION DELIVERY FIX
-- =====================================================
-- 
-- PROBLEM IDENTIFIED: Push notifications are being queued but not delivered
-- reliably because:
-- 1. pg_notify doesn't trigger Edge Functions automatically
-- 2. app.settings.supabase_project_ref is not configured
-- 3. No scheduled job to process pending notifications
--
-- SOLUTION: Use Supabase's built-in webhook trigger via pg_net
-- =====================================================

-- Step 1: Enable pg_net extension
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Step 2: Create a simplified, reliable notification trigger function
-- This directly calls the Edge Function via HTTP

CREATE OR REPLACE FUNCTION trigger_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_url TEXT;
    v_service_key TEXT;
BEGIN
    -- Get the Edge Function URL from environment
    -- Format: https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notification
    v_url := current_setting('app.settings.edge_function_url', true);
    v_service_key := current_setting('app.settings.service_role_key', true);
    
    -- If settings not configured, log and return (don't block the insert)
    IF v_url IS NULL OR v_url = '' THEN
        RAISE NOTICE 'Push notification URL not configured - notification queued for batch processing';
        RETURN NEW;
    END IF;
    
    -- Make async HTTP POST to Edge Function
    PERFORM net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || COALESCE(v_service_key, '')
        ),
        body := jsonb_build_object(
            'queue_id', NEW.id::text,
            'recipient_user_id', NEW.recipient_user_id::text,
            'notification_type', NEW.notification_type,
            'title', NEW.title,
            'body', NEW.body,
            'data', NEW.data
        )
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Don't fail the insert if notification fails
        RAISE NOTICE 'Push notification trigger failed: % - will retry in batch', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create trigger on push_notification_queue
DROP TRIGGER IF EXISTS trigger_send_push_notification ON push_notification_queue;
CREATE TRIGGER trigger_send_push_notification
    AFTER INSERT ON push_notification_queue
    FOR EACH ROW
    EXECUTE FUNCTION trigger_push_notification();

-- Step 4: Create Supabase Webhook alternative (more reliable)
-- This uses Supabase's database webhooks feature instead of custom triggers

-- Create a view that Supabase webhooks can subscribe to
CREATE OR REPLACE VIEW pending_notifications_webhook AS
SELECT 
    pnq.id as queue_id,
    pnq.recipient_user_id,
    upt.device_token,
    pnq.notification_type,
    pnq.title,
    pnq.body,
    pnq.data,
    pnq.created_at
FROM push_notification_queue pnq
JOIN user_push_tokens upt ON upt.user_id = pnq.recipient_user_id
WHERE pnq.status = 'pending'
ORDER BY pnq.created_at ASC
LIMIT 100;

-- Step 5: Update all notification trigger functions to use consistent pattern
-- Friend Request Notification
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
    
    -- Get sender's name and username
    SELECT 
        COALESCE(up.name, 'Someone'),
        up.username
    INTO sender_name, sender_username
    FROM user_profiles up
    WHERE up.id = NEW.requester_id;
    
    -- Build display name
    IF sender_name IS NOT NULL AND sender_name != 'Someone' THEN
        display_name := sender_name;
    ELSIF sender_username IS NOT NULL AND sender_username != '' THEN
        display_name := '@' || sender_username;
    ELSE
        display_name := 'Someone';
    END IF;
    
    -- Insert into notification queue (trigger will handle delivery)
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
        'Tap to view and respond.',
        jsonb_build_object(
            'type', 'friend_request',
            'friendship_id', NEW.id::text,
            'sender_id', NEW.requester_id::text,
            'sender_name', display_name
        )
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Friend request notification failed: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Friend Request Accepted Notification
CREATE OR REPLACE FUNCTION queue_friend_request_accepted_notification()
RETURNS TRIGGER AS $$
DECLARE
    accepter_name TEXT;
    accepter_username TEXT;
    display_name TEXT;
BEGIN
    -- Only trigger when status changes from 'pending' to 'accepted'
    IF OLD.status != 'pending' OR NEW.status != 'accepted' THEN
        RETURN NEW;
    END IF;
    
    -- Get accepter's name
    SELECT 
        COALESCE(up.name, 'Someone'),
        up.username
    INTO accepter_name, accepter_username
    FROM user_profiles up
    WHERE up.id = NEW.addressee_id;
    
    -- Build display name
    IF accepter_name IS NOT NULL AND accepter_name != 'Someone' THEN
        display_name := accepter_name;
    ELSIF accepter_username IS NOT NULL AND accepter_username != '' THEN
        display_name := '@' || accepter_username;
    ELSE
        display_name := 'Someone';
    END IF;
    
    -- Notify the original requester
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.requester_id,
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
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Friend accepted notification failed: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Shared Workout Notification
CREATE OR REPLACE FUNCTION queue_shared_workout_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    workout_name TEXT;
BEGIN
    -- Get sender name
    SELECT COALESCE(up.name, 'Someone') 
    INTO sender_name
    FROM user_profiles up
    WHERE up.id = NEW.sender_id;
    
    workout_name := COALESCE(NEW.workout_name, 'a workout');
    
    -- Queue the notification
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.recipient_id,
        'shared_workout',
        sender_name || ' sent you a workout! 💪',
        'Tap to check out "' || workout_name || '"',
        jsonb_build_object(
            'type', 'shared_workout',
            'workout_id', NEW.id::text,
            'sender_name', sender_name,
            'workout_name', workout_name
        )
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Shared workout notification failed: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Challenge Invite Notification
CREATE OR REPLACE FUNCTION queue_challenge_invite_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_sender_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Only for pending invites (not creator's auto-accepted entry)
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get sender name
    SELECT COALESCE(up.name, 'Someone') 
    INTO v_sender_name
    FROM friend_challenges fc
    JOIN user_profiles up ON up.id = fc.creator_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Get challenge title
    SELECT title INTO v_challenge_title
    FROM friend_challenges
    WHERE id = NEW.challenge_id;
    
    -- Queue notification
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.user_id,
        'challenge_invite',
        v_sender_name || ' wants to challenge you! 🏆',
        'Tap to check out "' || COALESCE(v_challenge_title, 'New Challenge') || '"',
        jsonb_build_object(
            'type', 'challenge_invite',
            'challenge_id', NEW.challenge_id::TEXT,
            'sender_name', v_sender_name,
            'challenge_title', v_challenge_title
        )
    );
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Challenge invite notification failed: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 6: Recreate all triggers with consistent naming
DROP TRIGGER IF EXISTS on_friend_request_sent ON friendships;
DROP TRIGGER IF EXISTS on_friend_request ON friendships;
CREATE TRIGGER on_friend_request_sent
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_notification();

DROP TRIGGER IF EXISTS on_friend_request_accepted ON friendships;
DROP TRIGGER IF EXISTS on_friend_accepted ON friendships;
CREATE TRIGGER on_friend_request_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_accepted_notification();

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

-- Step 7: Create batch processing function for fallback
-- This handles notifications that weren't delivered immediately

CREATE OR REPLACE FUNCTION process_pending_notifications_batch()
RETURNS TABLE(
    total_pending INTEGER,
    processed INTEGER,
    no_token INTEGER
) AS $$
DECLARE
    v_total INTEGER;
    v_processed INTEGER := 0;
    v_no_token INTEGER := 0;
    v_url TEXT;
    v_service_key TEXT;
    v_notification RECORD;
BEGIN
    v_url := current_setting('app.settings.edge_function_url', true);
    v_service_key := current_setting('app.settings.service_role_key', true);
    
    -- Count pending
    SELECT COUNT(*) INTO v_total 
    FROM push_notification_queue 
    WHERE status = 'pending';
    
    -- Process each pending notification
    FOR v_notification IN
        SELECT 
            pnq.*,
            upt.device_token
        FROM push_notification_queue pnq
        LEFT JOIN user_push_tokens upt ON upt.user_id = pnq.recipient_user_id
        WHERE pnq.status = 'pending'
        AND pnq.created_at > NOW() - INTERVAL '24 hours'  -- Only last 24h
        ORDER BY pnq.created_at ASC
        LIMIT 100
    LOOP
        IF v_notification.device_token IS NULL THEN
            -- No device token - mark as skipped
            UPDATE push_notification_queue 
            SET status = 'skipped', 
                error_message = 'No device token'
            WHERE id = v_notification.id;
            v_no_token := v_no_token + 1;
        ELSIF v_url IS NOT NULL AND v_url != '' THEN
            -- Try to send via Edge Function
            BEGIN
                PERFORM net.http_post(
                    url := v_url,
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || COALESCE(v_service_key, '')
                    ),
                    body := jsonb_build_object(
                        'queue_id', v_notification.id::text,
                        'recipient_user_id', v_notification.recipient_user_id::text,
                        'device_token', v_notification.device_token,
                        'notification_type', v_notification.notification_type,
                        'title', v_notification.title,
                        'body', v_notification.body,
                        'data', v_notification.data
                    )
                );
                v_processed := v_processed + 1;
            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Failed to process notification %: %', v_notification.id, SQLERRM;
            END;
        END IF;
    END LOOP;
    
    RETURN QUERY SELECT v_total, v_processed, v_no_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION process_pending_notifications_batch() TO service_role;

-- Step 8: Verify triggers are active
-- Using direct pg_trigger query to check enabled status
SELECT 
    t.trigger_name,
    t.event_object_table,
    t.action_timing || ' ' || t.event_manipulation as trigger_event,
    CASE WHEN pg.tgenabled != 'D' THEN '✅ ENABLED' ELSE '❌ DISABLED' END as status
FROM information_schema.triggers t
LEFT JOIN pg_trigger pg ON pg.tgname = t.trigger_name::TEXT
LEFT JOIN pg_class c ON pg.tgrelid = c.oid AND c.relname = t.event_object_table::TEXT
LEFT JOIN pg_namespace n ON c.relnamespace = n.oid AND n.nspname = t.event_object_schema::TEXT
WHERE t.event_object_schema = 'public'
AND t.trigger_name LIKE 'on_%'
ORDER BY t.event_object_table;

-- =====================================================
-- SETUP INSTRUCTIONS
-- =====================================================
/*
After running this SQL, you need to:

1. Go to Supabase Dashboard > Settings > Database
2. Add these configuration parameters:
   - app.settings.edge_function_url = 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notification'
   - app.settings.service_role_key = 'your-service-role-key'

OR run this SQL (replace with your values):

ALTER DATABASE postgres SET app.settings.edge_function_url = 'https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notification';
ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_SERVICE_ROLE_KEY';

3. Deploy the Edge Function (send-push-notification) if not already deployed

4. Enable pg_cron and schedule the batch processor:
   SELECT cron.schedule('process-notifications', '* * * * *', 
     $$SELECT * FROM process_pending_notifications_batch()$$);
*/

SELECT 'Push notification reliability fix applied!' AS status;
SELECT 'Remember to configure app.settings in Supabase Dashboard' AS next_step;
