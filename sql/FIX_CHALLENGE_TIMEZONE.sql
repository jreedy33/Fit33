-- ============================================================================
-- FIX: Challenge "today" progress uses UTC CURRENT_DATE instead of user's 
-- local timezone. This causes myToday/oppToday to show 0 after 7 PM EST
-- (midnight UTC) because the DB thinks it's "tomorrow" while the app 
-- logged progress against the user's local date.
--
-- Solution: Accept timezone parameter, compute "today" in user's local time.
-- Each user gets until THEIR midnight to hit the daily goal.
-- ============================================================================

-- Step 1: Add 'aggregated' to allowed sources (recalculate uses this)
ALTER TABLE challenge_daily_progress 
    DROP CONSTRAINT IF EXISTS challenge_daily_progress_source_check;

ALTER TABLE challenge_daily_progress 
    ADD CONSTRAINT challenge_daily_progress_source_check 
    CHECK (source IN ('manual', 'healthkit', 'strava', 'fitbit', 'aggregated'));

-- Step 2: Drop the old function signature (no params) before creating new one with params
DROP FUNCTION IF EXISTS get_active_challenges();

-- Step 3: Recreate with timezone parameter
CREATE OR REPLACE FUNCTION get_active_challenges(p_timezone TEXT DEFAULT 'UTC')
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
    days_elapsed INTEGER,
    days_remaining INTEGER,
    status TEXT,
    my_total_progress INTEGER,
    my_today_progress INTEGER,
    my_days_completed INTEGER,
    my_current_streak INTEGER,
    opponent_id UUID,
    opponent_name TEXT,
    opponent_username TEXT,
    opponent_photo_url TEXT,
    opponent_total_progress INTEGER,
    opponent_today_progress INTEGER,
    opponent_days_completed INTEGER,
    am_winning BOOLEAN,
    am_winning_today BOOLEAN
) AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_today DATE;
BEGIN
    -- Compute "today" in the caller's local timezone
    -- This ensures each user's day runs midnight-to-midnight in their own timezone
    BEGIN
        v_today := (CURRENT_TIMESTAMP AT TIME ZONE p_timezone)::DATE;
    EXCEPTION WHEN OTHERS THEN
        -- Fallback to UTC if invalid timezone string is passed
        v_today := CURRENT_DATE;
    END;

    RETURN QUERY
    SELECT 
        fc.id as challenge_id,
        fc.challenge_type,
        fc.title,
        fc.description,
        fc.daily_target,
        fc.total_target,
        fc.target_unit,
        fc.start_date,
        fc.end_date,
        (fc.end_date - fc.start_date + 1)::INTEGER as duration_days,
        GREATEST(0, v_today - fc.start_date)::INTEGER as days_elapsed,
        GREATEST(0, fc.end_date - v_today)::INTEGER as days_remaining,
        fc.status,
        my_cp.total_progress as my_total_progress,
        -- Today's progress for current user (using LOCAL today)
        COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = v_current_user_id 
            AND cdp.progress_date = v_today
        ), 0)::INTEGER as my_today_progress,
        my_cp.days_completed as my_days_completed,
        my_cp.current_streak as my_current_streak,
        opp_cp.user_id as opponent_id,
        opp_up.name as opponent_name,
        opp_up.username as opponent_username,
        opp_up.profile_photo_url as opponent_photo_url,
        opp_cp.total_progress as opponent_total_progress,
        -- Today's progress for opponent (using same LOCAL today for comparison)
        COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = opp_cp.user_id 
            AND cdp.progress_date = v_today
        ), 0)::INTEGER as opponent_today_progress,
        opp_cp.days_completed as opponent_days_completed,
        (my_cp.total_progress > opp_cp.total_progress) as am_winning,
        -- Who's winning TODAY (using LOCAL today)
        (COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = v_current_user_id 
            AND cdp.progress_date = v_today
        ), 0) > COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = opp_cp.user_id 
            AND cdp.progress_date = v_today
        ), 0)) as am_winning_today
    FROM friend_challenges fc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = fc.id AND my_cp.user_id = v_current_user_id
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = fc.id AND opp_cp.user_id != v_current_user_id
    LEFT JOIN user_profiles opp_up ON opp_up.id::TEXT = opp_cp.user_id::TEXT
    WHERE my_cp.status = 'accepted'
    AND fc.status = 'active'
    ORDER BY fc.start_date ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;

SELECT '✅ get_active_challenges now uses caller timezone for "today" - each user gets until their local midnight!' as result;
