-- Social League Neighborhoods
-- Replaces random league placement with friend-gravity clustering.
-- Users are pulled toward league groups where their friends/FoF already are.
-- Also adds social proximity indicators (is_friend, mutual_friend_count)
-- to leaderboard responses, and a lightweight "hide this person" feature.

BEGIN;

-- ============================================================================
-- 1. LEAGUE HIDDEN USERS TABLE
--    Lightweight per-user hide (softer than block). Hidden users are filtered
--    from your leaderboard view but still compete in the same group.
-- ============================================================================

CREATE TABLE IF NOT EXISTS league_hidden_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    hidden_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, hidden_user_id)
);

ALTER TABLE league_hidden_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own hidden list"
    ON league_hidden_users
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_league_hidden_users_user
    ON league_hidden_users(user_id);

-- ============================================================================
-- 2. HIDE / UNHIDE RPCs
-- ============================================================================

CREATE OR REPLACE FUNCTION hide_league_user(p_hidden_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'not_authenticated');
    END IF;

    IF v_user_id = p_hidden_user_id THEN
        RETURN json_build_object('success', false, 'error', 'cannot_hide_self');
    END IF;

    INSERT INTO league_hidden_users (user_id, hidden_user_id)
    VALUES (v_user_id, p_hidden_user_id)
    ON CONFLICT (user_id, hidden_user_id) DO NOTHING;

    RETURN json_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION unhide_league_user(p_hidden_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'not_authenticated');
    END IF;

    DELETE FROM league_hidden_users
    WHERE user_id = v_user_id AND hidden_user_id = p_hidden_user_id;

    RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION hide_league_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION unhide_league_user(UUID) TO authenticated;

-- ============================================================================
-- 3. REPLACE get_or_join_weekly_league WITH SOCIAL PLACEMENT + ENRICHMENT
--    Key changes:
--    a) Placement uses friend/FoF social-overlap scoring instead of random
--    b) Leaderboard entries include is_friend + mutual_friend_count
--    c) Hidden users filtered from leaderboard (alongside blocks)
-- ============================================================================

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

    -- Social-gravity placement: pick the group with the most friends/FoF.
    -- Two-phase approach: score first, then lock the winner for concurrency safety.
    IF v_membership_id IS NULL THEN
        WITH my_friends AS (
            SELECT CASE
                WHEN requester_id = p_user_id THEN addressee_id
                ELSE requester_id
            END AS fid
            FROM friendships
            WHERE (requester_id = p_user_id OR addressee_id = p_user_id)
              AND status = 'accepted'
        ),
        my_fof AS (
            SELECT DISTINCT CASE
                WHEN f2.requester_id = mf.fid THEN f2.addressee_id
                ELSE f2.requester_id
            END AS fid
            FROM friendships f2
            JOIN my_friends mf ON (f2.requester_id = mf.fid OR f2.addressee_id = mf.fid)
            WHERE f2.status = 'accepted'
              AND CASE WHEN f2.requester_id = mf.fid THEN f2.addressee_id ELSE f2.requester_id END != p_user_id
              AND CASE WHEN f2.requester_id = mf.fid THEN f2.addressee_id ELSE f2.requester_id END NOT IN (SELECT fid FROM my_friends)
        ),
        scored_groups AS (
            SELECT
                lg.id,
                COALESCE(SUM(
                    CASE
                        WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN 3
                        WHEN lm.user_id IN (SELECT fid FROM my_fof) THEN 1
                        ELSE 0
                    END
                ), 0) AS social_score,
                lg.member_count
            FROM league_groups lg
            LEFT JOIN league_members lm ON lm.group_id = lg.id
            WHERE lg.tier_rank = v_user_tier
              AND lg.week_start = v_week_start
              AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
              AND NOT lg.is_processed
            GROUP BY lg.id, lg.member_count
        )
        SELECT sg.id INTO v_group_id
        FROM scored_groups sg
        ORDER BY sg.social_score DESC, sg.member_count DESC
        LIMIT 1;

        -- Re-acquire with row lock to prevent concurrent overflow
        IF v_group_id IS NOT NULL THEN
            PERFORM id FROM league_groups
            WHERE id = v_group_id
              AND member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
            FOR UPDATE SKIP LOCKED;

            IF NOT FOUND THEN
                v_group_id := NULL;
            END IF;
        END IF;

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

    -- Build response with social proximity enrichment
    WITH my_friends AS (
        SELECT CASE
            WHEN requester_id = p_user_id THEN addressee_id
            ELSE requester_id
        END AS fid
        FROM friendships
        WHERE (requester_id = p_user_id OR addressee_id = p_user_id)
          AND status = 'accepted'
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
                    (lm.user_id = p_user_id) AS is_current_user,
                    (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                    CASE
                        WHEN lm.user_id = p_user_id THEN NULL
                        WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                        ELSE (
                            SELECT COUNT(DISTINCT mf.fid)::INT
                            FROM my_friends mf
                            JOIN friendships f3 ON (
                                (f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                                OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id)
                            )
                            WHERE f3.status = 'accepted'
                        )
                    END AS mutual_friend_count
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = v_group_id
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                         OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id)
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM league_hidden_users lhu
                      WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id
                  )
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 4. REPLACE get_league_leaderboard WITH SOCIAL ENRICHMENT + HIDE FILTER
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

    WITH my_friends AS (
        SELECT CASE
            WHEN requester_id = p_user_id THEN addressee_id
            ELSE requester_id
        END AS fid
        FROM friendships
        WHERE (requester_id = p_user_id OR addressee_id = p_user_id)
          AND status = 'accepted'
    )
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
                    (lm.user_id = p_user_id) AS is_current_user,
                    (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                    CASE
                        WHEN lm.user_id = p_user_id THEN NULL
                        WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                        ELSE (
                            SELECT COUNT(DISTINCT mf.fid)::INT
                            FROM my_friends mf
                            JOIN friendships f3 ON (
                                (f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                                OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id)
                            )
                            WHERE f3.status = 'accepted'
                        )
                    END AS mutual_friend_count
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = p_group_id
                  AND NOT EXISTS (
                      SELECT 1 FROM user_blocks ub
                      WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                         OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id)
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM league_hidden_users lhu
                      WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id
                  )
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMIT;
