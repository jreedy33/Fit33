-- =====================================================
-- FIX PUSH NOTIFICATION TRIGGER FOR IMMEDIATE DELIVERY
-- =====================================================
-- This updates the trigger to call the Edge Function immediately
-- when a notification is queued, ensuring delivery even when
-- the app is closed or device is asleep.
-- =====================================================

-- Step 1: Enable pg_net extension for HTTP requests from triggers
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Step 2: Update the notification queue function to call Edge Function immediately
CREATE OR REPLACE FUNCTION queue_shared_workout_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    workout_name TEXT;
    queue_id UUID;
    edge_function_url TEXT;
BEGIN
    -- Get sender name from user_profiles
    SELECT COALESCE(name, 'Someone') INTO sender_name
    FROM user_profiles
    WHERE id::text = NEW.sender_id::text;
    
    -- Get workout name
    workout_name := COALESCE(NEW.workout_name, 'a workout');
    
    -- Insert into notification queue
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
        'Tap to check out "' || workout_name || '" and start training.',
        jsonb_build_object(
            'workout_id', NEW.id::text,
            'sender_name', sender_name,
            'workout_name', workout_name,
            'type', 'shared_workout'
        )
    ) RETURNING id INTO queue_id;
    
    -- Get the Edge Function URL from vault or use direct URL
    -- Replace YOUR_PROJECT_REF with your actual Supabase project reference
    edge_function_url := 'https://' || current_setting('app.settings.supabase_project_ref', true) || '.supabase.co/functions/v1/send-push-notification';
    
    -- If the setting isn't configured, use a fallback approach
    IF edge_function_url IS NULL OR edge_function_url = 'https://.supabase.co/functions/v1/send-push-notification' THEN
        -- Fallback: just log that we need to configure the URL
        RAISE NOTICE 'Edge function URL not configured. Notification queued but not sent immediately.';
    ELSE
        -- Call the Edge Function immediately via pg_net
        PERFORM net.http_post(
            url := edge_function_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.settings.supabase_service_role_key', true)
            ),
            body := jsonb_build_object('queue_id', queue_id::text)
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create similar function for friend requests
CREATE OR REPLACE FUNCTION queue_friend_request_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    queue_id UUID;
    edge_function_url TEXT;
BEGIN
    -- Only notify on new pending requests
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get sender name
    SELECT COALESCE(name, 'Someone') INTO sender_name
    FROM user_profiles
    WHERE id::text = NEW.requester_id::text;
    
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
        sender_name || ' sent you a friend request! 👋',
        'Tap to view and respond to the request.',
        jsonb_build_object(
            'type', 'friend_request',
            'sender_id', NEW.requester_id::text,
            'sender_name', sender_name,
            'friendship_id', NEW.id::text
        )
    ) RETURNING id INTO queue_id;
    
    -- Call Edge Function (same pattern as above)
    edge_function_url := 'https://' || current_setting('app.settings.supabase_project_ref', true) || '.supabase.co/functions/v1/send-push-notification';
    
    IF edge_function_url IS NOT NULL AND edge_function_url != 'https://.supabase.co/functions/v1/send-push-notification' THEN
        PERFORM net.http_post(
            url := edge_function_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.settings.supabase_service_role_key', true)
            ),
            body := jsonb_build_object('queue_id', queue_id::text)
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Create function for friend request accepted notification
CREATE OR REPLACE FUNCTION queue_friend_accepted_notification()
RETURNS TRIGGER AS $$
DECLARE
    accepter_name TEXT;
    queue_id UUID;
    edge_function_url TEXT;
BEGIN
    -- Only notify when status changes to 'accepted'
    IF NEW.status != 'accepted' OR OLD.status = 'accepted' THEN
        RETURN NEW;
    END IF;
    
    -- Get accepter name (the addressee who accepted)
    SELECT COALESCE(name, 'Someone') INTO accepter_name
    FROM user_profiles
    WHERE id::text = NEW.addressee_id::text;
    
    -- Notify the original requester that their request was accepted
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.requester_id,
        'friend_request_accepted',
        accepter_name || ' accepted your friend request! 🎉',
        'You''re now friends. Start sharing workouts!',
        jsonb_build_object(
            'type', 'friend_request_accepted',
            'friend_id', NEW.addressee_id::text,
            'friend_name', accepter_name,
            'friendship_id', NEW.id::text
        )
    ) RETURNING id INTO queue_id;
    
    -- Call Edge Function
    edge_function_url := 'https://' || current_setting('app.settings.supabase_project_ref', true) || '.supabase.co/functions/v1/send-push-notification';
    
    IF edge_function_url IS NOT NULL AND edge_function_url != 'https://.supabase.co/functions/v1/send-push-notification' THEN
        PERFORM net.http_post(
            url := edge_function_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || current_setting('app.settings.supabase_service_role_key', true)
            ),
            body := jsonb_build_object('queue_id', queue_id::text)
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 5: Create/update triggers
DROP TRIGGER IF EXISTS on_workout_shared ON shared_workouts;
CREATE TRIGGER on_workout_shared
    AFTER INSERT ON shared_workouts
    FOR EACH ROW
    EXECUTE FUNCTION queue_shared_workout_notification();

DROP TRIGGER IF EXISTS on_friend_request ON friendships;
CREATE TRIGGER on_friend_request
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_request_notification();

DROP TRIGGER IF EXISTS on_friend_accepted ON friendships;
CREATE TRIGGER on_friend_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION queue_friend_accepted_notification();

-- =====================================================
-- IMPORTANT: Configure these settings in Supabase Dashboard
-- =====================================================
-- Go to: Project Settings > Database > Database Settings
-- Add these to the "Database Settings" section under "Custom Settings":
--
-- app.settings.supabase_project_ref = 'your-project-ref'
-- app.settings.supabase_service_role_key = 'your-service-role-key'
--
-- Or set them via SQL:
-- ALTER DATABASE postgres SET app.settings.supabase_project_ref = 'your-project-ref';
-- ALTER DATABASE postgres SET app.settings.supabase_service_role_key = 'your-service-role-key';
-- =====================================================

SELECT 'Push notification triggers updated!' AS status;
SELECT 'IMPORTANT: Configure app.settings in Supabase Dashboard for immediate delivery' AS next_step;
