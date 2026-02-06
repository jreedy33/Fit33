-- =====================================================================
-- 🔧 COMPLETE NOTIFICATION PIPELINE FIX
-- =====================================================================
-- This file fixes the ENTIRE notification pipeline to ensure ALL
-- notification types are properly delivered via push notifications.
--
-- Run this ENTIRE file in Supabase SQL Editor to fix notifications.
-- =====================================================================

-- =====================================================================
-- STEP 1: ENSURE push_notification_queue HAS ALL REQUIRED COLUMNS
-- =====================================================================
SELECT '1. Updating push_notification_queue schema...' AS status;

-- Add retry columns if they don't exist
ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS retry_count INTEGER DEFAULT 0;

ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

ALTER TABLE push_notification_queue 
ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

-- Add is_valid to user_push_tokens if not exists
ALTER TABLE user_push_tokens 
ADD COLUMN IF NOT EXISTS is_valid BOOLEAN DEFAULT true;

-- Create indexes for efficient processing
CREATE INDEX IF NOT EXISTS idx_push_queue_pending 
ON push_notification_queue(status, created_at) 
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_push_queue_retry 
ON push_notification_queue(next_retry_at) 
WHERE status = 'pending' AND next_retry_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_push_queue_recipient 
ON push_notification_queue(recipient_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_tokens_valid 
ON user_push_tokens(user_id) 
WHERE is_valid = true;

-- =====================================================================
-- STEP 2: CREATE THE UNIVERSAL PUSH QUEUE TRIGGER FUNCTION
-- This trigger fires on ALL app_notifications and queues them for push
-- =====================================================================
SELECT '2. Creating universal push queue trigger function...' AS status;

CREATE OR REPLACE FUNCTION queue_push_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_from_user_name TEXT;
BEGIN
    -- Skip if this is a read/update (not a new notification)
    IF TG_OP != 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Get the sender's name if from_user_id is provided
    IF NEW.from_user_id IS NOT NULL THEN
        SELECT COALESCE(name, username, 'Someone') 
        INTO v_from_user_name
        FROM user_profiles 
        WHERE id = NEW.from_user_id;
    END IF;
    
    -- Queue the push notification
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status,
        created_at
    ) VALUES (
        NEW.user_id,
        NEW.notification_type,
        NEW.title,
        NEW.body,
        jsonb_build_object(
            'notification_id', NEW.id::text,
            'notification_type', NEW.notification_type,
            'reference_id', COALESCE(NEW.reference_id::text, ''),
            'from_user_id', COALESCE(NEW.from_user_id::text, ''),
            'from_user_name', COALESCE(v_from_user_name, '')
        ),
        'pending',
        NOW()
    );
    
    -- Log for debugging
    RAISE NOTICE '📬 Queued push notification: type=%, user=%, title=%', 
        NEW.notification_type, NEW.user_id, NEW.title;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Don't fail the original insert if push queue fails
    RAISE WARNING '⚠️ Failed to queue push notification: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================================
-- STEP 3: CREATE/REPLACE THE TRIGGER ON app_notifications
-- =====================================================================
SELECT '3. Creating trigger on app_notifications...' AS status;

-- Drop existing trigger if exists (to recreate with correct definition)
DROP TRIGGER IF EXISTS trigger_queue_push_notification ON app_notifications;

-- Create the new trigger
CREATE TRIGGER trigger_queue_push_notification
    AFTER INSERT ON app_notifications
    FOR EACH ROW
    EXECUTE FUNCTION queue_push_notification();

-- =====================================================================
-- STEP 4: FIX THE send_friend_request FUNCTION
-- Ensure it creates app_notifications (which will trigger push)
-- =====================================================================
SELECT '4. Fixing send_friend_request function...' AS status;

CREATE OR REPLACE FUNCTION send_friend_request(target_user_id UUID, request_message TEXT DEFAULT NULL)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    friendship_id UUID
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
    v_requester_name TEXT;
    v_friendship_id UUID;
    v_existing_status TEXT;
BEGIN
    -- Get requester's name
    SELECT COALESCE(name, username, 'Someone') INTO v_requester_name
    FROM user_profiles WHERE id = current_user_id;
    
    -- Check for existing friendship
    SELECT id, status INTO v_friendship_id, v_existing_status
    FROM friendships
    WHERE (requester_id = current_user_id AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_id);
    
    IF v_existing_status = 'accepted' THEN
        RETURN QUERY SELECT false, 'Already friends'::TEXT, v_friendship_id;
        RETURN;
    END IF;
    
    IF v_existing_status = 'pending' THEN
        RETURN QUERY SELECT false, 'Request already pending'::TEXT, v_friendship_id;
        RETURN;
    END IF;
    
    -- Delete any declined/blocked records to allow fresh request
    IF v_friendship_id IS NOT NULL THEN
        DELETE FROM friendships WHERE id = v_friendship_id;
    END IF;
    
    -- Create new friend request
    INSERT INTO friendships (requester_id, addressee_id, status, message)
    VALUES (current_user_id, target_user_id, 'pending', request_message)
    RETURNING id INTO v_friendship_id;
    
    -- Create notification for recipient (this triggers push notification)
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        target_user_id,
        'friend_request_received',
        v_friendship_id,
        current_user_id,
        'New Friend Request! 👋',
        v_requester_name || ' wants to be your workout buddy.',
        false
    );
    
    RETURN QUERY SELECT true, 'Friend request sent'::TEXT, v_friendship_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================================
-- STEP 5: FIX THE accept_friend_request FUNCTION
-- =====================================================================
SELECT '5. Fixing accept_friend_request function...' AS status;

CREATE OR REPLACE FUNCTION accept_friend_request(p_friendship_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_requester_id UUID;
    v_addressee_id UUID;
    v_accepter_name TEXT;
    v_current_user UUID := auth.uid();
BEGIN
    -- Get friendship details
    SELECT requester_id, addressee_id INTO v_requester_id, v_addressee_id
    FROM friendships 
    WHERE id = p_friendship_id AND status = 'pending';
    
    -- Verify the current user is the addressee
    IF v_addressee_id != v_current_user THEN
        RAISE EXCEPTION 'Not authorized to accept this request';
    END IF;
    
    -- Update friendship status
    UPDATE friendships 
    SET status = 'accepted', updated_at = NOW()
    WHERE id = p_friendship_id;
    
    -- Get accepter's name
    SELECT COALESCE(name, username, 'Someone') INTO v_accepter_name
    FROM user_profiles WHERE id = v_current_user;
    
    -- Notify the original requester that their request was accepted
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        v_requester_id,
        'friend_request_accepted',
        p_friendship_id,
        v_current_user,
        v_accepter_name || ' accepted your request! 🎉',
        'You''re now workout buddies. Start training together!',
        false
    );
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================================
-- STEP 6: FIX CHALLENGE INVITE TRIGGER
-- =====================================================================
SELECT '6. Fixing challenge invite notification trigger...' AS status;

CREATE OR REPLACE FUNCTION queue_challenge_invite_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_challenger_name TEXT;
    v_challenge_title TEXT;
    v_creator_user_id UUID;
BEGIN
    -- Only process pending invites for non-creators
    IF NEW.status != 'pending' OR NEW.is_creator = true THEN
        RETURN NEW;
    END IF;
    
    -- Get challenge info
    SELECT 
        fc.title,
        COALESCE(up.name, up.username, 'Someone'),
        cp.user_id
    INTO v_challenge_title, v_challenger_name, v_creator_user_id
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.is_creator = true
    JOIN user_profiles up ON up.id = cp.user_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Create app notification (which triggers push via the universal trigger)
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        NEW.user_id,
        'challenge_invite',
        NEW.challenge_id,
        v_creator_user_id,
        'New Challenge Invite 🏆',
        v_challenger_name || ' challenged you to "' || COALESCE(v_challenge_title, 'a challenge') || '"',
        false
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS on_challenge_invite ON challenge_participants;
CREATE TRIGGER on_challenge_invite
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION queue_challenge_invite_notification();

-- =====================================================================
-- STEP 7: FIX respond_to_challenge FUNCTION
-- =====================================================================
SELECT '7. Fixing respond_to_challenge function...' AS status;

CREATE OR REPLACE FUNCTION respond_to_challenge(p_challenge_id UUID, p_accept BOOLEAN)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_all_accepted BOOLEAN;
    v_creator_id UUID;
    v_responder_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Verify pending invite exists
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = p_challenge_id 
        AND user_id = v_current_user_id 
        AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'No pending invite found';
    END IF;
    
    -- Get challenge info
    SELECT 
        cp.user_id,
        COALESCE(up.name, up.username, 'Someone'),
        fc.title
    INTO v_creator_id, v_responder_name, v_challenge_title
    FROM challenge_participants cp
    JOIN user_profiles up ON up.id = v_current_user_id
    JOIN friend_challenges fc ON fc.id = p_challenge_id
    WHERE cp.challenge_id = p_challenge_id AND cp.is_creator = true;
    
    -- Update participant status
    UPDATE challenge_participants
    SET 
        status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        responded_at = NOW(),
        joined_at = CASE WHEN p_accept THEN NOW() ELSE NULL END
    WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id;
    
    -- Notify the challenger of the response
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        v_creator_id,
        CASE WHEN p_accept THEN 'challenge_accepted' ELSE 'challenge_declined' END,
        p_challenge_id,
        v_current_user_id,
        CASE WHEN p_accept THEN 'Challenge Accepted! ⚔️' ELSE 'Challenge Declined' END,
        v_responder_name || CASE 
            WHEN p_accept THEN ' accepted your "' || COALESCE(v_challenge_title, 'Challenge') || '" challenge!'
            ELSE ' declined your "' || COALESCE(v_challenge_title, 'Challenge') || '" challenge'
        END,
        false
    );
    
    -- If accepted, check if all participants have accepted to start the challenge
    IF p_accept THEN
        SELECT NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = p_challenge_id AND status = 'pending'
        ) INTO v_all_accepted;
        
        IF v_all_accepted THEN
            UPDATE friend_challenges
            SET 
                status = 'active',
                start_date = CURRENT_DATE,
                end_date = CURRENT_DATE + (end_date - start_date),
                updated_at = NOW()
            WHERE id = p_challenge_id 
            AND status = 'pending';
        END IF;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================================
-- STEP 8: FIX CONTACT JOINED NOTIFICATION
-- =====================================================================
SELECT '8. Fixing contact joined notification trigger...' AS status;

CREATE OR REPLACE FUNCTION queue_contact_joined_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Create app notification (which triggers push via universal trigger)
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        NEW.recipient_id,
        'contact_joined',
        NEW.new_user_id,
        NEW.new_user_id,
        'Contact Joined Fit33! 🎉',
        COALESCE(NEW.new_user_name, 'Someone from your contacts') || ' just joined Fit33. Add them as a friend!',
        false
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_contact_joined_notification ON contact_joined_notifications;
CREATE TRIGGER trigger_contact_joined_notification
    AFTER INSERT ON contact_joined_notifications
    FOR EACH ROW
    EXECUTE FUNCTION queue_contact_joined_notification();

-- =====================================================================
-- STEP 9: SET UP CRON JOB (if pg_cron is enabled)
-- =====================================================================
SELECT '9. Setting up cron job for push notification processing...' AS status;

-- Remove existing job if exists
SELECT cron.unschedule('process-push-notifications')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-push-notifications');

-- Schedule new job to run every minute
SELECT cron.schedule(
    'process-push-notifications',
    '* * * * *',  -- Every minute
    $$
    SELECT net.http_post(
        url := 'https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/send-push-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('supabase.service_role_key', true)
        ),
        body := '{"batch": true}'::jsonb
    )
    WHERE EXISTS (
        SELECT 1 FROM push_notification_queue 
        WHERE status = 'pending' 
        AND (next_retry_at IS NULL OR next_retry_at <= NOW())
        LIMIT 1
    );
    $$
);

-- =====================================================================
-- STEP 10: GRANT PERMISSIONS
-- =====================================================================
SELECT '10. Granting permissions...' AS status;

GRANT EXECUTE ON FUNCTION send_friend_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION accept_friend_request(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION respond_to_challenge(UUID, BOOLEAN) TO authenticated;

GRANT INSERT ON app_notifications TO authenticated;
GRANT INSERT ON push_notification_queue TO authenticated;
GRANT SELECT, UPDATE ON push_notification_queue TO service_role;
GRANT SELECT, INSERT, UPDATE ON user_push_tokens TO authenticated;

-- =====================================================================
-- STEP 11: VERIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '✅ VERIFICATION' AS status;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Verify trigger exists
SELECT 
    '✅ Trigger on app_notifications' AS check,
    trigger_name,
    action_timing || ' ' || event_manipulation AS trigger_event
FROM information_schema.triggers
WHERE event_object_table = 'app_notifications'
AND trigger_name = 'trigger_queue_push_notification';

-- Verify functions exist
SELECT 
    proname AS function_name,
    '✅' AS status
FROM pg_proc
WHERE proname IN (
    'queue_push_notification',
    'send_friend_request', 
    'accept_friend_request',
    'respond_to_challenge',
    'queue_challenge_invite_notification',
    'queue_contact_joined_notification'
);

-- Verify cron job
SELECT 
    '✅ Cron job' AS check,
    jobname,
    schedule,
    CASE WHEN active THEN 'ACTIVE' ELSE 'INACTIVE' END AS status
FROM cron.job
WHERE jobname = 'process-push-notifications';

SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🎉 NOTIFICATION PIPELINE FIX COMPLETE!' AS status;
SELECT 'Now run NOTIFICATION_TESTING_SUITE.sql to verify everything works.' AS next_step;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
