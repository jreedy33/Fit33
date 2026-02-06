-- =====================================================
-- VERIFY ALL NOTIFICATIONS SQL
-- Comprehensive audit of notification system
-- =====================================================

-- ===========================================
-- SECTION 1: Current Notification Tables
-- ===========================================

-- List all notification-related tables
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name LIKE '%notif%';

-- ===========================================
-- SECTION 2: Check respond_to_challenge function
-- ===========================================

SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'respond_to_challenge';

-- ===========================================
-- SECTION 3: Check what triggers exist on challenge_participants
-- ===========================================

SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'challenge_participants';

-- ===========================================
-- SECTION 4: Check if contact_joined_notifications creates push notifications
-- ===========================================

SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'contact_joined_notifications';

-- ===========================================
-- SECTION 5: Recent notifications audit
-- ===========================================

-- Recent app_notifications
SELECT 
    notification_type,
    COUNT(*) as count,
    MAX(created_at) as latest
FROM app_notifications
GROUP BY notification_type
ORDER BY latest DESC;

-- Recent push_notification_queue entries
SELECT 
    notification_type,
    status,
    COUNT(*) as count,
    MAX(created_at) as latest
FROM push_notification_queue
GROUP BY notification_type, status
ORDER BY latest DESC;

-- Recent contact_joined_notifications  
SELECT 
    COUNT(*) as total,
    MAX(created_at) as latest
FROM contact_joined_notifications;

-- ===========================================
-- SECTION 6: FIXES - Add missing notifications
-- ===========================================

-- FIX 1: Make challenge invites also create app_notifications
-- (Currently they only go to push_notification_queue)

CREATE OR REPLACE FUNCTION public.queue_challenge_invite_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    challenger_name TEXT;
    challenge_title TEXT;
    creator_user_id UUID;
BEGIN
    -- Only for new pending invites (not the creator's own entry)
    IF NEW.status != 'pending' OR NEW.is_creator = true THEN
        RETURN NEW;
    END IF;
    
    -- Get challenge details and creator info
    SELECT 
        fc.title,
        COALESCE(up.name, up.username, 'Someone'),
        cp.user_id
    INTO challenge_title, challenger_name, creator_user_id
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.is_creator = true
    JOIN user_profiles up ON up.id = cp.user_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Insert into app_notifications (for in-app display)
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
        creator_user_id,
        'New Challenge Invite',
        challenger_name || ' challenged you to "' || COALESCE(challenge_title, 'a challenge') || '"',
        false
    );
    
    -- Push notification will be created automatically via trigger on app_notifications
    
    RETURN NEW;
END;
$function$;


-- FIX 2: Add trigger to contact_joined_notifications to create app_notifications

CREATE OR REPLACE FUNCTION queue_contact_joined_notification()
RETURNS TRIGGER AS $$
BEGIN
    -- Create in-app notification
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
        'Contact Joined Fit33!',
        COALESCE(NEW.new_user_name, 'Someone from your contacts') || ' just joined Fit33. Add them as a friend!',
        false
    );
    
    -- Push notification will be created automatically via trigger on app_notifications
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger if it doesn't exist
DROP TRIGGER IF EXISTS trigger_contact_joined_notification ON contact_joined_notifications;
CREATE TRIGGER trigger_contact_joined_notification
    AFTER INSERT ON contact_joined_notifications
    FOR EACH ROW
    EXECUTE FUNCTION queue_contact_joined_notification();


-- FIX 3: Update respond_to_challenge to notify the challenger when someone accepts/declines

-- Run this query first to see current function definition:
-- SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'respond_to_challenge';

-- ===========================================
-- SECTION 7: Verification Queries
-- ===========================================

-- After running fixes, test by checking:

-- 1. Send yourself a test notification
/*
INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'YOUR_USER_ID_HERE',
    'test',
    gen_random_uuid(),
    'YOUR_USER_ID_HERE',
    'Test Notification',
    'This is a test push notification',
    false
);
*/

-- 2. Check if it appeared in push queue
-- SELECT * FROM push_notification_queue ORDER BY created_at DESC LIMIT 5;

-- 3. Check if it was sent
-- SELECT * FROM push_notification_queue WHERE status = 'sent' ORDER BY sent_at DESC LIMIT 5;

-- ===========================================
-- NOTIFICATION TYPE REFERENCE
-- ===========================================
/*
Expected notification_type values:
- friend_request      : Someone sent you a friend request
- friend_accepted     : Someone accepted your friend request  
- challenge_invite    : Someone invited you to a challenge
- challenge_accepted  : Someone accepted your challenge
- challenge_declined  : Someone declined your challenge
- contact_joined      : Someone from your contacts joined Fit33
- workout_shared      : Someone shared a workout with you
- reminder            : Scheduled workout reminder
*/
