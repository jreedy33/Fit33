-- ============================================================================
-- CHALLENGE NOTIFICATION PREFERENCE
-- Allows users to toggle push notifications when opponent completes daily challenge
-- ============================================================================

-- 1. Add notification preference column to challenge_participants
ALTER TABLE challenge_participants 
ADD COLUMN IF NOT EXISTS notify_on_opponent_complete BOOLEAN DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN challenge_participants.notify_on_opponent_complete IS 
'When true, user receives push notification when opponent completes their daily challenge';

-- ============================================================================
-- 2. Function to toggle notification preference
-- ============================================================================

CREATE OR REPLACE FUNCTION toggle_challenge_notification_preference(
    p_challenge_id UUID,
    p_notify BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = p_challenge_id 
        AND user_id = v_user_id 
        AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'User is not a participant in this challenge';
    END IF;
    
    -- Update the preference
    UPDATE challenge_participants
    SET notify_on_opponent_complete = p_notify
    WHERE challenge_id = p_challenge_id 
    AND user_id = v_user_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION toggle_challenge_notification_preference(UUID, BOOLEAN) TO authenticated;

-- ============================================================================
-- 3. Function to get notification preference for a challenge
-- ============================================================================

CREATE OR REPLACE FUNCTION get_challenge_notification_preference(
    p_challenge_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_notify BOOLEAN;
BEGIN
    SELECT notify_on_opponent_complete INTO v_notify
    FROM challenge_participants
    WHERE challenge_id = p_challenge_id 
    AND user_id = auth.uid();
    
    RETURN COALESCE(v_notify, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_challenge_notification_preference(UUID) TO authenticated;

-- ============================================================================
-- 4. Update notify_opponent_daily_complete to check preference
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_opponent_daily_complete()
RETURNS TRIGGER AS $$
DECLARE
    v_user_name TEXT;
    v_challenge_title TEXT;
    v_opponent_id UUID;
    v_challenge_type TEXT;
    v_should_notify BOOLEAN;
BEGIN
    -- Only notify when target_hit changes from false to true (or NULL to true)
    IF NEW.target_hit = TRUE AND (OLD.target_hit IS NULL OR OLD.target_hit = FALSE) THEN
        
        -- Get the user's name who completed the challenge
        SELECT COALESCE(up.name, 'Your opponent') INTO v_user_name
        FROM user_profiles up
        WHERE up.id::TEXT = NEW.user_id::TEXT;
        
        -- Get challenge details
        SELECT fc.title, fc.challenge_type INTO v_challenge_title, v_challenge_type
        FROM friend_challenges fc
        WHERE fc.id = NEW.challenge_id;
        
        -- Find opponent(s) in this challenge who want notifications
        FOR v_opponent_id, v_should_notify IN 
            SELECT cp.user_id, COALESCE(cp.notify_on_opponent_complete, true)
            FROM challenge_participants cp
            WHERE cp.challenge_id = NEW.challenge_id 
            AND cp.user_id != NEW.user_id
            AND cp.status = 'accepted'
        LOOP
            -- Only queue notification if user wants to be notified
            IF v_should_notify THEN
                -- Queue push notification for the opponent
                INSERT INTO push_notification_queue (
                    recipient_user_id,
                    notification_type,
                    title,
                    body,
                    data
                ) VALUES (
                    v_opponent_id,
                    'challenge_progress',
                    v_user_name || ' completed their daily challenge! 🔥',
                    'They hit their target for "' || COALESCE(v_challenge_title, 'Challenge') || '". Don''t fall behind!',
                    jsonb_build_object(
                        'challenge_id', NEW.challenge_id::TEXT,
                        'user_name', v_user_name,
                        'challenge_title', v_challenge_title,
                        'challenge_type', v_challenge_type,
                        'type', 'challenge_progress'
                    )
                );
                
                -- Trigger the edge function via pg_notify
                PERFORM pg_notify('push_notification', json_build_object(
                    'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::TEXT,
                    'type', 'challenge_progress'
                )::TEXT);
                
                RAISE NOTICE 'Daily challenge completion notification queued for opponent %', v_opponent_id;
            ELSE
                RAISE NOTICE 'Skipping notification for opponent % (notifications disabled)', v_opponent_id;
            END IF;
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
DROP TRIGGER IF EXISTS on_daily_challenge_complete ON challenge_daily_progress;
CREATE TRIGGER on_daily_challenge_complete
    AFTER INSERT OR UPDATE ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION notify_opponent_daily_complete();

-- ============================================================================
-- 5. Update get_challenge_details to include notification preference
-- ============================================================================

-- Must drop first because we're changing the return type (adding notify_on_opponent_complete)
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

SELECT 'Challenge notification preference system created!' AS status;
SELECT '- Added notify_on_opponent_complete column to challenge_participants' AS change1;
SELECT '- Created toggle_challenge_notification_preference() function' AS change2;
SELECT '- Updated notify_opponent_daily_complete() to respect preference' AS change3;
SELECT '- Updated get_challenge_details() to include preference' AS change4;
