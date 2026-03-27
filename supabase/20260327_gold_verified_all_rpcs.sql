-- ============================================================================
-- ADD is_gold_verified TO ALL RPCs THAT ONLY HAVE is_verified
-- Comprehensive patch: covers 1v1 challenges, group challenges, community
-- challenges, private challenges, shared workouts, friend requests, search.
-- (League RPCs and get_friends already have is_gold_verified.)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. get_active_challenges — add opponent_is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_active_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_active_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, challenge_type TEXT, title TEXT, description TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    days_elapsed INT, days_remaining INT, status TEXT,
    my_total_progress INT, my_today_progress INT, my_days_completed INT, my_current_streak INT,
    opponent_id UUID, opponent_name TEXT, opponent_username TEXT, opponent_photo_url TEXT,
    opponent_total_progress INT, opponent_today_progress INT, opponent_days_completed INT,
    am_winning BOOLEAN, am_winning_today BOOLEAN,
    opponent_is_verified BOOLEAN, opponent_is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT gc.id, gc.challenge_type, gc.title, gc.description,
        gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE - gc.start_date)::INT),
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE)::INT),
        gc.status,
        COALESCE(my_cp.total_progress, 0)::INT, COALESCE(my_today.progress_value, 0)::INT,
        COALESCE(my_cp.days_completed, 0)::INT, COALESCE(my_cp.current_streak, 0)::INT,
        opp_cp.user_id, opp_up.name, opp_up.username, opp_up.profile_photo_url,
        COALESCE(opp_cp.total_progress, 0)::INT, COALESCE(opp_today.progress_value, 0)::INT,
        COALESCE(opp_cp.days_completed, 0)::INT,
        (COALESCE(my_cp.total_progress, 0) >= COALESCE(opp_cp.total_progress, 0)),
        (COALESCE(my_today.progress_value, 0) >= COALESCE(opp_today.progress_value, 0)),
        COALESCE(opp_up.is_verified, FALSE),
        COALESCE(opp_up.is_gold_verified, FALSE)
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = gc.id AND opp_cp.user_id != current_user_uuid
    JOIN user_profiles opp_up ON opp_up.id = opp_cp.user_id
    LEFT JOIN challenge_daily_progress my_today ON my_today.challenge_id = gc.id AND my_today.user_id = current_user_uuid
        AND my_today.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
    LEFT JOIN challenge_daily_progress opp_today ON opp_today.challenge_id = gc.id AND opp_today.user_id = opp_cp.user_id
        AND opp_today.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
    WHERE gc.status = 'active' AND my_cp.status = 'accepted'
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) = 2
    ORDER BY gc.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;

-- ============================================================================
-- 2. get_pending_sent_challenges — add opponent_is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_pending_sent_challenges();

CREATE OR REPLACE FUNCTION get_pending_sent_challenges()
RETURNS TABLE (
    challenge_id UUID, challenge_type TEXT, title TEXT, description TEXT, emoji TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    opponent_id UUID, opponent_name TEXT, opponent_username TEXT, opponent_photo_url TEXT,
    sent_at TIMESTAMPTZ,
    opponent_is_verified BOOLEAN, opponent_is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT gc.id, gc.challenge_type, gc.title, gc.description,
        CASE WHEN gc.challenge_type = 'steps' THEN '👟' WHEN gc.challenge_type = 'walk' THEN '🚶'
             WHEN gc.challenge_type = 'run' THEN '🏃' WHEN gc.challenge_type = 'lift' THEN '🏋️'
             WHEN gc.challenge_type = 'workout_streak' THEN '🔥' WHEN gc.challenge_type = 'active_minutes' THEN '⏱️'
             ELSE '🏆' END,
        gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        opp.user_id, up.name, up.username, up.profile_photo_url,
        gc.created_at,
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM group_challenges gc
    JOIN challenge_participants creator_cp ON creator_cp.challenge_id = gc.id
        AND creator_cp.user_id = current_user_uuid AND creator_cp.status = 'accepted'
    JOIN challenge_participants opp ON opp.challenge_id = gc.id AND opp.user_id != current_user_uuid
    JOIN user_profiles up ON up.id = opp.user_id
    WHERE gc.status = 'pending' AND gc.created_by = current_user_uuid AND opp.status = 'pending'
    ORDER BY gc.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_sent_challenges() TO authenticated;

-- ============================================================================
-- 3. get_active_group_challenges — add is_gold_verified to members JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_active_group_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, challenge_type TEXT, mode TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    days_elapsed INT, days_remaining INT, status TEXT,
    created_by UUID, member_count INT, members JSONB
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT gc.id, gc.title, gc.description, gc.challenge_type,
        COALESCE(gc.mode, 'competition'), gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE - gc.start_date)::INT),
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE)::INT),
        gc.status, gc.created_by,
        (SELECT COUNT(*)::INT FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id),
        (SELECT jsonb_agg(jsonb_build_object(
            'user_id', cp2.user_id, 'status', cp2.status,
            'total_progress', COALESCE(cp2.total_progress, 0),
            'today_progress', COALESCE(cdp.progress_value, 0),
            'days_completed', COALESCE(cp2.days_completed, 0),
            'current_streak', COALESCE(cp2.current_streak, 0),
            'name', up2.name, 'username', up2.username,
            'profile_photo_url', up2.profile_photo_url,
            'is_verified', COALESCE(up2.is_verified, FALSE),
            'is_gold_verified', COALESCE(up2.is_gold_verified, FALSE)
        ))
        FROM challenge_participants cp2
        JOIN user_profiles up2 ON up2.id = cp2.user_id
        LEFT JOIN challenge_daily_progress cdp ON cdp.challenge_id = gc.id
            AND cdp.user_id = cp2.user_id
            AND cdp.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
        WHERE cp2.challenge_id = gc.id)
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    WHERE gc.status IN ('pending', 'active')
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) > 2
    ORDER BY gc.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_active_group_challenges(TEXT) TO authenticated;

-- ============================================================================
-- 4. get_received_workouts — add sender_is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_received_workouts();

CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    workout_id UUID, sender_id UUID, sender_name TEXT, sender_username TEXT,
    sender_profile_photo_url TEXT, workout_name TEXT, workout_description TEXT,
    exercises JSONB, exercise_names TEXT[], message TEXT, status TEXT,
    estimated_duration INT, difficulty_level TEXT, created_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ, saved_to_favorites BOOLEAN,
    sender_is_verified BOOLEAN, sender_is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT sw.id, sw.sender_id, up.name, up.username, up.profile_photo_url,
        sw.workout_name, sw.workout_description, sw.exercises::JSONB, sw.exercise_names,
        sw.message, sw.status::TEXT, sw.estimated_duration, sw.difficulty_level,
        sw.created_at, sw.viewed_at, sw.saved_to_favorites,
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM shared_workouts sw
    JOIN user_profiles up ON up.id = sw.sender_id
    WHERE sw.recipient_id = current_user_uuid AND sw.status != 'deleted'
    ORDER BY sw.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_received_workouts() TO authenticated;

-- ============================================================================
-- 5. get_pending_friend_requests — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_pending_friend_requests();

CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID, from_user_id UUID, from_user_name TEXT,
    from_user_username TEXT, from_user_profile_photo_url TEXT,
    status TEXT, created_at TIMESTAMPTZ, message TEXT,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT f.id, f.requester_id, up.name, up.username, up.profile_photo_url,
        f.status::TEXT, f.created_at, f.message,
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM friendships f
    JOIN user_profiles up ON up.id = f.requester_id
    WHERE f.addressee_id = current_user_uuid AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_friend_requests() TO authenticated;

-- ============================================================================
-- 6. get_sent_friend_requests — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_sent_friend_requests();

CREATE OR REPLACE FUNCTION get_sent_friend_requests()
RETURNS TABLE (
    request_id UUID, to_user_id UUID, to_user_name TEXT,
    to_user_username TEXT, to_user_profile_photo_url TEXT,
    status TEXT, created_at TIMESTAMPTZ, message TEXT,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT f.id, f.addressee_id, up.name, up.username, up.profile_photo_url,
        f.status::TEXT, f.created_at, f.message,
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM friendships f
    JOIN user_profiles up ON up.id = f.addressee_id
    WHERE f.requester_id = current_user_uuid AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_sent_friend_requests() TO authenticated;

-- ============================================================================
-- 7. search_users — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS search_users(TEXT, INT);

CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INT DEFAULT 20)
RETURNS TABLE (
    user_id UUID, name TEXT, email TEXT, username TEXT,
    fitness_goal TEXT, experience_level TEXT, profile_photo_url TEXT,
    is_friend BOOLEAN, has_pending_request BOOLEAN,
    has_outgoing_request BOOLEAN, has_incoming_request BOOLEAN,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID; search_pattern TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    search_pattern := '%' || LOWER(TRIM(search_query)) || '%';
    RETURN QUERY
    SELECT up.id, up.name, up.email, up.username, up.fitness_goal, up.experience_level, up.profile_photo_url,
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
              OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
              OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND f.requester_id = current_user_uuid AND f.addressee_id = up.id),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND f.requester_id = up.id AND f.addressee_id = current_user_uuid),
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM user_profiles up
    WHERE up.id != current_user_uuid
      AND NOT EXISTS (SELECT 1 FROM user_blocks ub
          WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id)
             OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid))
      AND (LOWER(up.name) LIKE search_pattern OR LOWER(up.email) LIKE search_pattern OR LOWER(up.username) LIKE search_pattern)
    ORDER BY
        CASE WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
              OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 0
        WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
              OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 1
        ELSE 2 END,
        up.name ASC NULLS LAST
    LIMIT result_limit;
END;
$$;
GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- ============================================================================
-- 8a. get_community_challenge_leaderboard — add is_gold_verified to JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_community_challenge_leaderboard(
    p_challenge_id TEXT, p_limit INT DEFAULT 20, p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID, challenge_title TEXT, challenge_emoji TEXT, challenge_type TEXT,
    daily_target INT, target_unit TEXT, participant_count INT, join_code TEXT, invite_slug TEXT,
    leaderboard JSONB, my_rank INT, my_today_progress INT, my_days_completed INT,
    my_current_streak INT, my_best_streak INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID; v_challenge_id UUID; today_date DATE;
    v_my_rank INT; v_my_today INT; v_my_days INT; v_my_streak INT; v_my_best INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    SELECT ranked.rank, ranked.today_progress, ranked.days_completed, ranked.current_streak, ranked.best_streak
    INTO v_my_rank, v_my_today, v_my_days, v_my_streak, v_my_best
    FROM (
        SELECT ccp.user_id, COALESCE(cdp.progress_value, 0) AS today_progress,
            ccp.days_completed, ccp.current_streak, ccp.best_streak,
            ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC) AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp ON cdp.challenge_id = ccp.challenge_id
            AND cdp.user_id = ccp.user_id AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
    ) ranked WHERE ranked.user_id = current_user_uuid;
    RETURN QUERY
    SELECT cc.id, cc.title, cc.emoji, cc.challenge_type, cc.daily_target, cc.target_unit,
        cc.participant_count, cc.join_code, cc.invite_slug,
        (SELECT jsonb_agg(entry ORDER BY entry->>'rank') FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC),
                'user_id', ccp.user_id, 'name', up.name, 'username', up.username,
                'profile_photo_url', up.profile_photo_url,
                'today_progress', COALESCE(cdp.progress_value, 0),
                'days_completed', ccp.days_completed, 'current_streak', ccp.current_streak,
                'target_hit_today', COALESCE(cdp.target_hit, FALSE),
                'total_progress', COALESCE(ccp.total_progress, 0),
                'is_current_user', (ccp.user_id = current_user_uuid),
                'is_verified', COALESCE(up.is_verified, FALSE),
                'is_gold_verified', COALESCE(up.is_gold_verified, FALSE)
            ) AS entry
            FROM community_challenge_participants ccp
            JOIN user_profiles up ON up.id = ccp.user_id
            LEFT JOIN community_challenge_daily_progress cdp ON cdp.challenge_id = ccp.challenge_id
                AND cdp.user_id = ccp.user_id AND cdp.progress_date = today_date
            WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub
                  WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = ccp.user_id)
                     OR (ub.blocker_id = ccp.user_id AND ub.blocked_id = current_user_uuid))
            ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC LIMIT p_limit
        ) sub),
        COALESCE(v_my_rank, 0)::INT, COALESCE(v_my_today, 0)::INT,
        COALESCE(v_my_days, 0)::INT, COALESCE(v_my_streak, 0)::INT, COALESCE(v_my_best, 0)::INT
    FROM community_challenges cc WHERE cc.id = v_challenge_id;
END;
$$;
GRANT EXECUTE ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) TO authenticated;

-- ============================================================================
-- 8b. get_my_community_challenges — add is_gold_verified to top_participants JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_my_community_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, emoji TEXT, challenge_type TEXT,
    daily_target INT, target_unit TEXT, participant_count INT, max_participants INT,
    join_code TEXT, invite_slug TEXT, is_recurring BOOLEAN, is_featured BOOLEAN, is_official BOOLEAN,
    my_today_progress INT, my_days_completed INT, my_current_streak INT, my_best_streak INT, my_rank INT,
    created_by UUID, creator_name TEXT, creator_username TEXT,
    top_participants JSONB, friends_in JSONB, friends_count INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID; today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    RETURN QUERY
    SELECT cc.id, cc.title, cc.description, cc.emoji, cc.challenge_type,
        cc.daily_target, cc.target_unit, cc.participant_count, cc.max_participants,
        cc.join_code, cc.invite_slug, cc.is_recurring, cc.is_featured, cc.is_official,
        COALESCE(cdp.progress_value, 0)::INT, ccp.days_completed::INT,
        ccp.current_streak::INT, ccp.best_streak::INT,
        (SELECT COUNT(*)::INT + 1 FROM community_challenge_participants other_ccp
            LEFT JOIN community_challenge_daily_progress other_cdp ON other_cdp.challenge_id = other_ccp.challenge_id
                AND other_cdp.user_id = other_ccp.user_id AND other_cdp.progress_date = today_date
            WHERE other_ccp.challenge_id = cc.id AND other_ccp.is_active = TRUE
            AND other_ccp.user_id != current_user_uuid
            AND COALESCE(other_cdp.progress_value, 0) > COALESCE(cdp.progress_value, 0))::INT,
        cc.created_by, creator_up.name, creator_up.username,
        (SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB) FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC),
                'user_id', sub_ccp.user_id, 'name', sub_up.name, 'username', sub_up.username,
                'profile_photo_url', sub_up.profile_photo_url,
                'today_progress', COALESCE(sub_cdp.progress_value, 0),
                'days_completed', sub_ccp.days_completed, 'current_streak', sub_ccp.current_streak,
                'best_streak', sub_ccp.best_streak,
                'target_hit_today', COALESCE(sub_cdp.target_hit, FALSE),
                'is_current_user', (sub_ccp.user_id = current_user_uuid),
                'is_friend', are_friends(current_user_uuid, sub_ccp.user_id),
                'is_verified', COALESCE(sub_up.is_verified, FALSE),
                'is_gold_verified', COALESCE(sub_up.is_gold_verified, FALSE)
            ) AS entry
            FROM community_challenge_participants sub_ccp
            JOIN user_profiles sub_up ON sub_up.id = sub_ccp.user_id
            LEFT JOIN community_challenge_daily_progress sub_cdp ON sub_cdp.challenge_id = sub_ccp.challenge_id
                AND sub_cdp.user_id = sub_ccp.user_id AND sub_cdp.progress_date = today_date
            WHERE sub_ccp.challenge_id = cc.id AND sub_ccp.is_active = TRUE
            ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC
            LIMIT LEAST(10, GREATEST(5, cc.participant_count / 10))
        ) sub),
        (SELECT COALESCE(jsonb_agg(fi), '[]'::JSONB) FROM (
            SELECT jsonb_build_object('user_id', f_ccp.user_id, 'name', f_up.name,
                'username', f_up.username, 'profile_photo_url', f_up.profile_photo_url) AS fi
            FROM community_challenge_participants f_ccp
            JOIN user_profiles f_up ON f_up.id = f_ccp.user_id
            WHERE f_ccp.challenge_id = cc.id AND f_ccp.is_active = TRUE
                AND are_friends(current_user_uuid, f_ccp.user_id)
            ORDER BY f_ccp.joined_at ASC LIMIT 5
        ) sub2),
        (SELECT COUNT(*)::INT FROM community_challenge_participants f_ccp2
            WHERE f_ccp2.challenge_id = cc.id AND f_ccp2.is_active = TRUE
            AND are_friends(current_user_uuid, f_ccp2.user_id))::INT
    FROM community_challenge_participants ccp
    JOIN community_challenges cc ON cc.id = ccp.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = cc.created_by
    LEFT JOIN community_challenge_daily_progress cdp ON cdp.challenge_id = cc.id
        AND cdp.user_id = current_user_uuid AND cdp.progress_date = today_date
    WHERE ccp.user_id = current_user_uuid AND ccp.is_active = TRUE AND cc.status = 'active'
    ORDER BY cc.is_official DESC, cc.participant_count DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_my_community_challenges(TEXT) TO authenticated;

-- ============================================================================
-- 8c. get_community_challenge_detail — add is_gold_verified to top_leaderboard JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_community_challenge_detail(p_challenge_id TEXT, p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, emoji TEXT, challenge_type TEXT,
    daily_target INT, target_unit TEXT, participant_count INT, max_participants INT,
    join_code TEXT, invite_slug TEXT, is_recurring BOOLEAN, total_completions INT,
    my_today_progress INT, my_days_completed INT, my_current_streak INT, my_best_streak INT,
    my_rank INT, my_total_progress INT,
    avg_today_progress INT, top_today_progress INT, avg_streak NUMERIC,
    total_active_today INT, completion_rate_today NUMERIC,
    friends_in JSONB, friends_count INT, top_leaderboard JSONB, encouragement TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID; v_challenge_id UUID; today_date DATE;
    v_my_today INT; v_my_days INT; v_my_streak INT; v_my_best INT; v_my_rank INT; v_my_total INT;
    v_avg_today INT; v_top_today INT; v_avg_streak NUMERIC; v_active_today INT; v_completion_rate NUMERIC;
    v_encouragement TEXT; v_participant_count INT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    SELECT cc.participant_count INTO v_participant_count FROM community_challenges cc WHERE cc.id = v_challenge_id;
    SELECT COALESCE(cdp.progress_value, 0), ccp.days_completed, ccp.current_streak, ccp.best_streak, ccp.total_progress
    INTO v_my_today, v_my_days, v_my_streak, v_my_best, v_my_total
    FROM community_challenge_participants ccp
    LEFT JOIN community_challenge_daily_progress cdp ON cdp.challenge_id = ccp.challenge_id
        AND cdp.user_id = ccp.user_id AND cdp.progress_date = today_date
    WHERE ccp.challenge_id = v_challenge_id AND ccp.user_id = current_user_uuid;
    SELECT COUNT(*)::INT + 1 INTO v_my_rank
    FROM community_challenge_participants other_ccp
    LEFT JOIN community_challenge_daily_progress other_cdp ON other_cdp.challenge_id = other_ccp.challenge_id
        AND other_cdp.user_id = other_ccp.user_id AND other_cdp.progress_date = today_date
    WHERE other_ccp.challenge_id = v_challenge_id AND other_ccp.is_active = TRUE
        AND other_ccp.user_id != current_user_uuid
        AND COALESCE(other_cdp.progress_value, 0) > COALESCE(v_my_today, 0);
    SELECT COALESCE(AVG(COALESCE(cdp.progress_value, 0)), 0)::INT,
        COALESCE(MAX(COALESCE(cdp.progress_value, 0)), 0)::INT,
        COALESCE(AVG(ccp.current_streak), 0),
        COUNT(*) FILTER (WHERE COALESCE(cdp.progress_value, 0) > 0)::INT,
        CASE WHEN COUNT(*) > 0 THEN (COUNT(*) FILTER (WHERE COALESCE(cdp.target_hit, FALSE))::NUMERIC / COUNT(*)::NUMERIC * 100) ELSE 0 END
    INTO v_avg_today, v_top_today, v_avg_streak, v_active_today, v_completion_rate
    FROM community_challenge_participants ccp
    LEFT JOIN community_challenge_daily_progress cdp ON cdp.challenge_id = ccp.challenge_id
        AND cdp.user_id = ccp.user_id AND cdp.progress_date = today_date
    WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE;
    v_encouragement := CASE
        WHEN v_my_today IS NULL THEN '💪 Join your friends in this community challenge!'
        WHEN v_my_rank = 1 THEN '🏆 You''re leading this community! Keep crushing it!'
        WHEN v_my_rank <= 3 THEN '🔥 Top 3! You''re on fire — just a bit more to take the crown!'
        WHEN v_my_rank <= 5 THEN '💪 Top 5! You''re outperforming most of the community!'
        WHEN v_my_streak > 0 AND v_my_streak >= v_avg_streak THEN '🔥 ' || v_my_streak || '-day streak! You''re more consistent than the average!'
        WHEN COALESCE(v_my_today, 0) >= v_avg_today AND v_avg_today > 0 THEN '📈 You''re above the community average today — keep pushing!'
        WHEN COALESCE(v_my_today, 0) > 0 THEN '👏 Great start today! A little more to match the community average.'
        ELSE '⚡ Your friends are active today — time to log some progress!'
    END;
    RETURN QUERY
    SELECT cc.id, cc.title, cc.description, cc.emoji, cc.challenge_type,
        cc.daily_target, cc.target_unit, cc.participant_count, cc.max_participants,
        cc.join_code, cc.invite_slug, cc.is_recurring, cc.total_completions,
        COALESCE(v_my_today, 0)::INT, COALESCE(v_my_days, 0)::INT,
        COALESCE(v_my_streak, 0)::INT, COALESCE(v_my_best, 0)::INT,
        COALESCE(v_my_rank, 0)::INT, COALESCE(v_my_total, 0)::INT,
        v_avg_today, v_top_today, v_avg_streak, v_active_today, v_completion_rate,
        (SELECT COALESCE(jsonb_agg(fi), '[]'::JSONB) FROM (
            SELECT jsonb_build_object('user_id', ccp2.user_id, 'name', up2.name,
                'username', up2.username, 'profile_photo_url', up2.profile_photo_url,
                'today_progress', COALESCE(cdp2.progress_value, 0), 'current_streak', ccp2.current_streak) AS fi
            FROM community_challenge_participants ccp2
            JOIN user_profiles up2 ON up2.id = ccp2.user_id
            LEFT JOIN community_challenge_daily_progress cdp2 ON cdp2.challenge_id = ccp2.challenge_id
                AND cdp2.user_id = ccp2.user_id AND cdp2.progress_date = today_date
            WHERE ccp2.challenge_id = cc.id AND ccp2.is_active = TRUE
                AND are_friends(current_user_uuid, ccp2.user_id)
            ORDER BY COALESCE(cdp2.progress_value, 0) DESC LIMIT 10
        ) sub),
        (SELECT COUNT(*)::INT FROM community_challenge_participants ccp3
            WHERE ccp3.challenge_id = cc.id AND ccp3.is_active = TRUE
            AND are_friends(current_user_uuid, ccp3.user_id)),
        (SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB) FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp4.progress_value, 0) DESC, ccp4.days_completed DESC),
                'user_id', ccp4.user_id, 'name', up4.name, 'username', up4.username,
                'profile_photo_url', up4.profile_photo_url,
                'today_progress', COALESCE(cdp4.progress_value, 0),
                'days_completed', ccp4.days_completed, 'current_streak', ccp4.current_streak,
                'best_streak', ccp4.best_streak,
                'target_hit_today', COALESCE(cdp4.target_hit, FALSE),
                'is_current_user', (ccp4.user_id = current_user_uuid),
                'is_friend', are_friends(current_user_uuid, ccp4.user_id),
                'is_verified', COALESCE(up4.is_verified, FALSE),
                'is_gold_verified', COALESCE(up4.is_gold_verified, FALSE)
            ) AS entry
            FROM community_challenge_participants ccp4
            JOIN user_profiles up4 ON up4.id = ccp4.user_id
            LEFT JOIN community_challenge_daily_progress cdp4 ON cdp4.challenge_id = ccp4.challenge_id
                AND cdp4.user_id = ccp4.user_id AND cdp4.progress_date = today_date
            WHERE ccp4.challenge_id = cc.id AND ccp4.is_active = TRUE
            ORDER BY COALESCE(cdp4.progress_value, 0) DESC, ccp4.days_completed DESC LIMIT 10
        ) sub),
        v_encouragement
    FROM community_challenges cc WHERE cc.id = v_challenge_id;
END;
$$;
GRANT EXECUTE ON FUNCTION get_community_challenge_detail(TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 9a. get_private_challenge_detail — add is_gold_verified to leaderboard JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_private_challenge_detail(p_challenge_id TEXT, p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, emoji TEXT, challenge_type TEXT,
    daily_target INT, target_unit TEXT, member_count INT, max_members INT, join_code TEXT,
    is_recurring BOOLEAN, show_leaderboard BOOLEAN, allow_member_invites BOOLEAN,
    notifications_enabled BOOLEAN, total_completions INT, created_by UUID, status TEXT,
    created_at TIMESTAMPTZ,
    my_today_progress INT, my_days_completed INT, my_current_streak INT, my_best_streak INT,
    my_total_progress INT, my_rank INT, my_role TEXT,
    avg_today_progress INT, top_today_progress INT, total_active_today INT,
    completion_rate_today DOUBLE PRECISION,
    leaderboard JSONB, pending_invites_count INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID; v_challenge_id UUID; today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    IF NOT EXISTS (SELECT 1 FROM private_challenge_members pcm_check
        WHERE pcm_check.challenge_id = v_challenge_id AND pcm_check.user_id = current_user_uuid AND pcm_check.is_active = TRUE
    ) THEN RAISE EXCEPTION 'You are not a member of this challenge'; END IF;
    RETURN QUERY
    SELECT pc.id, pc.title, pc.description, pc.emoji, pc.challenge_type,
        pc.daily_target, pc.target_unit, pc.member_count, pc.max_members, pc.join_code,
        pc.is_recurring, pc.show_leaderboard, pc.allow_member_invites, pc.notifications_enabled,
        pc.total_completions, pc.created_by, pc.status, pc.created_at,
        COALESCE((SELECT dp.progress_value FROM private_challenge_daily_progress dp WHERE dp.challenge_id = v_challenge_id AND dp.user_id = current_user_uuid AND dp.progress_date = today_date), 0)::INT,
        COALESCE((SELECT m.days_completed FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.current_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.best_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.total_progress FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        (SELECT COUNT(*)::INT + 1 FROM private_challenge_members other_m
            LEFT JOIN private_challenge_daily_progress other_dp ON other_dp.challenge_id = other_m.challenge_id AND other_dp.user_id = other_m.user_id AND other_dp.progress_date = today_date
            WHERE other_m.challenge_id = v_challenge_id AND other_m.is_active = TRUE AND other_m.user_id != current_user_uuid
            AND COALESCE(other_dp.progress_value, 0) > COALESCE(
                (SELECT dp2.progress_value FROM private_challenge_daily_progress dp2 WHERE dp2.challenge_id = v_challenge_id AND dp2.user_id = current_user_uuid AND dp2.progress_date = today_date), 0
            ))::INT,
        (SELECT m2.role FROM private_challenge_members m2 WHERE m2.challenge_id = v_challenge_id AND m2.user_id = current_user_uuid)::TEXT,
        COALESCE((SELECT AVG(COALESCE(dp3.progress_value, 0))::INT FROM private_challenge_members m3 LEFT JOIN private_challenge_daily_progress dp3 ON dp3.challenge_id = m3.challenge_id AND dp3.user_id = m3.user_id AND dp3.progress_date = today_date WHERE m3.challenge_id = v_challenge_id AND m3.is_active = TRUE), 0)::INT,
        COALESCE((SELECT MAX(COALESCE(dp4.progress_value, 0))::INT FROM private_challenge_members m4 LEFT JOIN private_challenge_daily_progress dp4 ON dp4.challenge_id = m4.challenge_id AND dp4.user_id = m4.user_id AND dp4.progress_date = today_date WHERE m4.challenge_id = v_challenge_id AND m4.is_active = TRUE), 0)::INT,
        (SELECT COUNT(*)::INT FROM private_challenge_daily_progress dp5 WHERE dp5.challenge_id = v_challenge_id AND dp5.progress_date = today_date AND dp5.progress_value > 0)::INT,
        CASE WHEN pc.member_count > 0 THEN
            (SELECT COUNT(*)::DOUBLE PRECISION / pc.member_count FROM private_challenge_daily_progress dp6 WHERE dp6.challenge_id = v_challenge_id AND dp6.progress_date = today_date AND dp6.target_hit = TRUE)
        ELSE 0 END,
        (SELECT jsonb_agg(entry ORDER BY entry->>'rank') FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC),
                'user_id', m5.user_id, 'name', up5.name, 'username', up5.username,
                'profile_photo_url', up5.profile_photo_url, 'role', m5.role,
                'today_progress', COALESCE(dp7.progress_value, 0),
                'days_completed', m5.days_completed, 'current_streak', m5.current_streak,
                'best_streak', m5.best_streak,
                'target_hit_today', COALESCE(dp7.target_hit, FALSE),
                'is_current_user', (m5.user_id = current_user_uuid),
                'is_verified', COALESCE(up5.is_verified, FALSE),
                'is_gold_verified', COALESCE(up5.is_gold_verified, FALSE)
            ) AS entry
            FROM private_challenge_members m5
            JOIN user_profiles up5 ON up5.id = m5.user_id
            LEFT JOIN private_challenge_daily_progress dp7 ON dp7.challenge_id = m5.challenge_id AND dp7.user_id = m5.user_id AND dp7.progress_date = today_date
            WHERE m5.challenge_id = v_challenge_id AND m5.is_active = TRUE
            ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC
        ) sub),
        (SELECT COUNT(*)::INT FROM private_challenge_invites pci WHERE pci.challenge_id = v_challenge_id AND pci.status = 'pending')
    FROM private_challenges pc WHERE pc.id = v_challenge_id;
END;
$$;
GRANT EXECUTE ON FUNCTION get_private_challenge_detail(TEXT, TEXT) TO authenticated;

-- ============================================================================
-- 9b. get_my_private_challenges — add is_gold_verified to top_members JSON
-- ============================================================================
CREATE OR REPLACE FUNCTION get_my_private_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, emoji TEXT, challenge_type TEXT,
    daily_target INT, target_unit TEXT, member_count INT, max_members INT, join_code TEXT,
    is_recurring BOOLEAN, show_leaderboard BOOLEAN, allow_member_invites BOOLEAN,
    my_today_progress INT, my_days_completed INT, my_current_streak INT, my_role TEXT, my_rank INT,
    created_by UUID, creator_name TEXT, creator_username TEXT, status TEXT,
    top_members JSONB, last_chat_message TEXT, last_chat_sender TEXT,
    last_chat_at TIMESTAMPTZ, unread_count INT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE current_user_uuid UUID; today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    RETURN QUERY
    SELECT pc.id, pc.title, pc.description, pc.emoji, pc.challenge_type,
        pc.daily_target, pc.target_unit, pc.member_count, pc.max_members, pc.join_code,
        pc.is_recurring, pc.show_leaderboard, pc.allow_member_invites,
        COALESCE(pcdp.progress_value, 0)::INT, pcm.days_completed::INT,
        pcm.current_streak::INT, pcm.role,
        (SELECT COUNT(*)::INT + 1 FROM private_challenge_members other_pcm
            LEFT JOIN private_challenge_daily_progress other_pcdp ON other_pcdp.challenge_id = other_pcm.challenge_id
                AND other_pcdp.user_id = other_pcm.user_id AND other_pcdp.progress_date = today_date
            WHERE other_pcm.challenge_id = pc.id AND other_pcm.is_active = TRUE AND other_pcm.user_id != current_user_uuid
            AND COALESCE(other_pcdp.progress_value, 0) > COALESCE(pcdp.progress_value, 0))::INT,
        pc.created_by, creator_up.name, creator_up.username, pc.status,
        (SELECT jsonb_agg(member_info ORDER BY member_info->>'today_progress' DESC) FROM (
            SELECT jsonb_build_object(
                'user_id', m.user_id, 'name', up2.name, 'username', up2.username,
                'profile_photo_url', up2.profile_photo_url, 'role', m.role,
                'today_progress', COALESCE(dp.progress_value, 0),
                'is_verified', COALESCE(up2.is_verified, FALSE),
                'is_gold_verified', COALESCE(up2.is_gold_verified, FALSE)
            ) AS member_info
            FROM private_challenge_members m
            JOIN user_profiles up2 ON up2.id = m.user_id
            LEFT JOIN private_challenge_daily_progress dp ON dp.challenge_id = m.challenge_id AND dp.user_id = m.user_id AND dp.progress_date = today_date
            WHERE m.challenge_id = pc.id AND m.is_active = TRUE
            ORDER BY COALESCE(dp.progress_value, 0) DESC LIMIT 5
        ) sub),
        (SELECT pcc.content FROM private_challenge_chat pcc WHERE pcc.challenge_id = pc.id ORDER BY pcc.created_at DESC LIMIT 1),
        (SELECT up3.name FROM private_challenge_chat pcc2 JOIN user_profiles up3 ON up3.id = pcc2.sender_id WHERE pcc2.challenge_id = pc.id ORDER BY pcc2.created_at DESC LIMIT 1),
        (SELECT pcc3.created_at FROM private_challenge_chat pcc3 WHERE pcc3.challenge_id = pc.id ORDER BY pcc3.created_at DESC LIMIT 1),
        0::INT
    FROM private_challenge_members pcm
    JOIN private_challenges pc ON pc.id = pcm.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = pc.created_by
    LEFT JOIN private_challenge_daily_progress pcdp ON pcdp.challenge_id = pc.id AND pcdp.user_id = current_user_uuid AND pcdp.progress_date = today_date
    WHERE pcm.user_id = current_user_uuid AND pcm.is_active = TRUE AND pc.status = 'active'
    ORDER BY pcm.last_active_at DESC NULLS LAST;
END;
$$;
GRANT EXECUTE ON FUNCTION get_my_private_challenges(TEXT) TO authenticated;

COMMIT;
