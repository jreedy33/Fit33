-- ============================================================================
-- FIX CHALLENGE TRIGGER
-- Fixes the "record new has no field is_creator" error
-- ============================================================================

-- First, let's see what triggers exist on challenge_participants
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'challenge_participants';

-- Check the challenge_participants table structure
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'challenge_participants'
ORDER BY ordinal_position;

-- ============================================================================
-- The issue is likely a trigger that references 'is_creator' which doesn't exist
-- Let's find and fix it
-- ============================================================================

-- Drop any problematic triggers that reference is_creator
DO $$
DECLARE
    trigger_rec RECORD;
BEGIN
    FOR trigger_rec IN 
        SELECT trigger_name 
        FROM information_schema.triggers 
        WHERE event_object_table = 'challenge_participants'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON challenge_participants', trigger_rec.trigger_name);
        RAISE NOTICE 'Dropped trigger: %', trigger_rec.trigger_name;
    END LOOP;
END $$;

-- ============================================================================
-- Recreate the notification trigger properly
-- This trigger sends a push notification when a challenge invite is created
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
    
    -- Get challenge details
    SELECT c.*, up.name AS creator_name
    INTO v_challenge
    FROM challenges c
    JOIN user_profiles up ON up.id = c.creator_id
    WHERE c.id = NEW.challenge_id;
    
    -- Only notify if this is NOT the creator (the opponent)
    IF NEW.user_id != v_challenge.creator_id THEN
        -- Create app notification for the opponent
        INSERT INTO app_notifications (
            user_id,
            type,
            title,
            body,
            data
        ) VALUES (
            NEW.user_id,
            'challenge_invite',
            v_challenge.creator_name || ' wants to challenge you! 🏆',
            'Challenge: ' || v_challenge.title,
            jsonb_build_object(
                'challenge_id', NEW.challenge_id,
                'creator_id', v_challenge.creator_id,
                'challenge_type', v_challenge.challenge_type
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
DROP TRIGGER IF EXISTS on_challenge_participant_insert ON challenge_participants;
CREATE TRIGGER on_challenge_participant_insert
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_invite();

-- ============================================================================
-- Also fix the challenge response notification trigger
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
    
    -- Get challenge details and responder name
    SELECT c.*, up.name AS responder_name
    INTO v_challenge
    FROM challenges c
    JOIN user_profiles up ON up.id = NEW.user_id
    WHERE c.id = NEW.challenge_id;
    
    v_responder_name := v_challenge.responder_name;
    
    -- Notify the challenge creator
    IF NEW.status = 'accepted' THEN
        INSERT INTO app_notifications (
            user_id,
            type,
            title,
            body,
            data
        ) VALUES (
            v_challenge.creator_id,
            'challenge_accepted',
            v_responder_name || ' accepted your challenge! 🎉',
            'Challenge "' || v_challenge.title || '" is now active!',
            jsonb_build_object(
                'challenge_id', NEW.challenge_id,
                'responder_id', NEW.user_id
            )
        );
    ELSIF NEW.status = 'declined' THEN
        INSERT INTO app_notifications (
            user_id,
            type,
            title,
            body,
            data
        ) VALUES (
            v_challenge.creator_id,
            'challenge_declined',
            v_responder_name || ' declined your challenge 😔',
            'Challenge "' || v_challenge.title || '" was declined',
            jsonb_build_object(
                'challenge_id', NEW.challenge_id,
                'responder_id', NEW.user_id
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
DROP TRIGGER IF EXISTS on_challenge_participant_update ON challenge_participants;
CREATE TRIGGER on_challenge_participant_update
    AFTER UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_response();

-- ============================================================================
-- Verify the fix
-- ============================================================================

SELECT 
    'Triggers on challenge_participants:' AS info;

SELECT 
    trigger_name,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'challenge_participants';
