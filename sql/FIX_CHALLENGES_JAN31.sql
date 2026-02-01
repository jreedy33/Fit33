-- ============================================================================
-- FIX CHALLENGES - January 31, 2026
-- Issues:
-- 1. challenge_participants missing updated_at column
-- 2. Ambiguous column reference in get_challenge_details
-- 3. Need to clear all existing challenges
-- 4. Add constraint: only 1 active challenge between same two friends
-- 5. Add constraint: max 3 active challenges per user
-- ============================================================================

-- ============================================================================
-- 1. ADD MISSING updated_at COLUMN TO challenge_participants
-- ============================================================================

ALTER TABLE challenge_participants 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- ============================================================================
-- 2. CLEAR ALL EXISTING CHALLENGES (fresh start)
-- ============================================================================

-- Delete in correct order due to foreign key constraints
DELETE FROM challenge_daily_progress;
DELETE FROM challenge_participants;
DELETE FROM friend_challenges;

SELECT 'All existing challenges cleared!' AS status;

-- ============================================================================
-- 3. FIX get_challenge_details - DROP first, then recreate
-- ============================================================================

DROP FUNCTION IF EXISTS get_challenge_details(UUID);

CREATE OR REPLACE FUNCTION get_challenge_details(p_challenge_id UUID)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    
    -- Check user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants 
        WHERE challenge_id = p_challenge_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a participant in this challenge';
    END IF;
    
    SELECT json_build_object(
        'challenge_id', fc.id,
        'challenge_type', fc.challenge_type,
        'title', fc.title,
        'description', fc.description,
        'daily_target', fc.daily_target,
        'total_target', fc.total_target,
        'target_unit', fc.target_unit,
        'start_date', fc.start_date,
        'end_date', fc.end_date,
        'duration_days', (fc.end_date - fc.start_date + 1),
        'days_elapsed', GREATEST(0, LEAST(CURRENT_DATE - fc.start_date + 1, fc.end_date - fc.start_date + 1)),
        'days_remaining', GREATEST(0, fc.end_date - CURRENT_DATE),
        'status', fc.status,
        'created_at', fc.created_at,
        'participants', (
            SELECT json_agg(
                json_build_object(
                    'user_id', cp.user_id,
                    'name', up.name,
                    'username', up.username,
                    'photo_url', up.photo_url,
                    'status', cp.status,
                    'total_progress', COALESCE(cp.total_progress, 0),
                    'days_completed', COALESCE(cp.days_completed, 0),
                    'current_streak', COALESCE(cp.current_streak, 0),
                    'is_me', cp.user_id = v_user_id
                )
            )
            FROM challenge_participants cp
            JOIN user_profiles up ON up.id = cp.user_id
            WHERE cp.challenge_id = fc.id
        ),
        'daily_progress', (
            SELECT json_agg(
                json_build_object(
                    'user_id', cdp.user_id,
                    'progress_date', cdp.progress_date,
                    'progress_value', cdp.progress_value,
                    'target_hit', cdp.target_hit,
                    'source', cdp.source
                )
                ORDER BY cdp.progress_date DESC
            )
            FROM challenge_daily_progress cdp
            WHERE cdp.challenge_id = fc.id
        )
    ) INTO v_result
    FROM friend_challenges fc
    WHERE fc.id = p_challenge_id;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 4. FIX cancel_challenge - use correct column
-- ============================================================================

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
    
    -- Update participant statuses (only status column)
    UPDATE challenge_participants
    SET status = 'cancelled'
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

-- ============================================================================
-- 5. UPDATE create_challenge - enforce limits
--    - Max 1 active/pending challenge between same two friends
--    - Max 3 total active/pending challenges per user
-- ============================================================================

DROP FUNCTION IF EXISTS create_challenge(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, DATE, DATE);

CREATE OR REPLACE FUNCTION create_challenge(
    p_friend_id UUID,
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT,
    p_daily_target INTEGER,
    p_total_target INTEGER,
    p_target_unit TEXT,
    p_start_date DATE,
    p_end_date DATE
)
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
    v_challenge_id UUID;
    v_existing_count INTEGER;
    v_user_active_count INTEGER;
BEGIN
    v_user_id := auth.uid();
    
    -- Verify friendship exists
    IF NOT EXISTS (
        SELECT 1 FROM friendships 
        WHERE status = 'accepted' 
        AND ((user_id = v_user_id AND friend_id = p_friend_id) 
             OR (user_id = p_friend_id AND friend_id = v_user_id))
    ) THEN
        RAISE EXCEPTION 'You are not friends with this user';
    END IF;
    
    -- Check if there's already an active/pending challenge between these two users
    SELECT COUNT(*) INTO v_existing_count
    FROM friend_challenges fc
    JOIN challenge_participants cp1 ON cp1.challenge_id = fc.id AND cp1.user_id = v_user_id
    JOIN challenge_participants cp2 ON cp2.challenge_id = fc.id AND cp2.user_id = p_friend_id
    WHERE fc.status IN ('pending', 'active');
    
    IF v_existing_count > 0 THEN
        RAISE EXCEPTION 'You already have an active challenge with this friend. Complete or cancel it first.';
    END IF;
    
    -- Check if user has reached max 3 active/pending challenges
    SELECT COUNT(*) INTO v_user_active_count
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id = v_user_id
    WHERE fc.status IN ('pending', 'active');
    
    IF v_user_active_count >= 3 THEN
        RAISE EXCEPTION 'You can have at most 3 active challenges at a time.';
    END IF;
    
    -- Create the challenge
    INSERT INTO friend_challenges (
        creator_id,
        challenge_type,
        title,
        description,
        daily_target,
        total_target,
        target_unit,
        start_date,
        end_date,
        status
    ) VALUES (
        v_user_id,
        p_challenge_type,
        p_title,
        p_description,
        p_daily_target,
        p_total_target,
        p_target_unit,
        p_start_date,
        p_end_date,
        'pending'
    ) RETURNING id INTO v_challenge_id;
    
    -- Add creator as accepted participant
    INSERT INTO challenge_participants (challenge_id, user_id, status, joined_at)
    VALUES (v_challenge_id, v_user_id, 'accepted', NOW());
    
    -- Add friend as pending participant
    INSERT INTO challenge_participants (challenge_id, user_id, status)
    VALUES (v_challenge_id, p_friend_id, 'pending');
    
    RETURN v_challenge_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. VERIFY CHANGES
-- ============================================================================

SELECT 'Challenges system updated!' AS status;
SELECT '✓ Added updated_at column to challenge_participants' AS fix1;
SELECT '✓ Cleared all existing challenges' AS fix2;
SELECT '✓ Fixed get_challenge_details function' AS fix3;
SELECT '✓ Fixed cancel_challenge function' AS fix4;
SELECT '✓ Added limit: 1 challenge per friend pair' AS fix5;
SELECT '✓ Added limit: 3 max active challenges per user' AS fix6;
