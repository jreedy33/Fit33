-- ============================================================================
-- FIX CANCEL CHALLENGE - February 2, 2026
-- Fixes three issues:
-- 1. cancel_challenge trying to update non-existent updated_at column
-- 2. get_challenge_details ambiguous column reference
-- 3. challenge_participants status constraint doesn't allow 'cancelled' (use 'left')
-- ============================================================================

-- Fix 1: Update cancel_challenge to not reference updated_at on challenge_participants
DROP FUNCTION IF EXISTS cancel_challenge(UUID);

CREATE OR REPLACE FUNCTION cancel_challenge(
    p_challenge_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID;
    v_challenge RECORD;
    v_canceller_name TEXT;
    v_opponent_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    -- Get challenge details
    SELECT fc.*, cp.user_id as participant_id
    INTO v_challenge
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id
    WHERE fc.id = p_challenge_id
    AND cp.user_id = v_user_id
    AND fc.status IN ('active', 'pending');
    
    IF v_challenge IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or you are not a participant';
    END IF;
    
    -- Get canceller's name
    SELECT COALESCE(name, 'Your friend') INTO v_canceller_name
    FROM user_profiles
    WHERE id = v_user_id;
    
    -- Get opponent's user_id
    SELECT user_id INTO v_opponent_id
    FROM challenge_participants
    WHERE challenge_id = p_challenge_id
    AND user_id != v_user_id
    LIMIT 1;
    
    -- Update challenge status to cancelled
    UPDATE friend_challenges
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_challenge_id;
    
    -- Update participant statuses to 'left' (cancelled isn't a valid status for participants)
    UPDATE challenge_participants
    SET status = 'left'
    WHERE challenge_id = p_challenge_id;
    
    -- Queue notification to opponent if they exist
    IF v_opponent_id IS NOT NULL THEN
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data
        ) VALUES (
            v_opponent_id,
            'challenge_cancelled',
            v_canceller_name || ' cancelled the challenge 😔',
            'The "' || v_challenge.title || '" challenge has been cancelled.',
            jsonb_build_object(
                'challenge_id', p_challenge_id::TEXT,
                'canceller_name', v_canceller_name,
                'challenge_title', v_challenge.title,
                'type', 'challenge_cancelled'
            )
        );
        
        -- Trigger the edge function via pg_notify
        PERFORM pg_notify('push_notification', json_build_object(
            'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::TEXT,
            'type', 'challenge_cancelled'
        )::TEXT);
        
        RAISE NOTICE 'Challenge cancelled notification queued for opponent %', v_opponent_id;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION cancel_challenge(UUID) TO authenticated;

-- Fix 2: Update get_challenge_details to fix ambiguous column reference
DROP FUNCTION IF EXISTS get_challenge_details(UUID);

CREATE OR REPLACE FUNCTION get_challenge_details(p_challenge_id UUID)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT,
    start_date DATE,
    end_date DATE,
    duration_days INTEGER,
    status TEXT,
    created_at TIMESTAMPTZ,
    notify_on_opponent_complete BOOLEAN,
    -- Participants as JSON array
    participants JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.id,
        fc.challenge_type,
        fc.title,
        fc.description,
        fc.daily_target,
        fc.total_target,
        fc.target_unit,
        fc.start_date,
        fc.end_date,
        (fc.end_date - fc.start_date + 1)::INTEGER as duration_days,
        fc.status,
        fc.created_at,
        -- Get notification preference for current user
        (
            SELECT COALESCE(cp_me.notify_on_opponent_complete, true)
            FROM challenge_participants cp_me
            WHERE cp_me.challenge_id = fc.id AND cp_me.user_id = auth.uid()
        ) as notify_on_opponent_complete,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', cp.user_id,
                'name', up.name,
                'username', up.username,
                'photo_url', up.profile_photo_url,
                'status', cp.status,
                'total_progress', cp.total_progress,
                'days_completed', cp.days_completed,
                'current_streak', cp.current_streak,
                'best_streak', cp.best_streak,
                'is_creator', cp.user_id = fc.creator_id,
                'daily_progress', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'date', cdp.progress_date,
                        'value', cdp.progress_value,
                        'source', cdp.source
                    ) ORDER BY cdp.progress_date)
                    FROM challenge_daily_progress cdp
                    WHERE cdp.challenge_id = fc.id AND cdp.user_id = cp.user_id
                )
            ))
            FROM challenge_participants cp
            LEFT JOIN user_profiles up ON up.id::TEXT = cp.user_id::TEXT
            WHERE cp.challenge_id = fc.id
        ) as participants
    FROM friend_challenges fc
    WHERE fc.id = p_challenge_id
    AND (
        fc.creator_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM challenge_participants cp_check
            WHERE cp_check.challenge_id = fc.id AND cp_check.user_id = auth.uid()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_challenge_details(UUID) TO authenticated;

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT '✅ Fixed cancel_challenge function (removed updated_at, use left instead of cancelled)' AS fix1;
SELECT '✅ Fixed get_challenge_details function (resolved ambiguous column reference)' AS fix2;
