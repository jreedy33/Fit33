-- Fix: nudge_group_challenge_member overload conflict
-- The app gets "Could not choose the best candidate function between" because
-- multiple overloads exist (TEXT,TEXT) and (UUID,UUID). Drop all and recreate canonical version.

BEGIN;

DROP FUNCTION IF EXISTS nudge_group_challenge_member(TEXT, TEXT);
DROP FUNCTION IF EXISTS nudge_group_challenge_member(UUID, UUID);

CREATE OR REPLACE FUNCTION nudge_group_challenge_member(
    p_challenge_id TEXT,
    p_recipient_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    recipient_uuid UUID;
    sender_name TEXT;
    challenge_title TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    recipient_uuid := p_recipient_id::UUID;

    -- Check if already nudged today
    IF EXISTS (
        SELECT 1 FROM group_challenge_nudges
        WHERE challenge_id = challenge_uuid 
        AND sender_id = current_user_uuid 
        AND recipient_id = recipient_uuid
        AND created_at > CURRENT_DATE
    ) THEN
        RETURN FALSE;
    END IF;

    -- Record the nudge
    INSERT INTO group_challenge_nudges (challenge_id, sender_id, recipient_id, created_at)
    VALUES (challenge_uuid, current_user_uuid, recipient_uuid, NOW());

    -- Get names
    SELECT name INTO sender_name FROM user_profiles WHERE id = current_user_uuid;
    SELECT title INTO challenge_title FROM group_challenges WHERE id = challenge_uuid;

    -- Queue notification
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            recipient_uuid,
            'challenge_nudge',
            COALESCE(sender_name, 'Someone') || ' nudged you!',
            'Don''t forget your "' || COALESCE(challenge_title, 'challenge') || '" goal today!',
            jsonb_build_object(
                'type', 'challenge_nudge',
                'challenge_id', challenge_uuid::TEXT,
                'from_user_id', current_user_uuid::TEXT
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION nudge_group_challenge_member(TEXT, TEXT) TO authenticated;

COMMIT;
