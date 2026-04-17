-- Privacy Settings: Server-side RPC enforcement
-- Prerequisite: 20260330_privacy_settings.sql (columns must already exist)
-- Each function is idempotent (CREATE OR REPLACE).

BEGIN;

-- ============================================================================
-- 1. search_users — hide users with privacy_hide_search = TRUE
--    Also respect privacy_hide_photo: return NULL for photo if hidden
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
    SELECT up.id, up.name, up.email, up.username, up.fitness_goal, up.experience_level,
        CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END,
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
      AND NOT COALESCE(up.privacy_hide_search, FALSE)
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
-- 2. get_friend_activity_feed — hide posts from users with privacy_hide_activity
--    Also respect privacy_hide_photo on the poster
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
    SELECT faf.id, faf.user_id, up.name, up.username,
        CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END,
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
    AND NOT COALESCE(up.privacy_hide_activity, FALSE)
    ORDER BY faf.created_at DESC LIMIT p_limit OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION get_friend_activity_feed(INT, INT) TO authenticated;


-- ============================================================================
-- 3. match_contacts_by_phone — hide users with privacy_hide_contact_sync
--    Also respect privacy_hide_photo
-- ============================================================================
DROP FUNCTION IF EXISTS match_contacts_by_phone(text[]);

CREATE OR REPLACE FUNCTION match_contacts_by_phone(phone_hashes text[])
RETURNS TABLE(id uuid, name text, username text, profile_photo_url text)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY
    SELECT up.id, up.name, up.username,
        CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END
    FROM user_profiles up
    WHERE md5(up.phone_number) = ANY(phone_hashes)
      AND up.phone_number IS NOT NULL
      AND NOT COALESCE(up.privacy_hide_contact_sync, FALSE);
END;
$$;


-- ============================================================================
-- 4. get_people_you_may_know — respect privacy_hide_search and privacy_hide_photo
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
        CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END,
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
      AND NOT COALESCE(up.privacy_hide_search, FALSE)
    ORDER BY
        (up.profile_photo_url IS NOT NULL AND up.profile_photo_url != '' AND NOT COALESCE(up.privacy_hide_photo, FALSE)) DESC,
        fof.mutual_count DESC,
        up.name ASC
    LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_people_you_may_know(INT) TO authenticated;


-- ============================================================================
-- 5. get_league_leaderboard — respect privacy_hide_photo AND privacy_hide_league
--    Users with privacy_hide_league=TRUE are excluded from the leaderboard entirely.
-- ============================================================================
DROP FUNCTION IF EXISTS get_league_leaderboard(UUID, UUID);

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
            FROM league_members lm2 LEFT JOIN user_profiles up2 ON up2.id = lm2.user_id
            WHERE lm2.group_id = p_group_id AND NOT COALESCE(up2.privacy_hide_league, FALSE)
        ) sub WHERE user_id = p_user_id), 1),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username,
                CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END AS profile_photo_url,
                lm.points, lm.workouts_completed,
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
              AND NOT COALESCE(up.privacy_hide_league, FALSE)
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id) OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;
    RETURN v_result;
END;
$$;


-- ============================================================================
-- 6. get_or_join_weekly_league — respect privacy_hide_photo AND privacy_hide_league.
--    Users with privacy_hide_league=TRUE are NOT placed in new leagues and are
--    excluded from leaderboard results for other users.
-- ============================================================================
DROP FUNCTION IF EXISTS get_or_join_weekly_league(UUID);

CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_week_start DATE;
    v_user_tier INTEGER;
    v_group_id UUID;
    v_membership_id UUID;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
    v_best_group_id UUID;
    v_best_overlap INTEGER := -1;
    v_candidate RECORD;
    v_overlap INTEGER;
    v_prev_group_id UUID;
    v_least_stale_overlap INTEGER := 999;
    v_stale_count INTEGER;
    v_hide_league BOOLEAN;
BEGIN
    SELECT COALESCE(up.privacy_hide_league, FALSE) INTO v_hide_league
    FROM user_profiles up WHERE up.id = p_user_id;

    IF COALESCE(v_hide_league, FALSE) THEN
        RETURN json_build_object('hidden', true);
    END IF;

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

        IF v_user_tier = 1 THEN
            SELECT lm.group_id INTO v_prev_group_id
            FROM league_members lm
            JOIN league_groups lg ON lg.id = lm.group_id
            WHERE lm.user_id = p_user_id
              AND lg.week_start = v_week_start - INTERVAL '7 days'
            LIMIT 1;

            IF v_prev_group_id IS NOT NULL THEN
                FOR v_candidate IN
                    SELECT lg.id, lg.member_count
                    FROM league_groups lg
                    WHERE lg.tier_rank = 1
                      AND lg.week_start = v_week_start
                      AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = 1)
                      AND NOT lg.is_processed
                      AND NOT EXISTS (
                          SELECT 1 FROM league_members lm_blk
                          JOIN user_blocks ub ON (
                              (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                              OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                          )
                          WHERE lm_blk.group_id = lg.id
                      )
                    ORDER BY random()
                LOOP
                    SELECT COUNT(*)::INT INTO v_stale_count
                    FROM league_members lm_cur
                    JOIN league_members lm_prev ON lm_prev.user_id = lm_cur.user_id
                    WHERE lm_cur.group_id = v_candidate.id
                      AND lm_prev.group_id = v_prev_group_id;

                    IF v_stale_count < v_least_stale_overlap THEN
                        v_least_stale_overlap := v_stale_count;
                        v_best_group_id := v_candidate.id;
                    END IF;

                    IF v_stale_count = 0 THEN EXIT; END IF;
                END LOOP;

                v_group_id := v_best_group_id;
            ELSE
                SELECT lg.id INTO v_group_id
                FROM league_groups lg
                WHERE lg.tier_rank = 1
                  AND lg.week_start = v_week_start
                  AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = 1)
                  AND NOT lg.is_processed
                  AND NOT EXISTS (
                      SELECT 1 FROM league_members lm_blk
                      JOIN user_blocks ub ON (
                          (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY random()
                LIMIT 1;
            END IF;

        ELSE
            FOR v_candidate IN
                SELECT lg.id, lg.member_count
                FROM league_groups lg
                WHERE lg.tier_rank = v_user_tier
                  AND lg.week_start = v_week_start
                  AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
                  AND NOT lg.is_processed
                  AND NOT EXISTS (
                      SELECT 1 FROM league_members lm_blk
                      JOIN user_blocks ub ON (
                          (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY lg.member_count DESC
            LOOP
                SELECT COUNT(*)::INT INTO v_overlap
                FROM league_members lm2
                JOIN friendships f ON (
                    (f.requester_id = p_user_id AND f.addressee_id = lm2.user_id)
                    OR (f.addressee_id = p_user_id AND f.requester_id = lm2.user_id)
                )
                WHERE lm2.group_id = v_candidate.id
                  AND f.status = 'accepted';

                IF v_overlap > v_best_overlap THEN
                    v_best_overlap := v_overlap;
                    v_best_group_id := v_candidate.id;
                END IF;
            END LOOP;

            v_group_id := v_best_group_id;
        END IF;

        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        INSERT INTO league_members (user_id, group_id, points)
        VALUES (p_user_id, v_group_id, 0)
        ON CONFLICT (user_id, group_id) DO NOTHING;

        UPDATE league_groups SET member_count = member_count + 1
        WHERE id = v_group_id;
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;

    WITH my_friends AS (
        SELECT CASE WHEN requester_id = p_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships
        WHERE (requester_id = p_user_id OR addressee_id = p_user_id) AND status = 'accepted'
    )
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
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (
            SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members lm2 LEFT JOIN user_profiles up2 ON up2.id = lm2.user_id
            WHERE lm2.group_id = v_group_id AND NOT COALESCE(up2.privacy_hide_league, FALSE)
        ) sub WHERE user_id = p_user_id), 1),
        'group_size', (SELECT member_count FROM league_groups WHERE id = v_group_id),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username,
                CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END AS profile_photo_url,
                lm.points, lm.workouts_completed,
                ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                (lm.user_id = p_user_id) AS is_current_user,
                (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                CASE
                    WHEN lm.user_id = p_user_id THEN NULL
                    WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                    ELSE (SELECT COUNT(DISTINCT mf.fid)::INT FROM my_friends mf
                        JOIN friendships f3 ON ((f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                            OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id))
                        WHERE f3.status = 'accepted')
                END AS mutual_friend_count,
                (COALESCE(up.is_verified, FALSE)
                 OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7
                ) AS is_verified,
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified
            FROM league_members lm
            LEFT JOIN user_profiles up ON up.id = lm.user_id
            WHERE lm.group_id = v_group_id
              AND NOT COALESCE(up.privacy_hide_league, FALSE)
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub
                  WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                     OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu
                  WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMIT;
