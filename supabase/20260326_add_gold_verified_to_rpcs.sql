-- ============================================================================
-- ADD is_gold_verified TO ALL RPCs THAT ALREADY RETURN is_verified
-- Patch: adds COALESCE(up.is_gold_verified, FALSE) alongside is_verified
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. get_friends — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_friends();

CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID, friend_id UUID, friend_name TEXT, friend_email TEXT,
    friend_username TEXT, fitness_goal TEXT, experience_level TEXT,
    profile_photo_url TEXT, friends_since TIMESTAMPTZ, total_workouts_shared INT,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT f.id, CASE WHEN f.requester_id = current_user_uuid THEN f.addressee_id ELSE f.requester_id END,
        up.name, up.email, up.username, up.fitness_goal, up.experience_level, up.profile_photo_url,
        f.created_at,
        COALESCE((SELECT COUNT(*)::INT FROM shared_workouts sw
            WHERE (sw.sender_id = current_user_uuid AND sw.recipient_id = up.id)
               OR (sw.sender_id = up.id AND sw.recipient_id = current_user_uuid)), 0),
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM friendships f
    JOIN user_profiles up ON up.id = CASE WHEN f.requester_id = current_user_uuid THEN f.addressee_id ELSE f.requester_id END
    WHERE (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid) AND f.status = 'accepted'
    ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;

-- ============================================================================
-- 2. get_friend_activity_feed — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_friend_activity_feed(INT, INT);

CREATE OR REPLACE FUNCTION get_friend_activity_feed(p_limit INT DEFAULT 20, p_offset INT DEFAULT 0)
RETURNS TABLE (
    activity_id UUID, user_id UUID, user_name TEXT, user_username TEXT,
    user_profile_photo_url TEXT, user_level INT, activity_type TEXT,
    workout_id TEXT, metadata JSONB, created_at TIMESTAMPTZ, reactions JSONB,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT faf.id, faf.user_id, up.name, up.username, up.profile_photo_url,
        COALESCE((up.xp / 100) + 1, 1), faf.activity_type, faf.workout_id, faf.metadata, faf.created_at,
        COALESCE((SELECT jsonb_agg(jsonb_build_object('sender_id', ar.sender_id, 'sender_name', sp.name, 'emoji', ar.emoji))
            FROM activity_reactions ar JOIN user_profiles sp ON sp.id = ar.sender_id WHERE ar.activity_id = faf.id), '[]'::JSONB),
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM friend_activity_feed faf
    JOIN user_profiles up ON up.id = faf.user_id
    WHERE faf.user_id IN (
        SELECT CASE WHEN f.requester_id = current_user_uuid THEN f.addressee_id ELSE f.requester_id END
        FROM friendships f WHERE f.status = 'accepted'
          AND (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid)
    )
    ORDER BY faf.created_at DESC LIMIT p_limit OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION get_friend_activity_feed(INT, INT) TO authenticated;

-- ============================================================================
-- 3. League RPCs — add is_gold_verified to leaderboard entries
-- ============================================================================

CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE v_week_start DATE; v_user_tier INTEGER; v_group_id UUID; v_membership_id UUID;
    v_tier_info RECORD; v_days_remaining INTEGER; v_result JSON;
    v_best_group_id UUID; v_best_overlap INTEGER := -1; v_candidate RECORD; v_overlap INTEGER;
BEGIN
    PERFORM process_past_league_weeks();
    v_week_start := get_current_week_monday();
    v_days_remaining := 6 - (CURRENT_DATE - v_week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;
    INSERT INTO user_league_tier (user_id, current_tier) VALUES (p_user_id, 1) ON CONFLICT (user_id) DO NOTHING;
    SELECT current_tier INTO v_user_tier FROM user_league_tier WHERE user_id = p_user_id;
    SELECT lm.id, lm.group_id INTO v_membership_id, v_group_id
    FROM league_members lm JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id AND lg.week_start = v_week_start;
    IF v_membership_id IS NULL THEN
        FOR v_candidate IN
            SELECT lg.id, lg.member_count FROM league_groups lg
            WHERE lg.tier_rank = v_user_tier AND lg.week_start = v_week_start
              AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
              AND NOT lg.is_processed ORDER BY lg.member_count DESC
        LOOP
            SELECT COUNT(*)::INT INTO v_overlap FROM league_members lm2
            JOIN friendships f ON ((f.requester_id = p_user_id AND f.addressee_id = lm2.user_id)
                OR (f.addressee_id = p_user_id AND f.requester_id = lm2.user_id))
            WHERE lm2.group_id = v_candidate.id AND f.status = 'accepted';
            IF v_overlap > v_best_overlap THEN v_best_overlap := v_overlap; v_best_group_id := v_candidate.id; END IF;
        END LOOP;
        v_group_id := v_best_group_id;
        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count) VALUES (v_user_tier, v_week_start, 0) RETURNING id INTO v_group_id;
        END IF;
        INSERT INTO league_members (user_id, group_id, points) VALUES (p_user_id, v_group_id, 0) ON CONFLICT (user_id, group_id) DO NOTHING;
        UPDATE league_groups SET member_count = member_count + 1 WHERE id = v_group_id;
    END IF;
    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;
    WITH my_friends AS (
        SELECT CASE WHEN requester_id = p_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships WHERE (requester_id = p_user_id OR addressee_id = p_user_id) AND status = 'accepted'
    )
    SELECT json_build_object(
        'group_id', v_group_id, 'tier_rank', v_user_tier, 'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji, 'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count, 'relegation_count', v_tier_info.relegation_count,
        'week_start', v_week_start, 'days_remaining', v_days_remaining,
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members WHERE group_id = v_group_id) sub WHERE user_id = p_user_id), 1),
        'group_size', (SELECT member_count FROM league_groups WHERE id = v_group_id),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username, up.profile_photo_url, lm.points, lm.workouts_completed,
                ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                (lm.user_id = p_user_id) AS is_current_user,
                (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                CASE WHEN lm.user_id = p_user_id THEN NULL WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                    ELSE (SELECT COUNT(DISTINCT mf.fid)::INT FROM my_friends mf
                        JOIN friendships f3 ON ((f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                            OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id)) WHERE f3.status = 'accepted')
                END AS mutual_friend_count,
                (COALESCE(up.is_verified, FALSE) OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7) AS is_verified,
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified
            FROM league_members lm LEFT JOIN user_profiles up ON up.id = lm.user_id
            WHERE lm.group_id = v_group_id
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id) OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;
    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION get_league_leaderboard(p_user_id UUID, p_group_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER STABLE
AS $$
DECLARE v_group RECORD; v_tier_info RECORD; v_days_remaining INTEGER; v_result JSON;
BEGIN
    SELECT * INTO v_group FROM league_groups WHERE id = p_group_id;
    IF v_group IS NULL THEN RETURN json_build_object('error', 'group_not_found'); END IF;
    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_group.tier_rank;
    v_days_remaining := 6 - (CURRENT_DATE - v_group.week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;
    WITH my_friends AS (
        SELECT CASE WHEN requester_id = p_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships WHERE (requester_id = p_user_id OR addressee_id = p_user_id) AND status = 'accepted'
    )
    SELECT json_build_object(
        'group_id', v_group.id, 'tier_rank', v_group.tier_rank, 'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji, 'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count, 'relegation_count', v_tier_info.relegation_count,
        'week_start', v_group.week_start, 'days_remaining', v_days_remaining,
        'group_size', v_group.member_count,
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = p_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members WHERE group_id = p_group_id) sub WHERE user_id = p_user_id), 1),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username, up.profile_photo_url, lm.points, lm.workouts_completed,
                ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                (lm.user_id = p_user_id) AS is_current_user,
                (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                CASE WHEN lm.user_id = p_user_id THEN NULL WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                    ELSE (SELECT COUNT(DISTINCT mf.fid)::INT FROM my_friends mf
                        JOIN friendships f3 ON ((f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                            OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id)) WHERE f3.status = 'accepted')
                END AS mutual_friend_count,
                (COALESCE(up.is_verified, FALSE) OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7) AS is_verified,
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified
            FROM league_members lm LEFT JOIN user_profiles up ON up.id = lm.user_id
            WHERE lm.group_id = p_group_id
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id) OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;
    RETURN v_result;
END;
$$;

-- ============================================================================
-- 4. search_users — add is_gold_verified
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
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id) OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id) OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending' AND f.requester_id = current_user_uuid AND f.addressee_id = up.id),
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending' AND f.requester_id = up.id AND f.addressee_id = current_user_uuid),
        COALESCE(up.is_verified, FALSE),
        COALESCE(up.is_gold_verified, FALSE)
    FROM user_profiles up
    WHERE up.id != current_user_uuid
      AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id) OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid))
      AND (LOWER(up.name) LIKE search_pattern OR LOWER(up.email) LIKE search_pattern OR LOWER(up.username) LIKE search_pattern)
    ORDER BY CASE WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id) OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 0
        WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id) OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 1
        ELSE 2 END, up.name ASC NULLS LAST
    LIMIT result_limit;
END;
$$;
GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- ============================================================================
-- 5. Friend requests — add is_gold_verified
-- ============================================================================
DROP FUNCTION IF EXISTS get_pending_friend_requests();
CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID, from_user_id UUID, from_user_name TEXT,
    from_user_username TEXT, from_user_profile_photo_url TEXT,
    status TEXT, created_at TIMESTAMPTZ, message TEXT,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT f.id, f.requester_id, up.name, up.username, up.profile_photo_url,
        f.status::TEXT, f.created_at, f.message,
        COALESCE(up.is_verified, FALSE), COALESCE(up.is_gold_verified, FALSE)
    FROM friendships f JOIN user_profiles up ON up.id = f.requester_id
    WHERE f.addressee_id = current_user_uuid AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_friend_requests() TO authenticated;

DROP FUNCTION IF EXISTS get_sent_friend_requests();
CREATE OR REPLACE FUNCTION get_sent_friend_requests()
RETURNS TABLE (
    request_id UUID, to_user_id UUID, to_user_name TEXT,
    to_user_username TEXT, to_user_profile_photo_url TEXT,
    status TEXT, created_at TIMESTAMPTZ, message TEXT,
    is_verified BOOLEAN, is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT f.id, f.addressee_id, up.name, up.username, up.profile_photo_url,
        f.status::TEXT, f.created_at, f.message,
        COALESCE(up.is_verified, FALSE), COALESCE(up.is_gold_verified, FALSE)
    FROM friendships f JOIN user_profiles up ON up.id = f.addressee_id
    WHERE f.requester_id = current_user_uuid AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_sent_friend_requests() TO authenticated;

-- ============================================================================
-- 6. get_received_workouts — add sender_is_gold_verified
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
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT sw.id, sw.sender_id, up.name, up.username, up.profile_photo_url,
        sw.workout_name, sw.workout_description, sw.exercises::JSONB, sw.exercise_names,
        sw.message, sw.status::TEXT, sw.estimated_duration, sw.difficulty_level,
        sw.created_at, sw.viewed_at, sw.saved_to_favorites,
        COALESCE(up.is_verified, FALSE), COALESCE(up.is_gold_verified, FALSE)
    FROM shared_workouts sw JOIN user_profiles up ON up.id = sw.sender_id
    WHERE sw.recipient_id = current_user_uuid AND sw.status != 'deleted'
    ORDER BY sw.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_received_workouts() TO authenticated;

-- ============================================================================
-- 7. Challenge RPCs — add is_gold_verified to opponent/member data
-- ============================================================================

-- 7a. get_active_challenges
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
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT gc.id, gc.challenge_type, gc.title, gc.description, gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE - gc.start_date)::INT),
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE)::INT),
        gc.status, COALESCE(my_cp.total_progress, 0)::INT, COALESCE(my_today.progress_value, 0)::INT,
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

-- 7b. get_pending_sent_challenges
DROP FUNCTION IF EXISTS get_pending_sent_challenges();
CREATE OR REPLACE FUNCTION get_pending_sent_challenges()
RETURNS TABLE (
    challenge_id UUID, challenge_type TEXT, title TEXT, description TEXT, emoji TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    opponent_id UUID, opponent_name TEXT, opponent_username TEXT, opponent_photo_url TEXT,
    sent_at TIMESTAMPTZ, opponent_is_verified BOOLEAN, opponent_is_gold_verified BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
        gc.daily_target, gc.total_target, gc.target_unit, gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        opp.user_id, up.name, up.username, up.profile_photo_url, gc.created_at,
        COALESCE(up.is_verified, FALSE), COALESCE(up.is_gold_verified, FALSE)
    FROM group_challenges gc
    JOIN challenge_participants creator_cp ON creator_cp.challenge_id = gc.id AND creator_cp.user_id = current_user_uuid AND creator_cp.status = 'accepted'
    JOIN challenge_participants opp ON opp.challenge_id = gc.id AND opp.user_id != current_user_uuid
    JOIN user_profiles up ON up.id = opp.user_id
    WHERE gc.status = 'pending' AND gc.created_by = current_user_uuid AND opp.status = 'pending'
    ORDER BY gc.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_pending_sent_challenges() TO authenticated;

-- 7c. get_active_group_challenges — add is_gold_verified to members JSON
CREATE OR REPLACE FUNCTION get_active_group_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, challenge_type TEXT, mode TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    days_elapsed INT, days_remaining INT, status TEXT,
    created_by UUID, member_count INT, members JSONB
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    RETURN QUERY
    SELECT gc.id, gc.title, gc.description, gc.challenge_type, COALESCE(gc.mode, 'competition'),
        gc.daily_target, gc.total_target, gc.target_unit, gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
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
            'name', up2.name, 'username', up2.username, 'profile_photo_url', up2.profile_photo_url,
            'is_verified', COALESCE(up2.is_verified, FALSE),
            'is_gold_verified', COALESCE(up2.is_gold_verified, FALSE)
        ))
        FROM challenge_participants cp2
        JOIN user_profiles up2 ON up2.id = cp2.user_id
        LEFT JOIN challenge_daily_progress cdp ON cdp.challenge_id = gc.id AND cdp.user_id = cp2.user_id
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

COMMIT;
