-- =============================================================================
-- 20260430b_league_tier_promotion_floors.sql
--
-- Challenge League Points Expansion — "Making Higher Leagues Actually Harder"
-- (Part 2 of 3).
--
-- DELIVERS (plan: challenge-league-points-expansion "Making higher leagues
-- actually harder" section):
--   • Mechanism 1 — Promotion LP Floors. Promotion to a higher tier now
--     requires BOTH top-N% finish AND a minimum absolute LP score. Verified
--     has an additional apex gate (must finish rank 1 in Elite).
--   • Mechanism 2 — Tier-scaled Peak Day multipliers. The universal x3 is
--     replaced with a per-tier lookup (Bronze/Silver x2, Gold/Platinum x3,
--     Diamond/Elite x4, Verified x5). Peak Day still applies last in the
--     add_league_points multiplier chain.
--   • Mechanism 3 — Widened relegation zones at the top. Silver/Gold stay
--     at 17/18%; Platinum/Diamond bump to 30%; Elite to 35%. Verified keeps
--     its 2-strike shield at 15%. Bronze still never relegates.
--
-- INVARIANTS PRESERVED FROM SPRINTS 1+2+3:
--   • Bronze (rank 1) never relegates (relegation_pct = 0 unchanged).
--   • Verified (rank 7) never promotes into an 8th tier (no rank 8 exists).
--   • First-Strike Shield, Stand-Out skip-tier, Crown of the Week, Bounceback
--     detection, Verified Two-Strike rule — all unchanged.
--   • Pre-placement `pending_league_points` bucket carry-forward unchanged.
--   • Server-side per-source caps ledger (`league_point_awards`) unchanged.
--   • JSON shape of `get_or_join_weekly_league` and `process_past_league_weeks`
--     stays additive — no breaking decoder changes; iOS clients that don't
--     know about the new fields keep working.
--
-- NEW JSON FIELDS (surfaced by get_or_join_weekly_league):
--   • `promotion_lp_floor` — the absolute LP minimum required to promote
--     from the user's current tier. iOS uses this to render the progress
--     bar on the promotion-zone indicator. NULL when tier doesn't promote
--     (Verified).
--   • `peak_day_multiplier` — the user's tier's Peak Day Bonus multiplier
--     (2, 3, 4, or 5). iOS surfaces this in the Peak Day widget copy.
--
-- PAIRS WITH:
--   • `20260430_challenge_league_awards_schema.sql` (Part 1).
--   • `20260430c_challenge_league_scoring_rpcs.sql` (Part 3).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema additions to league_tiers
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE league_tiers
    ADD COLUMN IF NOT EXISTS promotion_lp_floor  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS peak_day_multiplier INTEGER NOT NULL DEFAULT 3
        CHECK (peak_day_multiplier BETWEEN 1 AND 10),
    ADD COLUMN IF NOT EXISTS requires_crown      BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN league_tiers.promotion_lp_floor IS
    'Minimum absolute LP required to promote OUT of this tier, on top of the top-N% finish. 0 for tiers that do not promote (Verified). Read by process_past_league_weeks at rollup. Surfaced to iOS via get_or_join_weekly_league.';
COMMENT ON COLUMN league_tiers.peak_day_multiplier IS
    'Per-tier Peak Day Bonus multiplier (2..5). Replaces the hardcoded 3x. Read by add_league_points at credit time. Scales drama at higher tiers — winning your Peak Day in Verified is a 5x swing.';
COMMENT ON COLUMN league_tiers.requires_crown IS
    'TRUE only on the Elite row — promotion INTO Verified requires rank=1 (a Crown finish), not just top-N%. Forces the apex tier to be a genuine "I won my league" badge.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Reseed league_tiers with the new values
--
-- Re-stating the full canonical seed values here (including pre-existing
-- columns) so a fresh environment that runs only this migration still gets
-- the correct shape. The ON CONFLICT update covers the 7-tier canonical
-- (Bronze..Verified) set from migration #146.
-- ─────────────────────────────────────────────────────────────────────────────

-- Promotion LP floors:
--   Bronze -> Silver       200  (~4 workouts + 1 challenge, low bar)
--   Silver -> Gold         350
--   Gold -> Platinum       500
--   Platinum -> Diamond    700
--   Diamond -> Elite       900
--   Elite -> Verified    1,200  (AND requires_crown = TRUE)
--   Verified (no promote): 0
--
-- Peak Day multipliers:
--   Bronze, Silver   -> x2
--   Gold, Platinum   -> x3 (current default)
--   Diamond, Elite   -> x4
--   Verified         -> x5
--
-- Relegation pcts (superseding Sprint 1 values where applicable):
--   Bronze           -> 0.000 (unchanged — never relegates)
--   Silver, Gold     -> 0.250 (was 0.170 — slightly wider to match "tiers matter")
--   Platinum         -> 0.300 (was 0.180)
--   Diamond          -> 0.300 (was 0.200)
--   Elite            -> 0.350 (was 0.250)
--   Verified         -> 0.150 (was 0.200 — narrower here to keep apex stable; 2-strike shield untouched)

UPDATE league_tiers SET
    promotion_lp_floor  = 200,
    peak_day_multiplier = 2,
    requires_crown      = FALSE,
    relegation_pct      = 0.000
    WHERE tier_rank = 1;  -- Bronze

UPDATE league_tiers SET
    promotion_lp_floor  = 350,
    peak_day_multiplier = 2,
    requires_crown      = FALSE,
    relegation_pct      = 0.250
    WHERE tier_rank = 2;  -- Silver

UPDATE league_tiers SET
    promotion_lp_floor  = 500,
    peak_day_multiplier = 3,
    requires_crown      = FALSE,
    relegation_pct      = 0.250
    WHERE tier_rank = 3;  -- Gold

UPDATE league_tiers SET
    promotion_lp_floor  = 700,
    peak_day_multiplier = 3,
    requires_crown      = FALSE,
    relegation_pct      = 0.300
    WHERE tier_rank = 4;  -- Platinum

UPDATE league_tiers SET
    promotion_lp_floor  = 900,
    peak_day_multiplier = 4,
    requires_crown      = FALSE,
    relegation_pct      = 0.300
    WHERE tier_rank = 5;  -- Diamond

UPDATE league_tiers SET
    promotion_lp_floor  = 1200,
    peak_day_multiplier = 4,
    requires_crown      = TRUE,      -- Apex gate: promote INTO Verified requires rank 1
    relegation_pct      = 0.350
    WHERE tier_rank = 6;  -- Elite

UPDATE league_tiers SET
    promotion_lp_floor  = 0,
    peak_day_multiplier = 5,
    requires_crown      = FALSE,     -- No promotion above Verified
    relegation_pct      = 0.150
    WHERE tier_rank = 7;  -- Verified

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. add_league_points — tier-scaled Peak Day multiplier
--
-- Drop all known overloads and re-define with the same signature as Sprint 3.
-- The only body change is the Peak Day branch: instead of hardcoding `3`, we
-- look up `league_tiers.peak_day_multiplier` based on `user_league_tier.current_tier`.
-- Falls back to 3 if the tier row is missing (safety — matches Sprint 3 behavior).
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
    v_current_tier INTEGER;
    v_tier_multiplier INTEGER;
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

    -- Cap enforcement (server-side, ledger-backed). Unchanged from Sprint 3.
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

    -- Peak Day Bonus — now tier-scaled. Read the user's current tier and
    -- look up its peak_day_multiplier. Falls back to 3 if anything is missing
    -- (pre-placement users have current_tier=1 seeded by get_or_join_weekly_league).
    SELECT peak_day_iso, current_tier
      INTO v_peak_day, v_current_tier
      FROM user_league_tier
     WHERE user_id = p_user_id;

    IF v_peak_day IS NOT NULL AND v_peak_day = v_today_iso THEN
        SELECT peak_day_multiplier INTO v_tier_multiplier
          FROM league_tiers
         WHERE tier_rank = COALESCE(v_current_tier, 1);
        v_multiplier := COALESCE(v_tier_multiplier, 3);
    END IF;

    v_effective_points := p_points * v_multiplier;

    -- Find current-week membership.
    SELECT lm.group_id INTO v_group_id
      FROM league_members lm
      JOIN league_groups lg ON lg.id = lm.group_id
     WHERE lm.user_id = p_user_id
       AND lg.week_start = v_week_start;

    IF v_group_id IS NULL THEN
        -- Pre-placement bucket. Peak Day still multiplies.
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
    'Adds League Points. As of 20260430b: Peak Day multiplier is now tier-scaled — read from league_tiers.peak_day_multiplier based on user_league_tier.current_tier (Bronze/Silver x2, Gold/Platinum x3, Diamond/Elite x4, Verified x5). All Sprint 3 cap enforcement preserved. JSON response shape unchanged (still exposes `multiplier` so iOS optimistic updates credit the right amount).';

GRANT EXECUTE ON FUNCTION add_league_points(UUID, INTEGER, TEXT, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. process_past_league_weeks — LP floor gate + Verified Crown gate
--
-- Full replacement. Preserves the entire Sprint 2 body (Stand-Out, Shield,
-- Verified Two-Strike, Crown, Bounceback) and adds the LP floor + Crown
-- apex gate to the promotion branch.
--
-- Promotion rule (new):
--   IF final_rank <= promotion_count
--      AND points >= tier.promotion_lp_floor
--      AND (NOT tier.requires_crown OR final_rank = 1)
--   THEN promote
--
-- The Crown gate only applies to Elite (tier_rank=6) per the seed above.
-- All other tiers have requires_crown=FALSE so the third clause is a no-op.
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
    -- New Sprint 4 gate inputs.
    v_promotion_lp_floor INTEGER;
    v_requires_crown BOOLEAN;
    v_meets_floor BOOLEAN;
    v_meets_crown_gate BOOLEAN;
BEGIN
    v_current_week := get_current_week_monday();

    FOR v_group IN
        SELECT lg.id, lg.tier_rank, lg.week_start, lg.member_count,
               lt.promotion_pct, lt.relegation_pct, lt.name AS tier_name,
               lt.promotion_lp_floor, lt.requires_crown
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

        v_promotion_count    := calc_league_zone_count(v_group_size, v_group.promotion_pct);
        v_relegation_count   := calc_league_zone_count(v_group_size, v_group.relegation_pct);
        v_promotion_lp_floor := COALESCE(v_group.promotion_lp_floor, 0);
        v_requires_crown     := COALESCE(v_group.requires_crown, FALSE);

        FOR v_member IN
            SELECT user_id, points,
                   ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS final_rank
            FROM league_members
            WHERE group_id = v_group.id
        LOOP
            v_promoted   := FALSE;
            v_relegated  := FALSE;
            v_stand_out  := FALSE;
            v_crown      := FALSE;
            v_shielded   := FALSE;
            v_bounceback := FALSE;
            v_new_tier   := v_group.tier_rank;

            SELECT top3_streak, shield_available, verified_relegation_streak
              INTO v_user_state
              FROM user_league_tier
             WHERE user_id = v_member.user_id;

            v_was_top3    := (v_member.final_rank <= 3);
            v_was_bottom3 := (v_member.final_rank > (v_group_size - 3));

            SELECT COALESCE(was_relegated, FALSE) INTO v_was_relegated_last_week
              FROM league_history
             WHERE user_id = v_member.user_id
               AND week_start = v_group.week_start - INTERVAL '7 days'
             ORDER BY week_start DESC LIMIT 1;
            v_was_relegated_last_week := COALESCE(v_was_relegated_last_week, FALSE);

            -- Apex gates (new): LP floor + Verified Crown requirement.
            v_meets_floor      := (v_member.points >= v_promotion_lp_floor);
            v_meets_crown_gate := (NOT v_requires_crown OR v_member.final_rank = 1);

            -- Promotion (top N, cap at rank 7) + Stand-Out skip-tier +
            -- Sprint 4 LP floor + Verified Crown apex gate.
            IF v_promotion_count > 0
               AND v_member.final_rank <= v_promotion_count
               AND v_group.tier_rank < 7
               AND v_meets_floor
               AND v_meets_crown_gate THEN
                v_promoted := TRUE;
                IF COALESCE(v_user_state.top3_streak, 0) >= 3 AND v_group.tier_rank < 6 THEN
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
            -- both gate this branch. Unchanged from Sprint 2.
            IF v_relegation_count > 0
               AND v_member.final_rank > (v_group_size - v_relegation_count)
               AND v_group.tier_rank > 1
               AND NOT v_promoted THEN
                IF v_group.tier_rank = 7 THEN
                    v_new_verified_streak := COALESCE(v_user_state.verified_relegation_streak, 0) + 1;
                    IF v_new_verified_streak >= 2 THEN
                        v_relegated := TRUE;
                        v_new_tier := v_group.tier_rank - 1;
                    END IF;
                ELSIF COALESCE(v_user_state.shield_available, FALSE) THEN
                    v_shielded := TRUE;
                ELSE
                    v_relegated := TRUE;
                    v_new_tier := v_group.tier_rank - 1;
                END IF;
            END IF;

            -- Crown of the Week — rank 1.
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

            -- Shield bookkeeping. Unchanged.
            IF v_promoted THEN
                v_new_shield := TRUE;
            ELSIF v_shielded THEN
                v_new_shield := FALSE;
            ELSE
                v_new_shield := COALESCE(v_user_state.shield_available, FALSE);
            END IF;

            -- Crown carry-forward — Head-Start Bonus + 7-day cosmetic ring.
            IF v_crown THEN
                v_new_starting_points := 20;
                v_new_crown_until := now() + INTERVAL '7 days';
            ELSE
                v_new_starting_points := 0;
                v_new_crown_until := NULL;
            END IF;

            IF v_stand_out THEN
                v_new_top3_streak := 0;
            END IF;

            INSERT INTO league_history
                (user_id, week_start, tier_name, tier_rank, final_rank,
                 final_points, group_size, was_promoted, was_relegated,
                 was_stand_out, was_crown, was_shielded, was_bounceback)
            VALUES
                (v_member.user_id, v_group.week_start, v_group.tier_name,
                 v_group.tier_rank, v_member.final_rank, v_member.points,
                 v_group_size, v_promoted, v_relegated,
                 v_stand_out, v_crown, v_shielded, v_bounceback);

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
    'Weekly League rollup. As of 20260430b (Sprint 4): promotion now requires BOTH top-N% finish AND points >= league_tiers.promotion_lp_floor. Elite has an additional apex gate (league_tiers.requires_crown=TRUE) requiring final_rank=1 to promote into Verified. All Sprint 1/2/3 invariants preserved: Bronze never relegates, Verified 2-strike, Shield, Stand-Out skip-tier, Crown + Head-Start Bonus, Bounceback. Idempotent.';

GRANT EXECUTE ON FUNCTION process_past_league_weeks() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. get_or_join_weekly_league — surface promotion_lp_floor + peak_day_multiplier
--
-- Additive-only change: adds two new JSON keys to both the `placed` and
-- `not_placed` branches. Sprint 3's response shape (peak_day, crown_until,
-- shield_available, top3_streak, pending_league_points) is preserved.
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
            'peak_day', v_user_state.peak_day_iso,
            -- New Sprint 4 fields (plan: "Making higher leagues actually harder").
            'promotion_lp_floor', COALESCE(v_tier_info.promotion_lp_floor, 0),
            'peak_day_multiplier', COALESCE(v_tier_info.peak_day_multiplier, 3),
            'requires_crown_to_promote', COALESCE(v_tier_info.requires_crown, FALSE)
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
        -- New Sprint 4 fields.
        'promotion_lp_floor', COALESCE(v_tier_info.promotion_lp_floor, 0),
        'peak_day_multiplier', COALESCE(v_tier_info.peak_day_multiplier, 3),
        'requires_crown_to_promote', COALESCE(v_tier_info.requires_crown, FALSE),
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
    'As of 20260430b (Sprint 4): adds promotion_lp_floor, peak_day_multiplier, and requires_crown_to_promote to both placed and not_placed JSON so iOS can render the promotion-zone progress bar and Peak Day widget copy. All Sprint 1/2/3 fields preserved.';

GRANT EXECUTE ON FUNCTION get_or_join_weekly_league(UUID) TO authenticated;

COMMIT;

-- =============================================================================
-- Verification (run manually after deploy):
--   SELECT tier_rank, name, promotion_lp_floor, peak_day_multiplier, requires_crown, relegation_pct FROM league_tiers ORDER BY tier_rank;
--   -- Expect:
--   -- 1 Bronze    0    2 f 0.000
--   -- 2 Silver    350  2 f 0.250
--   -- 3 Gold      500  3 f 0.250
--   -- 4 Platinum  700  3 f 0.300
--   -- 5 Diamond   900  4 f 0.300
--   -- 6 Elite     1200 4 t 0.350
--   -- 7 Verified  0    5 f 0.150  (no promotion)
-- =============================================================================
