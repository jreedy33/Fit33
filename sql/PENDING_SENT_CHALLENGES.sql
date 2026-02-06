-- ============================================================================
-- PENDING SENT CHALLENGES
-- Functions to support outgoing challenge requests (waiting for opponent)
-- ============================================================================

-- ============================================================================
-- Function: Get challenges I sent that are waiting for acceptance
-- ============================================================================

CREATE OR REPLACE FUNCTION get_pending_sent_challenges()
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    opponent_id UUID,
    opponent_name TEXT,
    opponent_username TEXT,
    opponent_photo_url TEXT,
    sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        c.id AS challenge_id,
        c.challenge_type,
        c.title,
        c.description,
        COALESCE(ct.emoji, '🏆')::TEXT AS emoji,
        c.daily_target,
        c.total_target,
        c.target_unit,
        c.start_date::TEXT,
        c.end_date::TEXT,
        (c.end_date - c.start_date + 1)::INT AS duration_days,
        cp.user_id AS opponent_id,
        up.name AS opponent_name,
        up.username AS opponent_username,
        up.profile_photo_url AS opponent_photo_url,
        c.created_at AS sent_at
    FROM friend_challenges c
    -- Get the opponent's participant record (status = pending means they haven't responded)
    JOIN challenge_participants cp ON cp.challenge_id = c.id 
        AND cp.user_id != v_user_id 
        AND cp.status = 'pending'
    -- Get opponent profile
    LEFT JOIN user_profiles up ON up.id = cp.user_id
    -- Get challenge type for emoji (optional - table may not exist)
    LEFT JOIN challenge_templates ct ON ct.challenge_type = c.challenge_type
    -- Only challenges I created
    WHERE c.creator_id = v_user_id
    -- Order by most recently sent first
    ORDER BY c.created_at DESC;
END;
$$;

-- Grant access
GRANT EXECUTE ON FUNCTION get_pending_sent_challenges() TO authenticated;

-- ============================================================================
-- Function: Cancel a pending challenge I sent
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
    WHERE challenge_id = v_challenge_id AND user_id != v_user_id;
    
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
-- VERIFICATION: Test the functions
-- ============================================================================

-- Run this to verify the function works:
-- SELECT * FROM get_pending_sent_challenges();
