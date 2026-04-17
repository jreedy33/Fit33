-- ============================================================================
-- LEAGUE AUTO-PLACEMENT (roster lock)
-- Fixes mid-week league joins: all users are placed at once Monday morning
-- via pg_cron. get_or_join_weekly_league no longer creates memberships
-- after Monday — it returns { "not_placed": true } instead.
--
-- Behavior:
--   • pg_cron calls auto_place_all_league_members() at 00:15 UTC every Monday
--   • That function: (1) processes past weeks, (2) places every eligible user
--   • get_or_join_weekly_league still does lazy placement on MONDAY only
--     (safety net if cron hasn't run yet or user is new)
--   • Tuesday–Sunday: no new placements; unplaced users wait until next Monday
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. BATCH AUTO-PLACEMENT FUNCTION
--    Iterates all users with a user_league_tier row who aren't placed this week.
--    Reuses the same Bronze (random + stale avoidance) and Silver+ (friend
--    overlap) algorithms from get_or_join_weekly_league.
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_place_all_league_members()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_week_start DATE;
    v_user RECORD;
    v_group_id UUID;
    v_placed_count INTEGER := 0;
    v_prev_group_id UUID;
    v_best_group_id UUID;
    v_least_stale_overlap INTEGER;
    v_stale_count INTEGER;
    v_candidate RECORD;
    v_best_overlap INTEGER;
    v_overlap INTEGER;
    v_new_member_id UUID;
BEGIN
    PERFORM process_past_league_weeks();

    v_week_start := get_current_week_monday();

    FOR v_user IN
        SELECT ult.user_id, ult.current_tier
        FROM user_league_tier ult
        WHERE NOT EXISTS (
            SELECT 1 FROM league_members lm
            JOIN league_groups lg ON lg.id = lm.group_id
            WHERE lm.user_id = ult.user_id
              AND lg.week_start = v_week_start
        )
        AND NOT COALESCE(
            (SELECT up.privacy_hide_league FROM user_profiles up WHERE up.id = ult.user_id),
            FALSE
        )
        ORDER BY ult.total_weeks_played DESC, ult.user_id
    LOOP
        v_group_id := NULL;
        v_best_group_id := NULL;

        IF v_user.current_tier = 1 THEN
            -- ==========================================================
            -- BRONZE: random placement, avoid last week's group-mates
            -- ==========================================================
            v_least_stale_overlap := 999;

            SELECT lm.group_id INTO v_prev_group_id
            FROM league_members lm
            JOIN league_groups lg ON lg.id = lm.group_id
            WHERE lm.user_id = v_user.user_id
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
                              (ub.blocker_id = v_user.user_id AND ub.blocked_id = lm_blk.user_id)
                              OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = v_user.user_id)
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
                          (ub.blocker_id = v_user.user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = v_user.user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY random()
                LIMIT 1;
            END IF;

        ELSE
            -- ==========================================================
            -- SILVER+: friend-overlap placement, avoid blocked users
            -- ==========================================================
            v_best_overlap := -1;

            FOR v_candidate IN
                SELECT lg.id, lg.member_count
                FROM league_groups lg
                WHERE lg.tier_rank = v_user.current_tier
                  AND lg.week_start = v_week_start
                  AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user.current_tier)
                  AND NOT lg.is_processed
                  AND NOT EXISTS (
                      SELECT 1 FROM league_members lm_blk
                      JOIN user_blocks ub ON (
                          (ub.blocker_id = v_user.user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = v_user.user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY lg.member_count DESC
            LOOP
                SELECT COUNT(*)::INT INTO v_overlap
                FROM league_members lm2
                JOIN friendships f ON (
                    (f.requester_id = v_user.user_id AND f.addressee_id = lm2.user_id)
                    OR (f.addressee_id = v_user.user_id AND f.requester_id = lm2.user_id)
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

        -- No suitable group → create one
        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user.current_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        -- Place the user (safe against duplicate if cron + RPC race)
        INSERT INTO league_members (user_id, group_id, points)
        VALUES (v_user.user_id, v_group_id, 0)
        ON CONFLICT (user_id, group_id) DO NOTHING
        RETURNING id INTO v_new_member_id;

        IF v_new_member_id IS NOT NULL THEN
            UPDATE league_groups SET member_count = member_count + 1
            WHERE id = v_group_id;
            v_placed_count := v_placed_count + 1;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'placed', v_placed_count,
        'week_start', v_week_start
    );
END;
$$;


-- ============================================================================
-- 2. UPDATED get_or_join_weekly_league — MONDAY-ONLY PLACEMENT
--    If the user has no membership and it's Tuesday–Sunday, returns
--    { "not_placed": true, tier info, next_week_start }.
--    Monday: still does lazy placement (safety net for cron delay).
--    Preserves ALL existing features: privacy, Bronze reshuffle, Silver+
--    friend overlap, blocks, hidden users, verified/gold_verified badges.
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
    v_is_monday BOOLEAN;
    v_new_member_id UUID;
BEGIN
    -- Privacy check
    SELECT COALESCE(up.privacy_hide_league, FALSE) INTO v_hide_league
    FROM user_profiles up WHERE up.id = p_user_id;

    IF COALESCE(v_hide_league, FALSE) THEN
        RETURN json_build_object('hidden', true);
    END IF;

    PERFORM process_past_league_weeks();

    v_week_start := get_current_week_monday();
    v_days_remaining := 6 - (CURRENT_DATE - v_week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    v_is_monday := (EXTRACT(ISODOW FROM CURRENT_DATE) = 1);

    -- Ensure user has a tier record (default Bronze)
    INSERT INTO user_league_tier (user_id, current_tier)
    VALUES (p_user_id, 1)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT current_tier INTO v_user_tier
    FROM user_league_tier WHERE user_id = p_user_id;

    -- Check existing membership
    SELECT lm.id, lm.group_id
    INTO v_membership_id, v_group_id
    FROM league_members lm
    JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id
      AND lg.week_start = v_week_start;

    -- ── ROSTER LOCK: no new placements after Monday ──
    IF v_membership_id IS NULL AND NOT v_is_monday THEN
        SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;
        RETURN json_build_object(
            'not_placed', true,
            'tier_rank', v_user_tier,
            'tier_name', v_tier_info.name,
            'tier_emoji', v_tier_info.emoji,
            'tier_color', v_tier_info.color_hex,
            'week_start', v_week_start,
            'days_remaining', v_days_remaining,
            'next_week_start', v_week_start + 7
        );
    END IF;

    -- ── Monday lazy placement (safety net if cron hasn't run) ──
    IF v_membership_id IS NULL THEN

        IF v_user_tier = 1 THEN
            -- BRONZE: random + stale avoidance + block avoidance
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
            -- SILVER+: friend-overlap placement + block avoidance
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
        ON CONFLICT (user_id, group_id) DO NOTHING
        RETURNING id INTO v_new_member_id;

        IF v_new_member_id IS NOT NULL THEN
            UPDATE league_groups SET member_count = member_count + 1
            WHERE id = v_group_id;
        END IF;
    END IF;

    -- ── Build full response with leaderboard ──
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


-- ============================================================================
-- 3. UPDATED get_league_leaderboard — no functional change, just re-declared
--    so all functions in the file are consistent. Preserves privacy, blocks,
--    hidden users, verified badges.
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
-- 4. SCHEDULE THE CRON JOB
--    Runs every Monday at 00:15 UTC. Supabase has pg_cron enabled by default.
--    The job calls auto_place_all_league_members() which handles everything.
-- ============================================================================

-- Enable pg_cron if not already (Supabase usually has this)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove any previous schedule with the same name
SELECT cron.unschedule('league-weekly-auto-place')
WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'league-weekly-auto-place'
);

-- Schedule: every Monday at 00:15 UTC
SELECT cron.schedule(
    'league-weekly-auto-place',
    '15 0 * * 1',
    $$SELECT auto_place_all_league_members()$$
);


COMMIT;
