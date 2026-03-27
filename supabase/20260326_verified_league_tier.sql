-- ============================================================================
-- VERIFIED LEAGUE TIER + VERIFIED BADGE SYSTEM
-- Adds tier 7 "Verified" above Elite. Users who reach this league get a blue
-- verification badge next to their name. An admin override column
-- (is_verified) on user_profiles forces the badge regardless of league tier.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. ADD is_verified COLUMN TO user_profiles
-- ============================================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- 2. ADD VERIFIED TIER (rank 7) + UPDATE ELITE TO ALLOW PROMOTION
-- ============================================================================

-- Elite now promotes top 2 to Verified (was 0 promotion since it was the top)
UPDATE league_tiers
SET promotion_count = 2
WHERE tier_rank = 6;

INSERT INTO league_tiers (tier_rank, name, emoji, color_hex, promotion_count, relegation_count, max_group_size)
VALUES (7, 'Verified', '✅', '#1DA1F2', 0, 3, 15)
ON CONFLICT (tier_rank) DO UPDATE SET
    name = EXCLUDED.name,
    emoji = EXCLUDED.emoji,
    color_hex = EXCLUDED.color_hex,
    promotion_count = EXCLUDED.promotion_count,
    relegation_count = EXCLUDED.relegation_count,
    max_group_size = EXCLUDED.max_group_size;

-- ============================================================================
-- 3. UPDATE process_past_league_weeks — MAX TIER IS NOW 7
-- ============================================================================

CREATE OR REPLACE FUNCTION process_past_league_weeks()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_week DATE;
    v_group RECORD;
    v_member RECORD;
    v_group_size INTEGER;
    v_tier_info RECORD;
    v_promoted BOOLEAN;
    v_relegated BOOLEAN;
    v_new_tier INTEGER;
    v_processed_count INTEGER := 0;
BEGIN
    v_current_week := get_current_week_monday();

    FOR v_group IN
        SELECT lg.id, lg.tier_rank, lg.week_start, lg.member_count,
               lt.promotion_count, lt.relegation_count, lt.name as tier_name
        FROM league_groups lg
        JOIN league_tiers lt ON lt.tier_rank = lg.tier_rank
        WHERE lg.week_start < v_current_week
          AND NOT lg.is_processed
        ORDER BY lg.week_start ASC
    LOOP
        v_group_size := v_group.member_count;

        IF v_group_size < 2 THEN
            UPDATE league_groups SET is_processed = TRUE WHERE id = v_group.id;
            CONTINUE;
        END IF;

        FOR v_member IN
            SELECT user_id, points,
                   ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) as final_rank
            FROM league_members
            WHERE group_id = v_group.id
        LOOP
            v_promoted := FALSE;
            v_relegated := FALSE;
            v_new_tier := v_group.tier_rank;

            -- Promotion: top N (max tier is now 7)
            IF v_member.final_rank <= v_group.promotion_count AND v_group.tier_rank < 7 THEN
                v_promoted := TRUE;
                v_new_tier := v_group.tier_rank + 1;
            END IF;

            -- Relegation: bottom N (if not at min tier 1)
            IF v_member.final_rank > (v_group_size - v_group.relegation_count)
               AND v_group.tier_rank > 1 THEN
                v_relegated := TRUE;
                v_new_tier := v_group.tier_rank - 1;
            END IF;

            INSERT INTO league_history
                (user_id, week_start, tier_name, tier_rank, final_rank,
                 final_points, group_size, was_promoted, was_relegated)
            VALUES
                (v_member.user_id, v_group.week_start, v_group.tier_name,
                 v_group.tier_rank, v_member.final_rank, v_member.points,
                 v_group_size, v_promoted, v_relegated);

            UPDATE user_league_tier
            SET current_tier = v_new_tier,
                total_weeks_played = total_weeks_played + 1,
                highest_tier_reached = GREATEST(highest_tier_reached, v_new_tier),
                total_promotions = total_promotions + CASE WHEN v_promoted THEN 1 ELSE 0 END,
                total_relegations = total_relegations + CASE WHEN v_relegated THEN 1 ELSE 0 END,
                updated_at = now()
            WHERE user_id = v_member.user_id;
        END LOOP;

        UPDATE league_groups SET is_processed = TRUE WHERE id = v_group.id;
        v_processed_count := v_processed_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'groups_processed', v_processed_count
    );
END;
$$;

-- ============================================================================
-- 4. UPDATE get_or_join_weekly_league — ADD is_verified TO LEADERBOARD ENTRIES
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
    v_best_group_id UUID;
    v_best_overlap INTEGER := -1;
    v_candidate RECORD;
    v_overlap INTEGER;
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
        FOR v_candidate IN
            SELECT lg.id, lg.member_count
            FROM league_groups lg
            WHERE lg.tier_rank = v_user_tier
              AND lg.week_start = v_week_start
              AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
              AND NOT lg.is_processed
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
                    END AS mutual_friend_count,
                    (COALESCE(up.is_verified, FALSE)
                     OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7
                    ) AS is_verified
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
-- 5. UPDATE get_league_leaderboard — ADD is_verified TO LEADERBOARD ENTRIES
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
                    END AS mutual_friend_count,
                    (COALESCE(up.is_verified, FALSE)
                     OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7
                    ) AS is_verified
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
