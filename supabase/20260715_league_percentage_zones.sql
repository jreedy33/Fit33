-- =============================================================================
-- 20260715_league_percentage_zones.sql
--
-- Sprint 1 — Weekly League Redesign · Workstream A1 (per `League Redesign Plan`).
--
-- WHY
--   Today the rollup at `process_past_league_weeks()` and the placement RPCs
--   (`get_or_join_weekly_league`, `get_league_leaderboard`) read FIXED integer
--   `promotion_count` / `relegation_count` columns off `league_tiers`. That
--   produces broken edge cases when groups end up smaller than nominal
--   (privacy filter, hidden users, blocks) — e.g. a group of 8 with the old
--   "top 5 promote" rule means 63% promote, the competition collapses.
--
-- WHAT
--   1. Add `promotion_pct` + `relegation_pct` numeric columns to `league_tiers`
--      and seed them with the calibrated per-tier percentages from the plan.
--   2. Add a helper `calc_league_zone_count(member_count, pct, allow_zero)`
--      that returns the runtime zone size — clamped by a `MIN = 1` floor
--      (except when `pct = 0`, e.g. Bronze relegate / Verified promote) and a
--      `MAX = floor(member_count / 2) - 1` cap so promotion + relegation zones
--      can never overlap (always ≥1 stable middle, except 2-person groups).
--   3. Rewrite `process_past_league_weeks()` to derive the zone counts from
--      the percentage columns at rollup time, using the helper.
--   4. Rewrite `get_or_join_weekly_league(UUID)` and
--      `get_league_leaderboard(UUID, UUID)` so the JSON they return to clients
--      reflects the live `member_count`-derived zone sizes — not the stale
--      pre-edge-filter integer columns. Swift `LeagueStanding.promotionCount`
--      / `relegationCount` decoders are unchanged.
--   5. Old `promotion_count` / `relegation_count` columns stay for now so the
--      change is reversible; a follow-up will drop them after rollouts settle.
--
-- INVARIANTS PRESERVED
--   • Bronze (rank 1) never relegates (relegation_pct = 0).
--   • Verified (rank 7) never promotes (promotion_pct = 0).
--   • Promotion + relegation zones never overlap (the half-1 cap guarantees
--     at least 1 stable rank in the middle for groups of ≥ 4).
--   • Existing IDOR / privacy / Bronze-reshuffle / friend-overlap behavior
--     stays intact — only the two zone-count fields in the JSON output were
--     swapped.
--   • `process_past_league_weeks()` still skips groups with member_count < 2.
--   • Output JSON shape is byte-compatible with the iOS Swift decoder
--     (`LeagueStanding`).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema: percentage columns on league_tiers
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE league_tiers
    ADD COLUMN IF NOT EXISTS promotion_pct NUMERIC(4, 3) NOT NULL DEFAULT 0.000;

ALTER TABLE league_tiers
    ADD COLUMN IF NOT EXISTS relegation_pct NUMERIC(4, 3) NOT NULL DEFAULT 0.000;

COMMENT ON COLUMN league_tiers.promotion_pct IS
    'Fraction of group_size eligible for tier promotion at rollup. Clamped at runtime by calc_league_zone_count() with a MIN=1 floor (except when 0) and a MAX=floor(group_size/2)-1 cap. Source-of-truth for promotion zone sizing as of 20260715.';

COMMENT ON COLUMN league_tiers.relegation_pct IS
    'Fraction of group_size eligible for tier relegation at rollup. Same clamping as promotion_pct. Bronze (rank 1) is 0 (no tier below).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Seed calibrated percentages (matches League Redesign Plan §A1)
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE league_tiers SET promotion_pct = 0.170, relegation_pct = 0.000 WHERE tier_rank = 1; -- Bronze
UPDATE league_tiers SET promotion_pct = 0.170, relegation_pct = 0.170 WHERE tier_rank = 2; -- Silver
UPDATE league_tiers SET promotion_pct = 0.170, relegation_pct = 0.170 WHERE tier_rank = 3; -- Gold
UPDATE league_tiers SET promotion_pct = 0.150, relegation_pct = 0.180 WHERE tier_rank = 4; -- Platinum
UPDATE league_tiers SET promotion_pct = 0.120, relegation_pct = 0.200 WHERE tier_rank = 5; -- Diamond
UPDATE league_tiers SET promotion_pct = 0.100, relegation_pct = 0.250 WHERE tier_rank = 6; -- Elite
UPDATE league_tiers SET promotion_pct = 0.000, relegation_pct = 0.200 WHERE tier_rank = 7; -- Verified

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Helper: zone-size computation
--
-- Clamping logic:
--   • If pct = 0 → return 0 (Bronze relegate / Verified promote).
--   • Else return GREATEST(1, LEAST(floor(N*pct), floor(N/2)-1)).
--   The half-1 cap ensures promote + relegate ≤ N - 2 for N ≥ 4 (always a
--   stable middle), and at small N the floor(1) keeps competition meaningful.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS calc_league_zone_count(INTEGER, NUMERIC);

CREATE OR REPLACE FUNCTION calc_league_zone_count(
    p_member_count INTEGER,
    p_pct NUMERIC
)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE
        WHEN COALESCE(p_member_count, 0) < 2 OR COALESCE(p_pct, 0) <= 0 THEN 0
        ELSE GREATEST(
            1,
            LEAST(
                FLOOR(p_member_count * p_pct)::INTEGER,
                GREATEST(0, FLOOR(p_member_count / 2.0)::INTEGER - 1)
            )
        )
    END;
$$;

COMMENT ON FUNCTION calc_league_zone_count(INTEGER, NUMERIC) IS
    'Runtime zone-size for a league group given member count + tier percentage. Returns 0 when pct=0 (Bronze relegate / Verified promote) or when group < 2 members. Otherwise GREATEST(1, LEAST(floor(N*pct), floor(N/2)-1)). Used by process_past_league_weeks() at rollup and by get_or_join_weekly_league / get_league_leaderboard for client-facing zone sizing.';

GRANT EXECUTE ON FUNCTION calc_league_zone_count(INTEGER, NUMERIC) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Rewrite process_past_league_weeks() — percentage-based rollup
--
-- Same body as 20260326_verified_league_tier.sql but the two threshold
-- comparisons read calc_league_zone_count() with the live group size and the
-- new percentage columns instead of v_group.promotion_count / .relegation_count.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS process_past_league_weeks();

CREATE OR REPLACE FUNCTION process_past_league_weeks()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_week DATE;
    v_group RECORD;
    v_member RECORD;
    v_group_size INTEGER;
    v_promotion_count INTEGER;
    v_relegation_count INTEGER;
    v_promoted BOOLEAN;
    v_relegated BOOLEAN;
    v_new_tier INTEGER;
    v_processed_count INTEGER := 0;
BEGIN
    v_current_week := get_current_week_monday();

    FOR v_group IN
        SELECT lg.id, lg.tier_rank, lg.week_start, lg.member_count,
               lt.promotion_pct, lt.relegation_pct, lt.name AS tier_name
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

        -- Compute live zone sizes from percentages × current group size.
        v_promotion_count  := calc_league_zone_count(v_group_size, v_group.promotion_pct);
        v_relegation_count := calc_league_zone_count(v_group_size, v_group.relegation_pct);

        FOR v_member IN
            SELECT user_id, points,
                   ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS final_rank
            FROM league_members
            WHERE group_id = v_group.id
        LOOP
            v_promoted := FALSE;
            v_relegated := FALSE;
            v_new_tier := v_group.tier_rank;

            -- Promotion: top N (max tier is 7)
            IF v_promotion_count > 0
               AND v_member.final_rank <= v_promotion_count
               AND v_group.tier_rank < 7 THEN
                v_promoted := TRUE;
                v_new_tier := v_group.tier_rank + 1;
            END IF;

            -- Relegation: bottom N (only if not already at min tier 1)
            IF v_relegation_count > 0
               AND v_member.final_rank > (v_group_size - v_relegation_count)
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

COMMENT ON FUNCTION process_past_league_weeks() IS
    'Rollup for past unprocessed league weeks. As of 20260715, computes promotion / relegation zone sizes from league_tiers.promotion_pct / relegation_pct via calc_league_zone_count() instead of the legacy fixed integer columns. Idempotent — skips groups with is_processed = TRUE.';

GRANT EXECUTE ON FUNCTION process_past_league_weeks() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Rewrite get_or_join_weekly_league(UUID) — return live zone sizes
--
-- Body is identical to 20260426_sprint7_security_hygiene.sql §Q2-72.2 (IDOR
-- guard, privacy hide, Bronze reshuffle, friend overlap, leaderboard build),
-- the ONLY change is the JSON's `promotion_count` / `relegation_count` fields
-- now read calc_league_zone_count() at the live group_size.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_or_join_weekly_league(UUID);

CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
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
    v_member_count INTEGER;
BEGIN
    -- IDOR guard.
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot join or read another user''s league'
            USING ERRCODE = '42501';
    END IF;

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
        ON CONFLICT (user_id, group_id) DO NOTHING
        RETURNING id INTO v_new_member_id;

        IF v_new_member_id IS NOT NULL THEN
            UPDATE league_groups SET member_count = member_count + 1
            WHERE id = v_group_id;
        END IF;
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;
    SELECT member_count INTO v_member_count FROM league_groups WHERE id = v_group_id;

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
        -- Live zone sizes derived from percentage × current member_count
        -- (replaces the legacy v_tier_info.promotion_count / relegation_count
        -- read on 20260426 — see migration header).
        'promotion_count',  calc_league_zone_count(v_member_count, v_tier_info.promotion_pct),
        'relegation_count', calc_league_zone_count(v_member_count, v_tier_info.relegation_pct),
        'week_start', v_week_start,
        'days_remaining', v_days_remaining,
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (
            SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members lm2 LEFT JOIN user_profiles up2 ON up2.id = lm2.user_id
            WHERE lm2.group_id = v_group_id AND NOT COALESCE(up2.privacy_hide_league, FALSE)
        ) sub WHERE user_id = p_user_id), 1),
        'group_size', v_member_count,
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

COMMENT ON FUNCTION get_or_join_weekly_league(UUID) IS
    'Returns / joins the caller''s weekly league group. As of 20260715 the JSON''s promotion_count / relegation_count are computed live from league_tiers.promotion_pct / relegation_pct × current member_count via calc_league_zone_count() — instead of the legacy fixed integer columns. IDOR-guarded (auth.uid() must match p_user_id). pg_cron / service_role bypass preserved.';

GRANT EXECUTE ON FUNCTION get_or_join_weekly_league(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Rewrite get_league_leaderboard(UUID, UUID) — return live zone sizes
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_league_leaderboard(UUID, UUID);

CREATE OR REPLACE FUNCTION get_league_leaderboard(p_user_id UUID, p_group_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
    v_group RECORD;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot read another user''s league context'
            USING ERRCODE = '42501';
    END IF;

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
        'promotion_count',  calc_league_zone_count(v_group.member_count, v_tier_info.promotion_pct),
        'relegation_count', calc_league_zone_count(v_group.member_count, v_tier_info.relegation_pct),
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

COMMENT ON FUNCTION get_league_leaderboard(UUID, UUID) IS
    'Returns the caller''s weekly league leaderboard. As of 20260715 the JSON''s promotion_count / relegation_count are computed live from league_tiers.promotion_pct / relegation_pct × current member_count via calc_league_zone_count(). IDOR-guarded.';

GRANT EXECUTE ON FUNCTION get_league_leaderboard(UUID, UUID) TO authenticated;

COMMIT;
