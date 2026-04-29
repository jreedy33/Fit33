-- =============================================================================
-- 20260716_league_sprint2_stakes.sql
--
-- Sprint 2 — Weekly League Redesign: Stakes & Drama (per `League Redesign Plan`).
--
-- DELIVERS (covers todos sprint2-crown-headstart, sprint2-standout,
-- sprint2-shield-bounceback, sprint2-pending-points):
--   • A2 Crown of the Week (7-day cosmetic for rank 1)
--   • A2 Head-Start Bonus (+20 League Points carry-forward to rank 1)
--   • A3 Stand-Out skip-tier promotion (3 consecutive top-3 finishes)
--   • A4 First-Strike Shield (auto-protect first relegation in a tier)
--   • A4 Bounceback detection (relegated last week + promoted this week)
--   • A4 Two-Strike Verified rule (apex tier requires 2 consecutive bottom-3
--     weeks to relegate)
--   • C3 Pre-placement points bucket (`pending_league_points` carry-forward)
--
-- INVARIANTS PRESERVED FROM SPRINT 1 (#146 / `20260715_league_percentage_zones`):
--   • Bronze (rank 1) never relegates. Verified (rank 7) never promotes.
--   • Promotion + relegation zones never overlap (cap at floor(N/2)-1).
--   • Output JSON shape is byte-compatible with the iOS Swift decoder.
--   • IDOR / privacy / Bronze-reshuffle / friend-overlap / blocks / hidden
--     users / verified / gold_verified — all unchanged.
--
-- WIRES (Swift side — paired iOS commit):
--   • `LeagueStanding` decodes new optional fields `crown_until`,
--     `shield_available`, `top3_streak`, `pending_league_points`.
--   • `process_past_league_weeks()` records `was_stand_out` /
--     `was_crown` / `was_shielded` / `was_bounceback` on `league_history`
--     so the iOS celebration overlay can branch on TierPromotionEvent.Variant.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema additions
-- ─────────────────────────────────────────────────────────────────────────────

-- Stand-Out skip-tier streak + Shield + Verified two-strike rule + carry-forward
-- buckets all live on `user_league_tier` (one row per user — the canonical
-- per-user league state).
ALTER TABLE user_league_tier
    ADD COLUMN IF NOT EXISTS top3_streak                INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS shield_available           BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS verified_relegation_streak INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS pending_league_points      INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS next_week_starting_points  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS crown_until                TIMESTAMPTZ NULL;

COMMENT ON COLUMN user_league_tier.top3_streak IS
    'Consecutive top-3 finishes. Reset to 0 on any non-top-3 finish. When the user is also in the promotion zone AND streak >= 3, the rollup skip-tiers (current_tier += 2). League Redesign Plan §A3.';
COMMENT ON COLUMN user_league_tier.shield_available IS
    'First-Strike Shield. Granted ONLY when the user enters a tier via promotion. Burns silently on the first relegation hit in that tier (UI shows informational "Shield burned" banner; tier does NOT drop). League Redesign Plan §A4.';
COMMENT ON COLUMN user_league_tier.verified_relegation_streak IS
    'Verified (rank 7) two-strike protection. Increments on each bottom-3 finish at Verified; relegation only fires when this counter reaches 2. Reset to 0 on any non-bottom-3 finish or on a non-Verified tier. League Redesign Plan §A4.';
COMMENT ON COLUMN user_league_tier.pending_league_points IS
    'Pre-placement League Points bucket. The `add_league_points` RPC routes points here when the user has NO `league_members` row for the current week. Drained into `league_members.points` at next placement (Monday). League Redesign Plan §C3.';
COMMENT ON COLUMN user_league_tier.next_week_starting_points IS
    'Head-Start Bonus carry-forward. Set to +20 by the rollup for rank-1 finishers. Drained into `league_members.points` at next placement and reset to 0. League Redesign Plan §A2.';
COMMENT ON COLUMN user_league_tier.crown_until IS
    'Crown of the Week expiration timestamp. Set to NOW() + 7 days at rollup for rank-1 finishers. Cosmetic only — drives the gold ring around the welcome-widget badge and the small `crown.fill` flair on profile cards. NULL when not crowned. League Redesign Plan §A2.';

-- History rows record which celebration variant fired so the iOS overlay can
-- render Stand-Out / Crown / Bounceback / Shield-Burned without re-running
-- the rollup logic client-side.
ALTER TABLE league_history
    ADD COLUMN IF NOT EXISTS was_stand_out  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS was_crown      BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS was_shielded   BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS was_bounceback BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN league_history.was_stand_out  IS 'True iff this rollup row was a Stand-Out skip-tier promotion (top3_streak >= 3 AND in promotion zone). League Redesign Plan §A3.';
COMMENT ON COLUMN league_history.was_crown      IS 'True iff this rollup row was rank #1 of its group (Crown of the Week). League Redesign Plan §A2.';
COMMENT ON COLUMN league_history.was_shielded   IS 'True iff a relegation was suppressed because the user had `shield_available = TRUE` at rollup. The shield burns; tier stays. League Redesign Plan §A4.';
COMMENT ON COLUMN league_history.was_bounceback IS 'True iff the user was relegated the previous week AND promoted this week (immediate return). Drives the dedicated celebration overlay. League Redesign Plan §A4.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. process_past_league_weeks() — full Sprint 2 rollup
--
-- Replaces the Sprint 1 percentage-zones version (#146). All Sprint 1 invariants
-- (percentage-derived zone counts, Verified never promotes, Bronze never
-- relegates, no-overlap clamp) are preserved unchanged. New on top:
--   1. Stand-Out skip-tier when promoting AND top3_streak >= 3.
--   2. First-Strike Shield: when relegating AND shield_available, suppress the
--      tier drop and burn the shield (set FALSE).
--   3. Verified Two-Strike: relegation from rank 7 requires
--      verified_relegation_streak >= 2.
--   4. Crown of the Week + Head-Start Bonus for rank 1.
--   5. Bounceback detection: last week was_relegated AND this week was_promoted.
--   6. Top-3 streak bookkeeping (increment / reset).
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
    v_user_state RECORD;
    v_group_size INTEGER;
    v_promotion_count INTEGER;
    v_relegation_count INTEGER;
    v_promoted BOOLEAN;
    v_relegated BOOLEAN;
    v_stand_out BOOLEAN;
    v_crown BOOLEAN;
    v_shielded BOOLEAN;
    v_bounceback BOOLEAN;
    v_new_tier INTEGER;
    v_new_top3_streak INTEGER;
    v_new_verified_streak INTEGER;
    v_new_shield BOOLEAN;
    v_new_starting_points INTEGER;
    v_new_crown_until TIMESTAMPTZ;
    v_was_relegated_last_week BOOLEAN;
    v_was_top3 BOOLEAN;
    v_was_bottom3 BOOLEAN;
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

        v_promotion_count  := calc_league_zone_count(v_group_size, v_group.promotion_pct);
        v_relegation_count := calc_league_zone_count(v_group_size, v_group.relegation_pct);

        FOR v_member IN
            SELECT user_id, points,
                   ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS final_rank
            FROM league_members
            WHERE group_id = v_group.id
        LOOP
            -- Reset per-member flags.
            v_promoted   := FALSE;
            v_relegated  := FALSE;
            v_stand_out  := FALSE;
            v_crown      := FALSE;
            v_shielded   := FALSE;
            v_bounceback := FALSE;
            v_new_tier   := v_group.tier_rank;

            -- Pull current per-user league state (top3 streak, shield, etc).
            SELECT top3_streak, shield_available, verified_relegation_streak
              INTO v_user_state
              FROM user_league_tier
             WHERE user_id = v_member.user_id;

            v_was_top3    := (v_member.final_rank <= 3);
            v_was_bottom3 := (v_member.final_rank > (v_group_size - 3));

            -- Was the previous week a relegation row for this user? Used for
            -- both the Bounceback overlay and the shield-grant question
            -- (shield is granted ONLY when entering a tier via promotion —
            -- never on a hold, never on a non-Verified relegation hold).
            SELECT COALESCE(was_relegated, FALSE) INTO v_was_relegated_last_week
              FROM league_history
             WHERE user_id = v_member.user_id
               AND week_start = v_group.week_start - INTERVAL '7 days'
             ORDER BY week_start DESC LIMIT 1;
            v_was_relegated_last_week := COALESCE(v_was_relegated_last_week, FALSE);

            -- Promotion (top N, cap at rank 7) + Stand-Out skip-tier.
            IF v_promotion_count > 0
               AND v_member.final_rank <= v_promotion_count
               AND v_group.tier_rank < 7 THEN
                v_promoted := TRUE;
                IF COALESCE(v_user_state.top3_streak, 0) >= 3 AND v_group.tier_rank < 6 THEN
                    -- Stand-Out: skip the next tier. Cap before Verified so
                    -- skip-into-Verified is reachable from Diamond, not Elite.
                    v_stand_out := TRUE;
                    v_new_tier := v_group.tier_rank + 2;
                ELSE
                    v_new_tier := v_group.tier_rank + 1;
                END IF;
                IF v_was_relegated_last_week THEN
                    v_bounceback := TRUE;
                END IF;
            END IF;

            -- Relegation (bottom N, never below rank 1). Verified and Shield
            -- both gate this branch.
            IF v_relegation_count > 0
               AND v_member.final_rank > (v_group_size - v_relegation_count)
               AND v_group.tier_rank > 1
               AND NOT v_promoted THEN
                IF v_group.tier_rank = 7 THEN
                    -- Verified Two-Strike: drop only on the second consecutive
                    -- bottom-3 week.
                    v_new_verified_streak := COALESCE(v_user_state.verified_relegation_streak, 0) + 1;
                    IF v_new_verified_streak >= 2 THEN
                        v_relegated := TRUE;
                        v_new_tier := v_group.tier_rank - 1;
                    END IF;
                ELSIF COALESCE(v_user_state.shield_available, FALSE) THEN
                    -- First-Strike Shield: burn instead of relegate.
                    v_shielded := TRUE;
                    -- Tier stays put; relegation flag stays FALSE so the
                    -- iOS celebration surface can render the informational
                    -- "Shield burned" variant separately from a real drop.
                ELSE
                    v_relegated := TRUE;
                    v_new_tier := v_group.tier_rank - 1;
                END IF;
            END IF;

            -- Crown of the Week — rank 1, regardless of promotion zone size.
            IF v_member.final_rank = 1 AND v_group_size >= 3 THEN
                v_crown := TRUE;
            END IF;

            -- Top-3 streak update.
            IF v_was_top3 THEN
                v_new_top3_streak := COALESCE(v_user_state.top3_streak, 0) + 1;
            ELSE
                v_new_top3_streak := 0;
            END IF;

            -- Verified streak update — Verified-tier-only state. Reset off-tier.
            IF v_group.tier_rank = 7 THEN
                IF v_was_bottom3 THEN
                    v_new_verified_streak := COALESCE(v_user_state.verified_relegation_streak, 0) + 1;
                ELSE
                    v_new_verified_streak := 0;
                END IF;
            ELSE
                v_new_verified_streak := 0;
            END IF;

            -- Shield bookkeeping.
            --   • Granted on promotion INTO a new tier (not a hold, not a
            --     Stand-Out double-promote — same rule).
            --   • Burned when used (`v_shielded`).
            --   • Persists across non-relegation, non-promotion holds.
            IF v_promoted THEN
                v_new_shield := TRUE;
            ELSIF v_shielded THEN
                v_new_shield := FALSE;
            ELSE
                v_new_shield := COALESCE(v_user_state.shield_available, FALSE);
            END IF;

            -- Crown carry-forward — Head-Start Bonus + 7-day cosmetic ring.
            IF v_crown THEN
                v_new_starting_points := 20;  -- Head-Start Bonus
                v_new_crown_until := now() + INTERVAL '7 days';
            ELSE
                v_new_starting_points := 0;
                -- Don't clobber an existing crown_until — let the existing
                -- 7-day window expire naturally.
                v_new_crown_until := NULL;
            END IF;

            -- Skip-tier (Stand-Out) resets the top3_streak to 0 — the user just
            -- "spent" the ramp on the double-promote.
            IF v_stand_out THEN
                v_new_top3_streak := 0;
            END IF;

            -- Persist the rollup row.
            INSERT INTO league_history
                (user_id, week_start, tier_name, tier_rank, final_rank,
                 final_points, group_size, was_promoted, was_relegated,
                 was_stand_out, was_crown, was_shielded, was_bounceback)
            VALUES
                (v_member.user_id, v_group.week_start, v_group.tier_name,
                 v_group.tier_rank, v_member.final_rank, v_member.points,
                 v_group_size, v_promoted, v_relegated,
                 v_stand_out, v_crown, v_shielded, v_bounceback);

            -- Update per-user state (preserve Sprint 1 fields untouched).
            UPDATE user_league_tier
               SET current_tier               = v_new_tier,
                   total_weeks_played         = total_weeks_played + 1,
                   highest_tier_reached       = GREATEST(highest_tier_reached, v_new_tier),
                   total_promotions           = total_promotions + CASE WHEN v_promoted THEN 1 ELSE 0 END,
                   total_relegations          = total_relegations + CASE WHEN v_relegated THEN 1 ELSE 0 END,
                   top3_streak                = v_new_top3_streak,
                   verified_relegation_streak = v_new_verified_streak,
                   shield_available           = v_new_shield,
                   next_week_starting_points  = v_new_starting_points,
                   -- Only set crown_until when a new crown was earned this
                   -- week. Don't NULL out an existing in-flight 7-day window.
                   crown_until                = COALESCE(v_new_crown_until, crown_until),
                   updated_at                 = now()
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
    'Weekly League rollup. As of 20260716 (Sprint 2): adds Stand-Out skip-tier (top3_streak >= 3), First-Strike Shield (suppresses first relegation in tier), Verified Two-Strike rule, Crown of the Week + Head-Start Bonus, and Bounceback detection. Percentage zones (Sprint 1) unchanged. Idempotent.';

GRANT EXECUTE ON FUNCTION process_past_league_weeks() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. add_league_points — pre-placement bucket
--
-- Today the RPC short-circuits with `no_membership` when the user isn't placed.
-- Sprint 2 §C3 routes those points to `user_league_tier.pending_league_points`
-- so the next Monday's placement starts on the correct foot. Same return
-- shape; new optional `pending_points` field surfaces the bucket so the iOS
-- not-placed page can show "earned this week, applied Monday".
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS add_league_points(UUID, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION add_league_points(
    p_user_id UUID,
    p_points INTEGER,
    p_source TEXT DEFAULT 'workout'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_start DATE;
    v_group_id UUID;
    v_new_points INTEGER;
    v_pending INTEGER;
BEGIN
    -- IDOR guard mirrors the rest of the league API surface.
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot add points for another user'
            USING ERRCODE = '42501';
    END IF;

    IF p_points IS NULL OR p_points <= 0 THEN
        RETURN json_build_object('success', false, 'reason', 'invalid_points');
    END IF;

    v_week_start := get_current_week_monday();

    SELECT lm.group_id INTO v_group_id
      FROM league_members lm
      JOIN league_groups lg ON lg.id = lm.group_id
     WHERE lm.user_id = p_user_id
       AND lg.week_start = v_week_start;

    IF v_group_id IS NULL THEN
        -- Pre-placement path. Bucket the points so they're credited at
        -- next Monday placement. League Redesign Plan §C3.
        INSERT INTO user_league_tier (user_id, current_tier, pending_league_points)
        VALUES (p_user_id, 1, p_points)
        ON CONFLICT (user_id) DO UPDATE
           SET pending_league_points = user_league_tier.pending_league_points + EXCLUDED.pending_league_points,
               updated_at = now()
        RETURNING pending_league_points INTO v_pending;

        RETURN json_build_object(
            'success', true,
            'pending', true,
            'pending_points', COALESCE(v_pending, p_points),
            'points_added', p_points,
            'source', p_source
        );
    END IF;

    UPDATE league_members
       SET points = points + p_points,
           workouts_completed = CASE
               WHEN p_source = 'workout' OR p_source = 'cardio_session'
               THEN workouts_completed + 1
               ELSE workouts_completed
           END
     WHERE user_id = p_user_id AND group_id = v_group_id
     RETURNING points INTO v_new_points;

    RETURN json_build_object(
        'success', true,
        'pending', false,
        'new_points', v_new_points,
        'points_added', p_points,
        'source', p_source
    );
END;
$$;

COMMENT ON FUNCTION add_league_points(UUID, INTEGER, TEXT) IS
    'Adds League Points for a user. As of 20260716 (Sprint 2): pre-placement points are routed to `user_league_tier.pending_league_points` instead of returning `no_membership`; the bucket drains into `league_members.points` at next Monday placement. IDOR-guarded. Recognizes new `cardio_session` source for the workouts_completed counter (parity with strength workouts).';

GRANT EXECUTE ON FUNCTION add_league_points(UUID, INTEGER, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Placement helpers — drain pending + Head-Start at insert time
--
-- Both `auto_place_all_league_members()` (Monday cron batch) and the lazy
-- placement branch in `get_or_join_weekly_league()` insert the new
-- `league_members` row with `points = 0`. We need them to instead drain
-- `pending_league_points + next_week_starting_points` from `user_league_tier`
-- into the new row's points. Rather than rewrite both function bodies in
-- full, we extract the drain logic into a small helper that both call.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS drain_pending_into_league_member(UUID);

CREATE OR REPLACE FUNCTION drain_pending_into_league_member(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_pending INTEGER;
    v_starting INTEGER;
    v_total INTEGER;
BEGIN
    SELECT pending_league_points, next_week_starting_points
      INTO v_pending, v_starting
      FROM user_league_tier
     WHERE user_id = p_user_id;

    v_total := COALESCE(v_pending, 0) + COALESCE(v_starting, 0);
    IF v_total = 0 THEN RETURN 0; END IF;

    UPDATE user_league_tier
       SET pending_league_points = 0,
           next_week_starting_points = 0,
           updated_at = now()
     WHERE user_id = p_user_id;

    RETURN v_total;
END;
$$;

COMMENT ON FUNCTION drain_pending_into_league_member(UUID) IS
    'Drains the pre-placement and Head-Start point buckets from user_league_tier and returns the total (non-negative). Caller is responsible for adding the returned value into the freshly-inserted league_members row''s points. League Redesign Plan §A2 + §C3.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. auto_place_all_league_members — credit pending at insert time
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS auto_place_all_league_members();

CREATE OR REPLACE FUNCTION auto_place_all_league_members()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    v_starting_points INTEGER;
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

        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user.current_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        v_starting_points := drain_pending_into_league_member(v_user.user_id);

        INSERT INTO league_members (user_id, group_id, points)
        VALUES (v_user.user_id, v_group_id, v_starting_points)
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

COMMENT ON FUNCTION auto_place_all_league_members() IS
    'Monday cron batch placement. As of 20260716 (Sprint 2): drains user_league_tier.pending_league_points + next_week_starting_points into the freshly-inserted league_members.points via drain_pending_into_league_member(). All Sprint 1 placement logic (Bronze reshuffle, Silver+ friend-overlap, blocks, hidden users, privacy) preserved.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. get_or_join_weekly_league — drain pending on Monday lazy-place too
--
-- Sprint 1's percentage-zone version (#146) lives in
-- `20260715_league_percentage_zones.sql`. We re-CREATE the function with the
-- same body, only swapping the `INSERT INTO league_members ... points = 0`
-- to `points = drain_pending_into_league_member(p_user_id)`.
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
    v_user_state RECORD;
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
    v_starting_points INTEGER;
BEGIN
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

    SELECT current_tier, pending_league_points, shield_available, top3_streak, crown_until
      INTO v_user_state
      FROM user_league_tier WHERE user_id = p_user_id;
    v_user_tier := v_user_state.current_tier;

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
            'next_week_start', v_week_start + 7,
            -- 2026-04-29 — League Redesign Plan §C3. Surface the pre-
            -- placement bucket so the iOS not-placed page can render
            -- "earned this week, applied Monday" instead of "0".
            'pending_league_points', COALESCE(v_user_state.pending_league_points, 0),
            'shield_available', COALESCE(v_user_state.shield_available, FALSE),
            'top3_streak', COALESCE(v_user_state.top3_streak, 0),
            'crown_until', v_user_state.crown_until
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

        v_starting_points := drain_pending_into_league_member(p_user_id);

        INSERT INTO league_members (user_id, group_id, points)
        VALUES (p_user_id, v_group_id, v_starting_points)
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
        -- 2026-04-29 — League Redesign Plan §A2 + §A3 + §A4 + §C3.
        -- Surface the new per-user state to the client (TierPromotionEvent
        -- variant routing + dashboard cosmetic + not-placed page CTA).
        'pending_league_points', COALESCE(v_user_state.pending_league_points, 0),
        'shield_available', COALESCE(v_user_state.shield_available, FALSE),
        'top3_streak', COALESCE(v_user_state.top3_streak, 0),
        'crown_until', v_user_state.crown_until,
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
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified,
                -- Crown-of-the-Week cosmetic — non-NULL crown_until in the
                -- future means this user holds the crown for the week.
                (CASE WHEN (SELECT ult.crown_until FROM user_league_tier ult WHERE ult.user_id = lm.user_id) > now()
                      THEN TRUE ELSE FALSE END) AS has_crown
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
    'Returns / joins the caller''s weekly league group. As of 20260716 (Sprint 2): surfaces pending_league_points, shield_available, top3_streak, crown_until in the JSON; leaderboard rows include `has_crown` for the rank-1 cosmetic. Drains pending + Head-Start buckets at lazy placement. IDOR-guarded.';

GRANT EXECUTE ON FUNCTION get_or_join_weekly_league(UUID) TO authenticated;

COMMIT;
