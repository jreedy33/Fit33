-- STEP 2: Create the updated function with today's progress
-- Run this AFTER FIX_CHALLENGE_STEP1_DROP.sql

CREATE OR REPLACE FUNCTION get_active_challenges()
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
BEGIN
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
        GREATEST(0, CURRENT_DATE - fc.start_date)::INTEGER as days_elapsed,
        GREATEST(0, fc.end_date - CURRENT_DATE)::INTEGER as days_remaining,
        fc.status,
        my_cp.total_progress as my_total_progress,
        COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = v_current_user_id 
            AND cdp.progress_date = CURRENT_DATE
        ), 0)::INTEGER as my_today_progress,
        my_cp.days_completed as my_days_completed,
        my_cp.current_streak as my_current_streak,
        opp_cp.user_id as opponent_id,
        opp_up.name as opponent_name,
        opp_up.username as opponent_username,
        opp_up.profile_photo_url as opponent_photo_url,
        opp_cp.total_progress as opponent_total_progress,
        COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = opp_cp.user_id 
            AND cdp.progress_date = CURRENT_DATE
        ), 0)::INTEGER as opponent_today_progress,
        opp_cp.days_completed as opponent_days_completed,
        (my_cp.total_progress > opp_cp.total_progress) as am_winning,
        (COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = v_current_user_id 
            AND cdp.progress_date = CURRENT_DATE
        ), 0) > COALESCE((
            SELECT cdp.progress_value 
            FROM challenge_daily_progress cdp 
            WHERE cdp.challenge_id = fc.id 
            AND cdp.user_id = opp_cp.user_id 
            AND cdp.progress_date = CURRENT_DATE
        ), 0)) as am_winning_today
    FROM friend_challenges fc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = fc.id AND my_cp.user_id = v_current_user_id
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = fc.id AND opp_cp.user_id != v_current_user_id
    LEFT JOIN user_profiles opp_up ON opp_up.id::TEXT = opp_cp.user_id::TEXT
    WHERE my_cp.status = 'accepted'
    AND fc.status IN ('active', 'pending')
    ORDER BY fc.start_date ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_active_challenges() TO authenticated;

SELECT '✅ Function created with today_progress fields!' as result;
SELECT 'Widget will now show 0 steps at midnight and increase as you walk.' as info;
