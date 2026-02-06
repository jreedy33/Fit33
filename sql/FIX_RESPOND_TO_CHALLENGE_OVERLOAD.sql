-- Fix respond_to_challenge function overload - drop all versions and create one

-- Drop all existing versions
DROP FUNCTION IF EXISTS respond_to_challenge(uuid, boolean);
DROP FUNCTION IF EXISTS respond_to_challenge(text, boolean);

-- Create single version that accepts TEXT
CREATE OR REPLACE FUNCTION respond_to_challenge(p_challenge_id TEXT, p_accept BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_challenge_id UUID := p_challenge_id::UUID;
    v_creator_id UUID;
    v_accepter_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Get challenge details and creator
    SELECT creator_id, title INTO v_creator_id, v_challenge_title
    FROM friend_challenges
    WHERE id = v_challenge_id;
    
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Challenge not found';
    END IF;
    
    -- Verify the user is a participant (not the creator)
    IF v_creator_id = v_user_id THEN
        RAISE EXCEPTION 'Creator cannot respond to their own challenge';
    END IF;
    
    -- Update participant status
    IF p_accept THEN
        UPDATE challenge_participants
        SET status = 'accepted'
        WHERE challenge_id = v_challenge_id AND user_id = v_user_id;
        
        -- Check if both participants have accepted
        IF (SELECT COUNT(*) FROM challenge_participants WHERE challenge_id = v_challenge_id AND status = 'accepted') = 2 THEN
            -- Update challenge status to active
            UPDATE friend_challenges
            SET status = 'active', updated_at = NOW()
            WHERE id = v_challenge_id;
            
            -- Notify creator that challenge is now active
            SELECT name INTO v_accepter_name FROM user_profiles WHERE id = v_user_id;
            
            INSERT INTO app_notifications (
                user_id,
                notification_type,
                title,
                body,
                reference_id,
                from_user_id
            ) VALUES (
                v_creator_id,
                'challenge_accepted',
                'Challenge Accepted! 🎉',
                v_accepter_name || ' accepted your challenge "' || v_challenge_title || '"!',
                v_challenge_id,
                v_user_id
            );
        END IF;
    ELSE
        -- Declined - update participant status
        UPDATE challenge_participants
        SET status = 'declined'
        WHERE challenge_id = v_challenge_id AND user_id = v_user_id;
        
        -- Update challenge to cancelled
        UPDATE friend_challenges
        SET status = 'cancelled', updated_at = NOW()
        WHERE id = v_challenge_id;
        
        -- Notify creator
        SELECT name INTO v_accepter_name FROM user_profiles WHERE id = v_user_id;
        
        INSERT INTO app_notifications (
            user_id,
            notification_type,
            title,
            body,
            reference_id,
            from_user_id
        ) VALUES (
            v_creator_id,
            'challenge_declined',
            'Challenge Declined 😔',
            v_accepter_name || ' declined your challenge "' || v_challenge_title || '"',
            v_challenge_id,
            v_user_id
        );
    END IF;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION respond_to_challenge(TEXT, BOOLEAN) TO authenticated;
