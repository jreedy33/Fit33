-- =====================================================
-- COMPLETE NOTIFICATION FIXES
-- Run this entire file in Supabase SQL Editor
-- =====================================================

-- ===========================================
-- FIX 1: Challenge Invites - Add app_notifications
-- ===========================================

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
    IF NEW.status != 'pending' OR NEW.is_creator = true THEN
        RETURN NEW;
    END IF;
    
    SELECT 
        fc.title,
        COALESCE(up.name, up.username, 'Someone'),
        cp.user_id
    INTO challenge_title, challenger_name, creator_user_id
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.is_creator = true
    JOIN user_profiles up ON up.id = cp.user_id
    WHERE fc.id = NEW.challenge_id;
    
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
    
    RETURN NEW;
END;
$function$;


-- ===========================================
-- FIX 2: Challenge Accept/Decline - Notify challenger
-- ===========================================

CREATE OR REPLACE FUNCTION public.respond_to_challenge(p_challenge_id uuid, p_accept boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_all_accepted BOOLEAN;
    v_creator_id UUID;
    v_responder_name TEXT;
    v_challenge_title TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'No pending invite found';
    END IF;
    
    SELECT 
        cp.user_id,
        COALESCE(up.name, up.username, 'Someone'),
        fc.title
    INTO v_creator_id, v_responder_name, v_challenge_title
    FROM challenge_participants cp
    JOIN user_profiles up ON up.id = v_current_user_id
    JOIN friend_challenges fc ON fc.id = p_challenge_id
    WHERE cp.challenge_id = p_challenge_id AND cp.is_creator = true;
    
    UPDATE challenge_participants
    SET 
        status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        responded_at = NOW(),
        joined_at = CASE WHEN p_accept THEN NOW() ELSE NULL END
    WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id;
    
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
        CASE WHEN p_accept THEN 'Challenge Accepted!' ELSE 'Challenge Declined' END,
        v_responder_name || CASE 
            WHEN p_accept THEN ' accepted your challenge "' || COALESCE(v_challenge_title, 'Challenge') || '"!'
            ELSE ' declined your challenge "' || COALESCE(v_challenge_title, 'Challenge') || '"'
        END,
        false
    );
    
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
$function$;


-- ===========================================
-- FIX 3: Contact Joined - Add push notification
-- ===========================================

CREATE OR REPLACE FUNCTION queue_contact_joined_notification()
RETURNS TRIGGER AS $$
BEGIN
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
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_contact_joined_notification ON contact_joined_notifications;
CREATE TRIGGER trigger_contact_joined_notification
    AFTER INSERT ON contact_joined_notifications
    FOR EACH ROW
    EXECUTE FUNCTION queue_contact_joined_notification();


-- ===========================================
-- VERIFICATION
-- ===========================================

SELECT 'Fixes applied! Verifying triggers...' AS status;

SELECT 
    event_object_table AS table_name,
    trigger_name,
    action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('app_notifications', 'contact_joined_notifications', 'challenge_participants')
ORDER BY event_object_table, trigger_name;
