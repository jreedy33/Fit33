-- ============================================================================
-- Migration: Fix search_users, add block filtering across all discovery & leaderboard RPCs
-- Date: 2025-03-25
-- 
-- Problems fixed:
-- 1. search_users was overwritten (20260322) losing friendship flags + block filtering
-- 2. get_people_you_may_know has no block filtering
-- 3. match_contacts_by_phone has no block filtering
-- 4. Community & league leaderboard RPCs have no block filtering
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. RESTORE search_users WITH friendship flags + block filtering
--    Matches the Swift client's UserSearchResult model which expects:
--    user_id, name, email, username, fitness_goal, experience_level,
--    profile_photo_url, is_friend, has_pending_request,
--    has_outgoing_request, has_incoming_request
-- ============================================================================

DROP FUNCTION IF EXISTS search_users(TEXT, INT);

CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INT DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    profile_photo_url TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN,
    has_outgoing_request BOOLEAN,
    has_incoming_request BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    search_pattern TEXT;
BEGIN
    current_user_uuid := auth.uid();

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    search_pattern := '%' || LOWER(TRIM(search_query)) || '%';

    RETURN QUERY
    SELECT
        up.id AS user_id,
        up.name,
        up.email,
        up.username,
        up.fitness_goal,
        up.experience_level,
        up.profile_photo_url,
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))
        ) AS is_friend,
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))
        ) AS has_pending_request,
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND f.requester_id = current_user_uuid
              AND f.addressee_id = up.id
        ) AS has_outgoing_request,
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND f.requester_id = up.id
              AND f.addressee_id = current_user_uuid
        ) AS has_incoming_request
    FROM user_profiles up
    WHERE up.id != current_user_uuid
      AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id)
             OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid)
      )
      AND (
          LOWER(up.name) LIKE search_pattern
          OR LOWER(up.email) LIKE search_pattern
          OR LOWER(up.username) LIKE search_pattern
      )
    ORDER BY
        CASE
            WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
                AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                  OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 0
            WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
                AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                  OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 1
            ELSE 2
        END,
        up.name ASC NULLS LAST
    LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- ============================================================================
-- 2. ADD BLOCK FILTERING TO get_people_you_may_know
-- ============================================================================

DROP FUNCTION IF EXISTS get_people_you_may_know(INT);

CREATE OR REPLACE FUNCTION get_people_you_may_know(
    result_limit INT DEFAULT 20
)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    profile_photo_url TEXT,
    phone_number TEXT,
    fitness_goal TEXT,
    is_friend BOOLEAN,
    has_outgoing_request BOOLEAN,
    has_incoming_request BOOLEAN,
    mutual_friend_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    WITH my_friends AS (
        SELECT CASE 
            WHEN requester_id = current_user_uuid THEN addressee_id
            ELSE requester_id
        END AS friend_id
        FROM friendships
        WHERE (requester_id = current_user_uuid OR addressee_id = current_user_uuid)
          AND status = 'accepted'
    ),
    friends_of_friends AS (
        SELECT 
            CASE 
                WHEN f.requester_id = mf.friend_id THEN f.addressee_id
                ELSE f.requester_id
            END AS suggested_user_id,
            COUNT(DISTINCT mf.friend_id) AS mutual_count
        FROM friendships f
        INNER JOIN my_friends mf ON (f.requester_id = mf.friend_id OR f.addressee_id = mf.friend_id)
        WHERE f.status = 'accepted'
        GROUP BY suggested_user_id
        HAVING CASE 
            WHEN f.requester_id = mf.friend_id THEN f.addressee_id
            ELSE f.requester_id
        END != current_user_uuid
        AND CASE 
            WHEN f.requester_id = mf.friend_id THEN f.addressee_id
            ELSE f.requester_id
        END NOT IN (SELECT friend_id FROM my_friends)
    ),
    pending_to_them AS (
        SELECT addressee_id AS other_user_id
        FROM friendships
        WHERE requester_id = current_user_uuid AND status = 'pending'
    ),
    pending_from_them AS (
        SELECT requester_id AS other_user_id
        FROM friendships
        WHERE addressee_id = current_user_uuid AND status = 'pending'
    )
    SELECT 
        up.id AS user_id,
        up.name,
        up.email,
        up.username,
        up.profile_photo_url,
        up.phone_number,
        up.fitness_goal,
        FALSE AS is_friend,
        EXISTS(SELECT 1 FROM pending_to_them pt WHERE pt.other_user_id = up.id) AS has_outgoing_request,
        EXISTS(SELECT 1 FROM pending_from_them pf WHERE pf.other_user_id = up.id) AS has_incoming_request,
        fof.mutual_count::INT AS mutual_friend_count
    FROM friends_of_friends fof
    INNER JOIN user_profiles up ON up.id = fof.suggested_user_id
    WHERE NOT EXISTS(SELECT 1 FROM pending_to_them pt WHERE pt.other_user_id = up.id)
      AND NOT EXISTS(SELECT 1 FROM pending_from_them pf WHERE pf.other_user_id = up.id)
      AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id)
             OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid)
      )
    ORDER BY 
        (up.profile_photo_url IS NOT NULL AND up.profile_photo_url != '') DESC,
        fof.mutual_count DESC,
        up.name ASC
    LIMIT result_limit;
END;
$$;

COMMENT ON FUNCTION get_people_you_may_know(INT) IS 
  'Returns friends-of-friends ("People You May Know") with mutual friend counts. '
  'Excludes blocked users in either direction.';

GRANT EXECUTE ON FUNCTION get_people_you_may_know(INT) TO authenticated;

-- ============================================================================
-- 3. ADD BLOCK FILTERING TO match_contacts_by_phone
-- ============================================================================

CREATE OR REPLACE FUNCTION match_contacts_by_phone(phone_hashes text[])
RETURNS TABLE(id uuid, name text, username text, profile_photo_url text)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT up.id, up.name, up.username, up.profile_photo_url
    FROM user_profiles up
    WHERE md5(up.phone_number) = ANY(phone_hashes)
      AND up.phone_number IS NOT NULL
      AND up.id != current_user_uuid
      AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id)
             OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid)
      );
END;
$$;

-- ============================================================================
-- 4. ADD BLOCK FILTERING TO get_community_challenge_leaderboard
--    Blocked users are excluded from the leaderboard JSON array
-- ============================================================================

CREATE OR REPLACE FUNCTION get_community_challenge_leaderboard(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 20,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_title TEXT,
    challenge_emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    join_code TEXT,
    invite_slug TEXT,
    leaderboard JSONB,
    my_rank INT,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_my_rank INT;
    v_my_today INT;
    v_my_days INT;
    v_my_streak INT;
    v_my_best INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    SELECT ranked.rank, ranked.today_progress, ranked.days_completed, ranked.current_streak, ranked.best_streak
    INTO v_my_rank, v_my_today, v_my_days, v_my_streak, v_my_best
    FROM (
        SELECT 
            ccp.user_id,
            COALESCE(cdp.progress_value, 0) AS today_progress,
            ccp.days_completed,
            ccp.current_streak,
            ccp.best_streak,
            ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC) AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp 
            ON cdp.challenge_id = ccp.challenge_id 
            AND cdp.user_id = ccp.user_id 
            AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
    ) ranked
    WHERE ranked.user_id = current_user_uuid;

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title AS challenge_title,
        cc.emoji AS challenge_emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        (
            SELECT jsonb_agg(entry ORDER BY entry->>'rank')
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC),
                    'user_id', ccp.user_id,
                    'name', up.name,
                    'username', up.username,
                    'profile_photo_url', up.profile_photo_url,
                    'today_progress', COALESCE(cdp.progress_value, 0),
                    'days_completed', ccp.days_completed,
                    'current_streak', ccp.current_streak,
                    'target_hit_today', COALESCE(cdp.target_hit, FALSE)
                ) AS entry
                FROM community_challenge_participants ccp
                JOIN user_profiles up ON up.id = ccp.user_id
                LEFT JOIN community_challenge_daily_progress cdp 
                    ON cdp.challenge_id = ccp.challenge_id 
                    AND cdp.user_id = ccp.user_id 
                    AND cdp.progress_date = today_date
                WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = ccp.user_id)
                         OR (ub.blocker_id = ccp.user_id AND ub.blocked_id = current_user_uuid)
                  )
                ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
                LIMIT p_limit
            ) sub
        ) AS leaderboard,
        COALESCE(v_my_rank, 0)::INT AS my_rank,
        COALESCE(v_my_today, 0)::INT AS my_today_progress,
        COALESCE(v_my_days, 0)::INT AS my_days_completed,
        COALESCE(v_my_streak, 0)::INT AS my_current_streak,
        COALESCE(v_my_best, 0)::INT AS my_best_streak
    FROM community_challenges cc
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) TO authenticated;

-- ============================================================================
-- 5. ADD BLOCK FILTERING TO get_single_community_leaderboard_snippet
-- ============================================================================

DROP FUNCTION IF EXISTS get_single_community_leaderboard_snippet(TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION get_single_community_leaderboard_snippet(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 10,
    p_timezone TEXT DEFAULT 'America/New_York'
)
RETURNS TABLE (
    challenge_id UUID,
    my_today_progress INT,
    my_rank INT,
    my_current_streak INT,
    my_best_streak INT,
    participant_count INT,
    top_participants JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
    today_date DATE := (NOW() AT TIME ZONE p_timezone)::DATE;
    v_challenge_id UUID := p_challenge_id::UUID;
BEGIN
    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        COALESCE(cdp.progress_value, 0)::INT AS my_today_progress,
        (
            SELECT COUNT(*)::INT + 1
            FROM community_challenge_participants other_ccp
            LEFT JOIN community_challenge_daily_progress other_cdp
                ON other_cdp.challenge_id = other_ccp.challenge_id
                AND other_cdp.user_id = other_ccp.user_id
                AND other_cdp.progress_date = today_date
            WHERE other_ccp.challenge_id = v_challenge_id
            AND other_ccp.is_active = TRUE
            AND other_ccp.user_id != current_user_uuid
            AND COALESCE(other_cdp.progress_value, 0) > COALESCE(cdp.progress_value, 0)
        )::INT AS my_rank,
        ccp.current_streak::INT AS my_current_streak,
        ccp.best_streak::INT AS my_best_streak,
        cc.participant_count::INT AS participant_count,
        (
            SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC),
                    'user_id', sub_ccp.user_id,
                    'name', sub_up.name,
                    'username', sub_up.username,
                    'profile_photo_url', sub_up.profile_photo_url,
                    'today_progress', COALESCE(sub_cdp.progress_value, 0),
                    'days_completed', sub_ccp.days_completed,
                    'current_streak', sub_ccp.current_streak,
                    'best_streak', sub_ccp.best_streak,
                    'target_hit_today', COALESCE(sub_cdp.target_hit, FALSE),
                    'is_current_user', (sub_ccp.user_id = current_user_uuid)
                ) AS entry
                FROM community_challenge_participants sub_ccp
                JOIN user_profiles sub_up ON sub_up.id = sub_ccp.user_id
                LEFT JOIN community_challenge_daily_progress sub_cdp
                    ON sub_cdp.challenge_id = sub_ccp.challenge_id
                    AND sub_cdp.user_id = sub_ccp.user_id
                    AND sub_cdp.progress_date = today_date
                WHERE sub_ccp.challenge_id = v_challenge_id AND sub_ccp.is_active = TRUE
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = sub_ccp.user_id)
                         OR (ub.blocker_id = sub_ccp.user_id AND ub.blocked_id = current_user_uuid)
                  )
                ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC
                LIMIT p_limit
            ) sub
        ) AS top_participants
    FROM community_challenges cc
    JOIN community_challenge_participants ccp
        ON ccp.challenge_id = cc.id AND ccp.user_id = current_user_uuid AND ccp.is_active = TRUE
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = cc.id
        AND cdp.user_id = current_user_uuid
        AND cdp.progress_date = today_date
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_single_community_leaderboard_snippet(TEXT, INT, TEXT) TO authenticated;

-- ============================================================================
-- 6. ADD BLOCK FILTERING TO get_league_leaderboard
-- ============================================================================

CREATE OR REPLACE FUNCTION get_league_leaderboard(p_user_id UUID, p_group_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER STABLE
AS $$
DECLARE
    v_group RECORD;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    SELECT * INTO v_group FROM league_groups WHERE id = p_group_id;
    IF v_group IS NULL THEN
        RETURN json_build_object('error', 'group_not_found');
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_group.tier_rank;

    v_days_remaining := 6 - (CURRENT_DATE - v_group.week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    SELECT json_build_object(
        'group_id', v_group.id,
        'tier_rank', v_group.tier_rank,
        'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji,
        'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count,
        'relegation_count', v_tier_info.relegation_count,
        'week_start', v_group.week_start,
        'days_remaining', v_days_remaining,
        'group_size', v_group.member_count,
        'my_points', COALESCE(
            (SELECT points FROM league_members
             WHERE user_id = p_user_id AND group_id = p_group_id), 0),
        'my_rank', COALESCE((
            SELECT rk FROM (
                SELECT user_id,
                       ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
                FROM league_members WHERE group_id = p_group_id
            ) sub WHERE user_id = p_user_id
        ), 1),
        'leaderboard', COALESCE((
            SELECT json_agg(row_to_json(sub) ORDER BY sub.rank)
            FROM (
                SELECT
                    lm.user_id,
                    up.name,
                    up.username,
                    up.profile_photo_url,
                    lm.points,
                    lm.workouts_completed,
                    ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                    (lm.user_id = p_user_id) AS is_current_user
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = p_group_id
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                         OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id)
                  )
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 7. ADD BLOCK FILTERING TO get_or_join_weekly_league (leaderboard embed)
--    Only the leaderboard subquery needs block filtering; the join/create
--    logic is untouched.
-- ============================================================================

-- The get_or_join_weekly_league function is large and contains league
-- join/create logic. We only need to update its embedded leaderboard query.
-- Rather than redefining the entire function (risky), we add a helper view
-- and update just the leaderboard subquery pattern.
--
-- Since get_or_join_weekly_league builds its response JSON inline, we
-- must replace the full function. Read the current definition and re-create
-- with the block filter added to the leaderboard subquery.

CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_week_start DATE;
    v_user_tier INTEGER;
    v_group_id UUID;
    v_membership_id UUID;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    PERFORM process_past_league_weeks();

    v_week_start := get_current_week_monday();
    v_days_remaining := 6 - (CURRENT_DATE - v_week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    INSERT INTO user_league_tier (user_id, current_tier)
    VALUES (p_user_id, 1)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT current_tier INTO v_user_tier
    FROM user_league_tier WHERE user_id = p_user_id;

    SELECT lm.id, lm.group_id
    INTO v_membership_id, v_group_id
    FROM league_members lm
    JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id
      AND lg.week_start = v_week_start;

    IF v_membership_id IS NULL THEN
        SELECT id INTO v_group_id
        FROM league_groups
        WHERE tier_rank = v_user_tier
          AND week_start = v_week_start
          AND member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
          AND NOT is_processed
        ORDER BY member_count DESC
        LIMIT 1
        FOR UPDATE SKIP LOCKED;

        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        INSERT INTO league_members (user_id, group_id, points)
        VALUES (p_user_id, v_group_id, 0)
        ON CONFLICT (user_id, group_id) DO NOTHING;

        UPDATE league_groups
        SET member_count = member_count + 1
        WHERE id = v_group_id;
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;

    SELECT json_build_object(
        'group_id', v_group_id,
        'tier_rank', v_user_tier,
        'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji,
        'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count,
        'relegation_count', v_tier_info.relegation_count,
        'week_start', v_week_start,
        'days_remaining', v_days_remaining,
        'my_points', COALESCE(
            (SELECT points FROM league_members
             WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((
            SELECT rk FROM (
                SELECT user_id,
                       ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
                FROM league_members WHERE group_id = v_group_id
            ) sub WHERE user_id = p_user_id
        ), 1),
        'group_size', (SELECT member_count FROM league_groups WHERE id = v_group_id),
        'leaderboard', COALESCE((
            SELECT json_agg(row_to_json(sub) ORDER BY sub.rank)
            FROM (
                SELECT
                    lm.user_id,
                    up.name,
                    up.username,
                    up.profile_photo_url,
                    lm.points,
                    lm.workouts_completed,
                    ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                    (lm.user_id = p_user_id) AS is_current_user
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = v_group_id
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                         OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id)
                  )
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMIT;
