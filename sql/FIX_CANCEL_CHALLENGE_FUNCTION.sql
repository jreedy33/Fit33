-- ============================================================================
-- FIX: Remove duplicate cancel_challenge functions
-- Error: Could not choose between cancel_challenge(text) and cancel_challenge(uuid)
-- ============================================================================

-- Drop ALL existing versions of cancel_challenge
DROP FUNCTION IF EXISTS cancel_challenge(TEXT);
DROP FUNCTION IF EXISTS cancel_challenge(UUID);
DROP FUNCTION IF EXISTS cancel_pending_challenge(TEXT);
DROP FUNCTION IF EXISTS cancel_pending_challenge(UUID);

-- ============================================================================
-- Recreate single clean version with TEXT parameter
-- (Swift sends UUID as string, so TEXT is the correct type)
-- ============================================================================

CREATE OR REPLACE FUNCTION cancel_challenge(p_challenge_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_challenge_id UUID := p_challenge_id::UUID;
    v_creator_id UUID;
    v_opponent_id UUID;
    v_challenge_title TEXT;
BEGIN
    -- Verify the user is the creator of this challenge
    SELECT creator_id, title INTO v_creator_id, v_challenge_title
    FROM friend_challenges
    WHERE id = v_challenge_id;
    
    IF v_creator_id IS NULL THEN
        RAISE EXCEPTION 'Challenge not found';
    END IF;
    
    IF v_creator_id != v_user_id THEN
        RAISE EXCEPTION 'Only the challenge creator can cancel it';
    END IF;
    
    -- Get opponent ID for notification
    SELECT user_id INTO v_opponent_id
    FROM challenge_participants
    WHERE challenge_id = v_challenge_id AND user_id != v_user_id
    LIMIT 1;
    
    -- Update challenge status to cancelled
    UPDATE friend_challenges
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = v_challenge_id;
    
    -- Update all participant statuses to 'left' (no updated_at column on this table)
    UPDATE challenge_participants
    SET status = 'left'
    WHERE challenge_id = v_challenge_id;
    
    -- Send notification to opponent that challenge was cancelled
    IF v_opponent_id IS NOT NULL THEN
        INSERT INTO app_notifications (
            user_id,
            notification_type,
            title,
            body,
            reference_id,
            from_user_id
        ) VALUES (
            v_opponent_id,
            'challenge_cancelled',
            'Challenge Cancelled',
            (SELECT name FROM user_profiles WHERE id = v_user_id) || ' cancelled the challenge "' || v_challenge_title || '"',
            v_challenge_id,
            v_user_id
        );
    END IF;
    
    RETURN TRUE;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION cancel_challenge(TEXT) TO authenticated;

-- ============================================================================
-- Verify only one function exists now
-- ============================================================================
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS arguments
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' 
AND p.proname LIKE '%cancel%challenge%';
