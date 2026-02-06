-- ============================================================================
-- FIX CHALLENGE TRIGGER V2
-- Fixes the trigger to use friend_challenges instead of challenges
-- ============================================================================

-- Drop the broken triggers
DROP TRIGGER IF EXISTS on_challenge_participant_insert ON challenge_participants;
DROP TRIGGER IF EXISTS on_challenge_participant_update ON challenge_participants;

-- ============================================================================
-- Recreate the notification trigger properly with CORRECT table name
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_challenge_invite()
RETURNS TRIGGER AS $$
DECLARE
    v_challenge RECORD;
    v_creator_name TEXT;
BEGIN
    -- Only trigger for pending status (new invites)
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get challenge details from friend_challenges (correct table name!)
    SELECT fc.*, up.name AS creator_name
    INTO v_challenge
    FROM friend_challenges fc
    JOIN user_profiles up ON up.id = fc.creator_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Only notify if this is NOT the creator (the opponent)
    IF v_challenge.creator_id IS NOT NULL AND NEW.user_id != v_challenge.creator_id THEN
        -- Create app notification for the opponent
        INSERT INTO app_notifications (
            user_id,
            notification_type,
            title,
            body,
            reference_id,
            from_user_id
        ) VALUES (
            NEW.user_id,
            'challenge_invite',
            v_challenge.creator_name || ' wants to challenge you! 🏆',
            'Challenge: ' || v_challenge.title,
            NEW.challenge_id,
            v_challenge.creator_id
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
CREATE TRIGGER on_challenge_participant_insert
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_invite();

-- ============================================================================
-- Fix the challenge response notification trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_challenge_response()
RETURNS TRIGGER AS $$
DECLARE
    v_challenge RECORD;
    v_responder_name TEXT;
BEGIN
    -- Only trigger when status changes from pending
    IF OLD.status != 'pending' THEN
        RETURN NEW;
    END IF;
    
    -- Get challenge details and responder name from friend_challenges (correct table!)
    SELECT fc.id, fc.title, fc.creator_id, up.name AS responder_name
    INTO v_challenge
    FROM friend_challenges fc
    JOIN user_profiles up ON up.id = NEW.user_id
    WHERE fc.id = NEW.challenge_id;
    
    -- Notify the challenge creator
    IF v_challenge.creator_id IS NOT NULL THEN
        IF NEW.status = 'accepted' THEN
            INSERT INTO app_notifications (
                user_id,
                notification_type,
                title,
                body,
                reference_id,
                from_user_id
            ) VALUES (
                v_challenge.creator_id,
                'challenge_accepted',
                v_challenge.responder_name || ' accepted your challenge! 🎉',
                'Challenge "' || v_challenge.title || '" is now active!',
                NEW.challenge_id,
                NEW.user_id
            );
        ELSIF NEW.status = 'declined' THEN
            INSERT INTO app_notifications (
                user_id,
                notification_type,
                title,
                body,
                reference_id,
                from_user_id
            ) VALUES (
                v_challenge.creator_id,
                'challenge_declined',
                v_challenge.responder_name || ' declined your challenge 😔',
                'Challenge "' || v_challenge.title || '" was declined',
                NEW.challenge_id,
                NEW.user_id
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
CREATE TRIGGER on_challenge_participant_update
    AFTER UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_response();

-- ============================================================================
-- Verify
-- ============================================================================

SELECT 'Triggers fixed!' AS status;

SELECT trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'challenge_participants';
