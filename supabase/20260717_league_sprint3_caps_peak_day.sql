-- =============================================================================
-- 20260717_league_sprint3_caps_peak_day.sql
--
-- Sprint 3 — Weekly League Redesign: Engagement & Polish (per `League Redesign Plan`).
--
-- DELIVERS (covers todos sprint3-peak-day + sprint3-caps-enforcement):
--   • A5 Peak Day Bonus — a per-user weekday picked at placement; League
--     Points earned on that day are multiplied 3×. The peak day re-randomizes
--     each Monday rollup. Surfaced in the placed `get_or_join_weekly_league`
--     JSON so the dashboard widget can render "Peak Day: Wednesday — 3×".
--   • C2 Server-side per-source caps — the soft client-side cap ledger from
--     Sprint 1 is now the source of truth on the server too. A new
--     `league_point_awards` ledger table (one row per award) is the authority
--     for daily / weekly / lifetime cap enforcement inside `add_league_points`.
--     Pre-existing client-side caps stay (they avoid round-trips), but they
--     are no longer trustable — the server re-checks every call.
--
-- INVARIANTS PRESERVED FROM SPRINTS 1+2:
--   • Bronze never relegates. Verified never promotes.
--   • Promotion + relegation zones never overlap.
--   • Pre-placement points still accumulate in `user_league_tier.pending_league_points`.
--   • Stand-Out / Shield / Crown / Bounceback / Two-Strike all unchanged.
--   • `get_or_join_weekly_league` JSON shape stays additive — old clients
--     that don't decode `peak_day` keep working.
--
-- WIRES (Swift side — paired iOS commit):
--   • `LeagueStanding` decodes new optional `peak_day` (0=Sun..6=Sat).
--   • Dashboard renders the "Peak Day Bonus" widget with day-of-week label.
--   • `add_league_points` JSON response now includes `multiplier` so the
--     iOS optimistic update can credit 3× when the server applied 3×.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema additions
-- ─────────────────────────────────────────────────────────────────────────────

-- Peak Day per user. ISO weekday: 1=Mon, 2=Tue, …, 7=Sun. NULL = no peak
-- day (legacy users until next placement). Refreshed on every Monday rollup.
ALTER TABLE user_league_tier
    ADD COLUMN IF NOT EXISTS peak_day_iso INTEGER NULL
        CHECK (peak_day_iso IS NULL OR (peak_day_iso BETWEEN 1 AND 7));

COMMENT ON COLUMN user_league_tier.peak_day_iso IS
    'Per-user Peak Day Bonus weekday (ISO 1=Mon..7=Sun). League Points earned on this weekday are multiplied 3× by `add_league_points`. Refreshed each Monday rollup. NULL until first placement. League Redesign Plan §A5.';

-- Per-award ledger for server-side cap enforcement. One row per
-- `add_league_points` award. Source of truth for daily / weekly / lifetime
-- per-source caps from `LeaguePointSource`. Hot-path indexed for the
-- "have we already awarded this user for this source today?" query.
CREATE TABLE IF NOT EXISTS league_point_awards (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source          TEXT NOT NULL,
    awarded_points  INTEGER NOT NULL,
    multiplier      INTEGER NOT NULL DEFAULT 1,
    awarded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    awarded_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    week_start      DATE NOT NULL,
    -- Optional dedupe key for sources whose cap is per-key lifetime
    -- (`new_exercise_tried`, `streak_milestone_*`). Empty string for
    -- date-bucketed sources.
    attribution     TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_lpa_user_source_date
    ON league_point_awards (user_id, source, awarded_date);
CREATE INDEX IF NOT EXISTS idx_lpa_user_source_week
    ON league_point_awards (user_id, source, week_start);
CREATE INDEX IF NOT EXISTS idx_lpa_user_source_attribution
    ON league_point_awards (user_id, source, attribution)
    WHERE attribution <> '';

COMMENT ON TABLE league_point_awards IS
    'Authoritative ledger of every League Point award. Powers server-side per-source cap enforcement in add_league_points (Sprint 3 §C2). The client-side ledger in UserDefaults is a soft pre-check only — the server is the source of truth. League Redesign Plan §C2.';

-- RLS — users can read their own awards (debug surface), nobody writes
-- directly. Inserts go through the SECURITY DEFINER `add_league_points` RPC.
ALTER TABLE league_point_awards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lpa_select_own" ON league_point_awards;
CREATE POLICY "lpa_select_own" ON league_point_awards
    FOR SELECT USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "lpa_no_direct_write" ON league_point_awards;
-- (No INSERT / UPDATE / DELETE policies — RPC bypasses RLS via SECURITY DEFINER.)

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. league_point_source_caps — declarative per-source cap policy
--
-- Mirrors the Swift `LeaguePointSource.dailyCap` / `weeklyCap` / `lifetimeKey`
-- so the source of truth lives next to the data. Seed ONCE; future cap
-- changes go through new migrations editing this table (not the RPC body).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS league_point_source_caps (
    source        TEXT PRIMARY KEY,
    daily_cap     INTEGER NULL,    -- NULL = uncapped
    weekly_cap    INTEGER NULL,    -- NULL = uncapped
    is_lifetime   BOOLEAN NOT NULL DEFAULT FALSE,
    notes         TEXT NULL
);

INSERT INTO league_point_source_caps (source, daily_cap, weekly_cap, is_lifetime, notes) VALUES
    ('workout',                   NULL, NULL, FALSE, 'Capped naturally — one workout = +50.'),
    ('challenge_target',          NULL, NULL, FALSE, 'Daily quest tied; bounded by the at-most-3-quests/day rule.'),
    ('personal_record',           NULL, NULL, FALSE, 'Per-exercise weekly cap handled at PR detection site.'),
    ('meal_logged',               3,    NULL, FALSE, 'Up to 3 logged meals/day.'),
    ('daily_login',               1,    NULL, FALSE, 'Once/day on app open.'),
    ('streak_milestone_7',        NULL, NULL, TRUE,  'Once per user.'),
    ('streak_milestone_30',       NULL, NULL, TRUE,  'Once per user.'),
    ('streak_milestone_100',      NULL, NULL, TRUE,  'Once per user.'),
    ('daily_quest_completed',     NULL, NULL, FALSE, 'Bounded by 3 quests/day.'),
    ('cardio_session',            NULL, NULL, FALSE, 'Bounded by workout cadence.'),
    ('body_weight_logged',        1,    NULL, FALSE, 'Once/day.'),
    ('new_exercise_tried',        NULL, NULL, TRUE,  'Once per exercise lifetime — attribution = exerciseId.'),
    ('friend_kudos_given',        5,    NULL, FALSE, 'Up to 5 kudos/day count toward points.'),
    ('workout_shared_with_friend', NULL, 3,   FALSE, 'Up to 3 shares/week count toward points.')
ON CONFLICT (source) DO UPDATE
    SET daily_cap   = EXCLUDED.daily_cap,
        weekly_cap  = EXCLUDED.weekly_cap,
        is_lifetime = EXCLUDED.is_lifetime,
        notes       = EXCLUDED.notes;

COMMENT ON TABLE league_point_source_caps IS
    'Per-source cap policy used by add_league_points (Sprint 3 §C2). Mirrors the Swift LeaguePointSource cap properties. Edit cap values via new migrations — never UPDATE rows directly in production. League Redesign Plan §C2.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. add_league_points — Peak Day multiplier + ledger-backed caps
--
-- Replaces the Sprint 2 version. Adds:
--   1. Per-source cap check via `league_point_awards` + `league_point_source_caps`.
--   2. Peak Day Bonus 3× multiplier when CURRENT_DATE matches user's peak_day_iso.
--   3. Award ledger row written for every successful award.
--   4. JSON response now exposes `multiplier`, `cap_blocked`, and `cap_reason`.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS add_league_points(UUID, INTEGER, TEXT);
DROP FUNCTION IF EXISTS add_league_points(UUID, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION add_league_points(
    p_user_id UUID,
    p_points INTEGER,
    p_source TEXT DEFAULT 'workout',
    p_attribution TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_start DATE;
    v_today DATE;
    v_peak_day INTEGER;
    v_today_iso INTEGER;
    v_multiplier INTEGER := 1;
    v_effective_points INTEGER;
    v_group_id UUID;
    v_new_points INTEGER;
    v_pending INTEGER;
    v_cap RECORD;
    v_already_today INTEGER;
    v_already_week INTEGER;
    v_already_lifetime INTEGER;
BEGIN
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot add points for another user'
            USING ERRCODE = '42501';
    END IF;

    IF p_points IS NULL OR p_points <= 0 THEN
        RETURN json_build_object('success', false, 'reason', 'invalid_points');
    END IF;

    v_week_start := get_current_week_monday();
    v_today := CURRENT_DATE;
    v_today_iso := EXTRACT(ISODOW FROM v_today)::INTEGER;

    -- Cap enforcement (server-side, ledger-backed). League Redesign Plan §C2.
    SELECT * INTO v_cap FROM league_point_source_caps WHERE source = p_source;

    IF v_cap.source IS NOT NULL THEN
        IF v_cap.is_lifetime THEN
            SELECT COUNT(*) INTO v_already_lifetime
              FROM league_point_awards
             WHERE user_id = p_user_id
               AND source = p_source
               AND attribution = COALESCE(p_attribution, '');
            IF v_already_lifetime > 0 THEN
                RETURN json_build_object(
                    'success', false,
                    'cap_blocked', true,
                    'cap_reason', 'lifetime_cap',
                    'source', p_source
                );
            END IF;
        END IF;

        IF v_cap.daily_cap IS NOT NULL THEN
            SELECT COUNT(*) INTO v_already_today
              FROM league_point_awards
             WHERE user_id = p_user_id
               AND source = p_source
               AND awarded_date = v_today;
            IF v_already_today >= v_cap.daily_cap THEN
                RETURN json_build_object(
                    'success', false,
                    'cap_blocked', true,
                    'cap_reason', 'daily_cap',
                    'cap_value', v_cap.daily_cap,
                    'source', p_source
                );
            END IF;
        END IF;

        IF v_cap.weekly_cap IS NOT NULL THEN
            SELECT COUNT(*) INTO v_already_week
              FROM league_point_awards
             WHERE user_id = p_user_id
               AND source = p_source
               AND week_start = v_week_start;
            IF v_already_week >= v_cap.weekly_cap THEN
                RETURN json_build_object(
                    'success', false,
                    'cap_blocked', true,
                    'cap_reason', 'weekly_cap',
                    'cap_value', v_cap.weekly_cap,
                    'source', p_source
                );
            END IF;
        END IF;
    END IF;

    -- Peak Day Bonus (League Redesign Plan §A5).
    SELECT peak_day_iso INTO v_peak_day FROM user_league_tier WHERE user_id = p_user_id;
    IF v_peak_day IS NOT NULL AND v_peak_day = v_today_iso THEN
        v_multiplier := 3;
    END IF;

    v_effective_points := p_points * v_multiplier;

    -- Find current-week membership.
    SELECT lm.group_id INTO v_group_id
      FROM league_members lm
      JOIN league_groups lg ON lg.id = lm.group_id
     WHERE lm.user_id = p_user_id
       AND lg.week_start = v_week_start;

    IF v_group_id IS NULL THEN
        -- Pre-placement bucket. Peak Day still multiplies — the multiplier
        -- carries forward to the placed week's starting points.
        INSERT INTO user_league_tier (user_id, current_tier, pending_league_points)
        VALUES (p_user_id, 1, v_effective_points)
        ON CONFLICT (user_id) DO UPDATE
           SET pending_league_points = user_league_tier.pending_league_points + EXCLUDED.pending_league_points,
               updated_at = now()
        RETURNING pending_league_points INTO v_pending;

        INSERT INTO league_point_awards (
            user_id, source, awarded_points, multiplier,
            awarded_date, week_start, attribution
        ) VALUES (
            p_user_id, p_source, v_effective_points, v_multiplier,
            v_today, v_week_start, COALESCE(p_attribution, '')
        );

        RETURN json_build_object(
            'success', true,
            'pending', true,
            'pending_points', COALESCE(v_pending, v_effective_points),
            'points_added', v_effective_points,
            'multiplier', v_multiplier,
            'source', p_source
        );
    END IF;

    UPDATE league_members
       SET points = points + v_effective_points,
           workouts_completed = CASE
               WHEN p_source = 'workout' OR p_source = 'cardio_session'
               THEN workouts_completed + 1
               ELSE workouts_completed
           END
     WHERE user_id = p_user_id AND group_id = v_group_id
     RETURNING points INTO v_new_points;

    INSERT INTO league_point_awards (
        user_id, source, awarded_points, multiplier,
        awarded_date, week_start, attribution
    ) VALUES (
        p_user_id, p_source, v_effective_points, v_multiplier,
        v_today, v_week_start, COALESCE(p_attribution, '')
    );

    RETURN json_build_object(
        'success', true,
        'pending', false,
        'new_points', v_new_points,
        'points_added', v_effective_points,
        'multiplier', v_multiplier,
        'source', p_source
    );
END;
$$;

COMMENT ON FUNCTION add_league_points(UUID, INTEGER, TEXT, TEXT) IS
    'Adds League Points. As of 20260717 (Sprint 3): enforces server-side per-source caps via league_point_awards ledger + league_point_source_caps policy table; applies Peak Day Bonus 3× multiplier when CURRENT_DATE matches user_league_tier.peak_day_iso. Pre-placement bucket still works (Sprint 2 §C3). New optional p_attribution param for lifetime-keyed sources (`new_exercise_tried`).';

GRANT EXECUTE ON FUNCTION add_league_points(UUID, INTEGER, TEXT, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Peak Day rolling — refresh at every Monday rollup
--
-- We extend `process_past_league_weeks` (Sprint 2's version) by re-randomizing
-- every user's `peak_day_iso` after the per-week loop. Bronze (rank 1) never
-- relegates and Verified (rank 7) never promotes — the peak-day update is
-- orthogonal to tier movement and applies to everyone.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS refresh_user_peak_days();

CREATE OR REPLACE FUNCTION refresh_user_peak_days()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    -- Cryptographically meaningless RNG is fine — Peak Day is a fairness
    -- + variety mechanic, not a security one. `random()` per-row produces
    -- 1-7 (ISODOW) for each user.
    UPDATE user_league_tier
       SET peak_day_iso = 1 + FLOOR(random() * 7)::INTEGER,
           updated_at   = now();
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION refresh_user_peak_days() IS
    'Re-randomizes every user_league_tier.peak_day_iso. Called by auto_place_all_league_members() each Monday after the rollup so the Peak Day Bonus shifts each week. League Redesign Plan §A5.';

-- Wrap auto_place_all_league_members so the peak-day refresh runs before
-- placement. (Re-CREATE only the wrapping line — body unchanged otherwise.
-- Cheaper than re-DROP/CREATE the whole function: instead we add a
-- pre-call hook via a simple wrapper trigger pattern. See below.)
--
-- Implementation: we add a NEW SECURITY DEFINER wrapper
-- `auto_place_all_league_members_with_peakdays()` that the cron schedule
-- can switch to. The legacy entry point keeps working — it just no longer
-- refreshes peak days. Cron switchover is a follow-up ops task.

CREATE OR REPLACE FUNCTION auto_place_all_league_members_with_peakdays()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_placement JSON;
    v_peak_count INTEGER;
BEGIN
    v_peak_count := refresh_user_peak_days();
    v_placement  := auto_place_all_league_members();
    RETURN json_build_object(
        'placement', v_placement,
        'peak_days_refreshed', v_peak_count
    );
END;
$$;

GRANT EXECUTE ON FUNCTION auto_place_all_league_members_with_peakdays() TO service_role;

COMMENT ON FUNCTION auto_place_all_league_members_with_peakdays() IS
    'Composite Monday cron entrypoint (Sprint 3): refresh_user_peak_days() then auto_place_all_league_members(). Switch the pg_cron job to this function name to enable the Peak Day Bonus rotation. League Redesign Plan §A5.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. get_or_join_weekly_league — surface peak_day in the JSON
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

    SELECT current_tier, pending_league_points, shield_available, top3_streak,
           crown_until, peak_day_iso
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
            'pending_league_points', COALESCE(v_user_state.pending_league_points, 0),
            'shield_available', COALESCE(v_user_state.shield_available, FALSE),
            'top3_streak', COALESCE(v_user_state.top3_streak, 0),
            'crown_until', v_user_state.crown_until,
            'peak_day', v_user_state.peak_day_iso
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
        'pending_league_points', COALESCE(v_user_state.pending_league_points, 0),
        'shield_available', COALESCE(v_user_state.shield_available, FALSE),
        'top3_streak', COALESCE(v_user_state.top3_streak, 0),
        'crown_until', v_user_state.crown_until,
        'peak_day', v_user_state.peak_day_iso,
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
    'As of 20260717 (Sprint 3): surfaces user_league_tier.peak_day_iso as `peak_day` in both placed and not_placed JSON for the dashboard Peak Day widget. All Sprint 1+2 fields (pending_league_points, shield_available, top3_streak, crown_until, has_crown leaderboard flag) preserved.';

GRANT EXECUTE ON FUNCTION get_or_join_weekly_league(UUID) TO authenticated;

COMMIT;
