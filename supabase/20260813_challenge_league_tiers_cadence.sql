-- =============================================================================
-- 20260813_challenge_league_tiers_cadence.sql
--
-- Migration #183 — Wires the Sprint 20260811 catalog expansion (#180 / #181 /
-- #182) into the Challenge League Points system shipped in
-- `20260430_challenge_league_awards_schema.sql` (#176) /
-- `20260430b_league_tier_promotion_floors.sql` (#177) /
-- `20260430c_challenge_league_scoring_rpcs.sql` (#178).
--
-- NUMBERING NOTE: an earlier draft of this file claimed #179, but #179 is
-- already taken by `20260501_challenge_lp_push_notifications.sql`
-- (Challenge LP Expansion Part 4/3 — push wiring). This file's number is
-- #183 in the release train; #180 / #181 / #182 are the catalog templates
-- table, target_cadence column, and create_community_challenge cadence
-- widening respectively.
--
-- WITHOUT this migration:
--   1. The 5 new ChallengeType cases (cycling, swim, stairs_climbed,
--      total_volume_lifted, mind_body_minutes) all silently fall back to the
--      `_unknown_ → easy` defaults inside compute_challenge_daily_awards
--      (10/15 LP). That's not catastrophic — they still earn LP — but it
--      under-rewards real cardio (cycling/swim) and strength (volume).
--   2. Cadence-aware challenges (target_cadence in weekly / total /
--      per_session) get ZERO daily LP awards because #177's cadence-aware
--      progress writers set per-row `target_hit = FALSE` for those rows
--      (the leaderboard computes period_progress on read; the daily column
--      stays unset). compute_challenge_daily_awards reads target_hit from
--      the daily progress row and decides "did the user get hit_target this
--      day?" — no TRUE rows = no awards.
--
-- THIS MIGRATION:
--   • Seeds 5 new rows in `challenge_award_tiers` so the new types match
--     intuitive effort levels.
--   • Recreates `compute_challenge_daily_awards` to be cadence-aware:
--       daily       → unchanged (per-row target_hit)
--       per_session → unchanged (per-row target_hit; multiple qualifying
--                                sessions on different days each award)
--       weekly      → recompute target_hit on the day the running ISO-week
--                     SUM crosses daily_target (one award per week)
--       total       → recompute target_hit on the day the running CHALLENGE
--                     cumulative crosses daily_target (one award per
--                     challenge — milestone hit; rest of the LP comes via
--                     the Final Bell pot)
--   • Preserves every other behavior: day_winner, intensity, early_bird,
--     per-challenge cap, cross-challenge cap, idempotent ledger.
--
-- INVARIANT (paired): The challenge_award_tiers seed table MUST cover every
-- ChallengeType case in `Fit33/ChallengeService.swift:3459`. When adding a
-- new ChallengeType, append a tiers row in a new migration in the same PR
-- as the Swift change.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Seed challenge_award_tiers for the 5 new types
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO challenge_award_tiers (challenge_type, effort_tier, base_hit, base_win, notes) VALUES
    ('cycling',             'moderate', 15, 20, 'Real cardio session — moderate effort, lower per-minute intensity than running.'),
    ('swim',                'hard',     20, 25, 'High cardiac demand + skill. Mirrors run/lift effort.'),
    ('stairs_climbed',      'easy',     10, 15, 'Passive-ish like steps — cumulative low-bar ambient activity.'),
    ('total_volume_lifted', 'hard',     20, 25, 'Working-set tonnage = real strength work; mirrors lift.'),
    ('mind_body_minutes',   'easy',     10, 15, 'Yoga / mobility / flexibility — recovery-positive but not high-intensity.')
ON CONFLICT (challenge_type) DO UPDATE SET
    effort_tier = EXCLUDED.effort_tier,
    base_hit    = EXCLUDED.base_hit,
    base_win    = EXCLUDED.base_win,
    notes       = EXCLUDED.notes;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Cadence-aware compute_challenge_daily_awards
--
-- Drop every known overload (supabase-rules invariant 12) before recreating.
-- Body diff vs. 20260430c:
--   • Read `target_cadence` from the parent challenge row alongside the
--     existing header.
--   • When loading `_cda_rows`, recompute `target_hit` per the cadence
--     semantics described above (using a simple correlated subquery for the
--     running sums — fine because we cap participants per challenge).
--   • Use `effective_target_hit` (the recomputed flag) everywhere downstream
--     instead of `cdp.target_hit`. The original column stays untouched on
--     disk — this is purely a read-time correction.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS compute_challenge_daily_awards(TEXT, UUID, DATE);

CREATE OR REPLACE FUNCTION compute_challenge_daily_awards(
    p_challenge_kind TEXT,
    p_challenge_id UUID,
    p_day DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_header RECORD;
    v_tier RECORD;
    v_participant RECORD;
    v_leader_value INTEGER := 0;
    v_participant_count INTEGER := 0;
    v_winner_count INTEGER;
    v_early_bird_user UUID;
    v_week_start DATE;
    v_per_challenge_cap CONSTANT INTEGER := 100;
    v_cross_challenge_daily_cap CONSTANT INTEGER := 500;
    v_already_today_for_user INTEGER;
    v_capacity INTEGER;
    v_total_points INTEGER;
    v_award_rows INTEGER := 0;
    v_add_result JSON;
    v_effective_kind TEXT;
    v_target_cadence TEXT;
    v_iso_week_start DATE;  -- Monday of the ISO week containing p_day
BEGIN
    IF p_challenge_kind NOT IN ('1v1','group','private','community') THEN
        RAISE EXCEPTION 'Invalid challenge_kind: %', p_challenge_kind
            USING ERRCODE = '22023';
    END IF;

    IF p_day IS NULL THEN
        RAISE EXCEPTION 'p_day is required' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_header FROM _challenge_league_header(
        CASE WHEN p_challenge_kind = '1v1' THEN 'group' ELSE p_challenge_kind END,
        p_challenge_id
    );

    IF v_header.challenge_type IS NULL THEN
        RETURN json_build_object('success', false, 'reason', 'challenge_not_found',
                                  'challenge_id', p_challenge_id);
    END IF;

    IF p_day < v_header.start_date OR p_day > v_header.end_date THEN
        RETURN json_build_object('success', false, 'reason', 'day_outside_window',
                                  'day', p_day,
                                  'start_date', v_header.start_date,
                                  'end_date', v_header.end_date);
    END IF;

    -- Cadence lookup. The _challenge_league_header helper doesn't return it,
    -- so fetch from the parent table directly. Default to 'daily' for
    -- pre-#177 challenges that lack the column entirely (graceful).
    v_target_cadence := 'daily';
    IF p_challenge_kind IN ('1v1','group') THEN
        SELECT COALESCE(target_cadence, 'daily') INTO v_target_cadence
          FROM group_challenges WHERE id = p_challenge_id;
    ELSIF p_challenge_kind = 'private' THEN
        SELECT COALESCE(target_cadence, 'daily') INTO v_target_cadence
          FROM private_challenges WHERE id = p_challenge_id;
    ELSIF p_challenge_kind = 'community' THEN
        SELECT COALESCE(target_cadence, 'daily') INTO v_target_cadence
          FROM community_challenges WHERE id = p_challenge_id;
    END IF;

    -- Tier lookup (fallback to easy defaults — preserved from 20260430c).
    SELECT challenge_type, effort_tier, base_hit, base_win, notes
      INTO v_tier
      FROM challenge_award_tiers
     WHERE challenge_type = v_header.challenge_type;

    IF v_tier.challenge_type IS NULL THEN
        SELECT '_unknown_'::TEXT  AS challenge_type,
               'easy'::TEXT       AS effort_tier,
               10::INTEGER        AS base_hit,
               15::INTEGER        AS base_win,
               'fallback'::TEXT   AS notes
          INTO v_tier;
    END IF;

    v_week_start     := get_current_week_monday();
    v_iso_week_start := date_trunc('week', p_day)::DATE;

    -- Resolve effective kind (1v1 vs group based on participant count).
    IF p_challenge_kind IN ('1v1','group') THEN
        SELECT CASE WHEN COUNT(*) = 2 THEN '1v1' ELSE 'group' END
          INTO v_effective_kind
          FROM challenge_participants
         WHERE challenge_id = p_challenge_id
           AND status = 'accepted';
    ELSE
        v_effective_kind := p_challenge_kind;
    END IF;

    -- Materialize per-participant rows for THIS day. effective_target_hit
    -- reflects the cadence-aware "did the user hit the target?" answer,
    -- which is the key change in this migration:
    --
    --   daily       → row.target_hit (existing per-row column)
    --   per_session → row.progress_value >= daily_target (single qualifying
    --                 session anywhere in the window — multiple qualifying
    --                 sessions on different days each fire)
    --   weekly      → SUM(progress_value) over the ISO week ending today
    --                 crosses daily_target FOR THE FIRST TIME today (i.e.
    --                 yesterday's running sum was BELOW the target). One
    --                 award per ISO week.
    --   total       → cumulative SUM since challenge start crosses
    --                 daily_target for the first time today. One award per
    --                 challenge — the rest of the reward comes via Final Bell.

    CREATE TEMP TABLE IF NOT EXISTS _cda_rows (
        user_id UUID,
        progress_value INTEGER,
        target_hit BOOLEAN,
        effective_target_hit BOOLEAN,
        updated_at TIMESTAMPTZ
    ) ON COMMIT DROP;
    TRUNCATE _cda_rows;

    IF v_effective_kind IN ('1v1','group') THEN
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, effective_target_hit, updated_at)
        SELECT
            cdp.user_id,
            cdp.progress_value,
            cdp.target_hit,
            CASE
                WHEN v_target_cadence = 'daily' THEN
                    cdp.target_hit
                WHEN v_target_cadence = 'per_session' THEN
                    (v_header.daily_target IS NOT NULL
                     AND cdp.progress_value >= v_header.daily_target)
                WHEN v_target_cadence = 'weekly' THEN
                    -- Running ISO-week sum INCLUDING today crosses target,
                    -- AND the sum EXCLUDING today (yesterday's EoD) did not.
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = cdp.user_id
                               AND c2.progress_date >= v_iso_week_start
                               AND c2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = cdp.user_id
                               AND c2.progress_date >= v_iso_week_start
                               AND c2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                WHEN v_target_cadence = 'total' THEN
                    -- Cumulative challenge total crosses target today AND
                    -- did NOT cross prior to today.
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = cdp.user_id
                               AND c2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = cdp.user_id
                               AND c2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                ELSE
                    cdp.target_hit
            END,
            cdp.updated_at
          FROM challenge_daily_progress cdp
         WHERE cdp.challenge_id = p_challenge_id
           AND cdp.progress_date = p_day;
    ELSIF v_effective_kind = 'private' THEN
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, effective_target_hit, updated_at)
        SELECT
            pcdp.user_id,
            pcdp.progress_value,
            pcdp.target_hit,
            CASE
                WHEN v_target_cadence = 'daily' THEN
                    pcdp.target_hit
                WHEN v_target_cadence = 'per_session' THEN
                    (v_header.daily_target IS NOT NULL
                     AND pcdp.progress_value >= v_header.daily_target)
                WHEN v_target_cadence = 'weekly' THEN
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(p2.progress_value)
                              FROM private_challenge_daily_progress p2
                             WHERE p2.challenge_id = p_challenge_id
                               AND p2.user_id = pcdp.user_id
                               AND p2.progress_date >= v_iso_week_start
                               AND p2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(p2.progress_value)
                              FROM private_challenge_daily_progress p2
                             WHERE p2.challenge_id = p_challenge_id
                               AND p2.user_id = pcdp.user_id
                               AND p2.progress_date >= v_iso_week_start
                               AND p2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                WHEN v_target_cadence = 'total' THEN
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(p2.progress_value)
                              FROM private_challenge_daily_progress p2
                             WHERE p2.challenge_id = p_challenge_id
                               AND p2.user_id = pcdp.user_id
                               AND p2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(p2.progress_value)
                              FROM private_challenge_daily_progress p2
                             WHERE p2.challenge_id = p_challenge_id
                               AND p2.user_id = pcdp.user_id
                               AND p2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                ELSE
                    pcdp.target_hit
            END,
            pcdp.updated_at
          FROM private_challenge_daily_progress pcdp
         WHERE pcdp.challenge_id = p_challenge_id
           AND pcdp.progress_date = p_day;
    ELSE
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, effective_target_hit, updated_at)
        SELECT
            ccdp.user_id,
            ccdp.progress_value,
            ccdp.target_hit,
            CASE
                WHEN v_target_cadence = 'daily' THEN
                    ccdp.target_hit
                WHEN v_target_cadence = 'per_session' THEN
                    (v_header.daily_target IS NOT NULL
                     AND ccdp.progress_value >= v_header.daily_target)
                WHEN v_target_cadence = 'weekly' THEN
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM community_challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = ccdp.user_id
                               AND c2.progress_date >= v_iso_week_start
                               AND c2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM community_challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = ccdp.user_id
                               AND c2.progress_date >= v_iso_week_start
                               AND c2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                WHEN v_target_cadence = 'total' THEN
                    (
                        v_header.daily_target IS NOT NULL
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM community_challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = ccdp.user_id
                               AND c2.progress_date <= p_day
                        ), 0) >= v_header.daily_target
                        AND COALESCE((
                            SELECT SUM(c2.progress_value)
                              FROM community_challenge_daily_progress c2
                             WHERE c2.challenge_id = p_challenge_id
                               AND c2.user_id = ccdp.user_id
                               AND c2.progress_date < p_day
                        ), 0) < v_header.daily_target
                    )
                ELSE
                    ccdp.target_hit
            END,
            ccdp.updated_at
          FROM community_challenge_daily_progress ccdp
         WHERE ccdp.challenge_id = p_challenge_id
           AND ccdp.progress_date = p_day;
    END IF;

    SELECT COUNT(*) INTO v_participant_count FROM _cda_rows;

    IF v_participant_count = 0 THEN
        RETURN json_build_object('success', true, 'awards_written', 0,
                                  'reason', 'no_progress_rows',
                                  'cadence', v_target_cadence);
    END IF;

    -- Daily leader uses the cadence-aware effective_target_hit so we don't
    -- declare a "day winner" on a row that doesn't actually represent the
    -- user crossing the cadence threshold.
    SELECT MAX(progress_value) INTO v_leader_value FROM _cda_rows WHERE effective_target_hit;
    SELECT COUNT(*) INTO v_winner_count
      FROM _cda_rows
     WHERE effective_target_hit AND progress_value = v_leader_value;

    -- Early bird (1v1 only): first user to hit (cadence-aware) target this day.
    IF v_effective_kind = '1v1' THEN
        SELECT user_id INTO v_early_bird_user
          FROM _cda_rows
         WHERE effective_target_hit
         ORDER BY updated_at ASC NULLS LAST
         LIMIT 1;
    END IF;

    -- Walk every participant and score them.
    FOR v_participant IN
        SELECT user_id, progress_value, target_hit, effective_target_hit, updated_at FROM _cda_rows
    LOOP
        v_total_points := 0;

        -- Award 1: hit_target (cadence-aware)
        IF v_participant.effective_target_hit THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_participant.user_id, v_effective_kind, p_challenge_id, p_day,
                'hit_target',
                v_tier.base_hit, 1.0, v_tier.base_hit, v_week_start,
                CASE
                    WHEN v_target_cadence = 'daily' THEN
                        format('Hit %s daily target (%s)', v_tier.effort_tier, v_header.challenge_type)
                    WHEN v_target_cadence = 'weekly' THEN
                        format('Crossed %s weekly target (%s)', v_tier.effort_tier, v_header.challenge_type)
                    WHEN v_target_cadence = 'total' THEN
                        format('Reached %s challenge total (%s)', v_tier.effort_tier, v_header.challenge_type)
                    ELSE
                        format('Qualifying %s session (%s)', v_tier.effort_tier, v_header.challenge_type)
                END
            )
            ON CONFLICT DO NOTHING;
            IF FOUND THEN
                v_total_points := v_total_points + v_tier.base_hit;
                v_award_rows := v_award_rows + 1;
            END IF;
        END IF;

        -- Award 2: day_winner (sole leader only, ties fall through)
        IF v_participant.effective_target_hit
           AND v_leader_value > 0
           AND v_participant.progress_value = v_leader_value
           AND v_winner_count = 1
        THEN
            DECLARE
                v_multiplier NUMERIC;
                v_extra INTEGER;
            BEGIN
                IF v_effective_kind = '1v1' THEN
                    v_multiplier := 2.0;
                ELSIF v_effective_kind IN ('group','private') THEN
                    v_multiplier := 1.5;
                ELSE
                    v_multiplier := 1.25;
                END IF;
                v_extra := GREATEST(0, ROUND(v_tier.base_win * v_multiplier)::INTEGER - v_tier.base_hit);

                INSERT INTO challenge_league_awards (
                    user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                    base_points, multiplier_applied, final_points, week_start, note
                ) VALUES (
                    v_participant.user_id, v_effective_kind, p_challenge_id, p_day,
                    'day_winner',
                    v_tier.base_win, v_multiplier, v_extra, v_week_start,
                    format('Day winner (%s) — %sx', v_effective_kind, v_multiplier)
                )
                ON CONFLICT DO NOTHING;
                IF FOUND THEN
                    v_total_points := v_total_points + v_extra;
                    v_award_rows := v_award_rows + 1;
                END IF;
            END;
        END IF;

        -- Award 3: intensity (>=150/200/300% of target) — only meaningful
        -- for daily / per_session cadences where the row's progress_value
        -- IS the target-relative number. For weekly / total the per-row
        -- value isn't directly comparable to daily_target (it's a
        -- contribution toward an aggregate goal), so intensity is skipped.
        IF v_participant.effective_target_hit
           AND v_target_cadence IN ('daily','per_session')
           AND v_header.daily_target > 0
           AND v_participant.progress_value >= v_header.daily_target
        THEN
            DECLARE
                v_ratio NUMERIC;
                v_intensity_multiplier NUMERIC := 0;
                v_intensity_bonus INTEGER;
            BEGIN
                v_ratio := v_participant.progress_value::NUMERIC / v_header.daily_target::NUMERIC;
                IF v_ratio >= 3.0 THEN
                    v_intensity_multiplier := 1.0;
                ELSIF v_ratio >= 2.0 THEN
                    v_intensity_multiplier := 0.5;
                ELSIF v_ratio >= 1.5 THEN
                    v_intensity_multiplier := 0.25;
                END IF;
                IF v_intensity_multiplier > 0 THEN
                    v_intensity_bonus := ROUND(v_tier.base_hit * v_intensity_multiplier)::INTEGER;
                    INSERT INTO challenge_league_awards (
                        user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                        base_points, multiplier_applied, final_points, week_start, note
                    ) VALUES (
                        v_participant.user_id, v_effective_kind, p_challenge_id, p_day,
                        'intensity',
                        v_tier.base_hit, 1.0 + v_intensity_multiplier, v_intensity_bonus, v_week_start,
                        format('%sx target', ROUND(v_ratio, 2))
                    )
                    ON CONFLICT DO NOTHING;
                    IF FOUND THEN
                        v_total_points := v_total_points + v_intensity_bonus;
                        v_award_rows := v_award_rows + 1;
                    END IF;
                END IF;
            END;
        END IF;

        -- Award 4: early_bird (1v1 only)
        IF v_effective_kind = '1v1'
           AND v_participant.effective_target_hit
           AND v_early_bird_user IS NOT NULL
           AND v_participant.user_id = v_early_bird_user
        THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_participant.user_id, v_effective_kind, p_challenge_id, p_day,
                'early_bird',
                10, 1.0, 10, v_week_start,
                CASE v_target_cadence
                    WHEN 'weekly' THEN 'First to cross the weekly target'
                    WHEN 'total' THEN 'First to reach the challenge total'
                    WHEN 'per_session' THEN 'First to log a qualifying session'
                    ELSE 'First to hit target'
                END
            )
            ON CONFLICT DO NOTHING;
            IF FOUND THEN
                v_total_points := v_total_points + 10;
                v_award_rows := v_award_rows + 1;
            END IF;
        END IF;

        -- Per-challenge cap.
        IF v_total_points > v_per_challenge_cap THEN
            v_total_points := v_per_challenge_cap;
        END IF;

        -- Cross-challenge daily cap.
        IF v_total_points > 0 THEN
            SELECT COALESCE(SUM(final_points), 0) INTO v_already_today_for_user
              FROM challenge_league_awards cla
             WHERE cla.user_id = v_participant.user_id
               AND cla.challenge_day = p_day
               AND cla.challenge_id <> p_challenge_id
               AND cla.award_kind IN ('hit_target','day_winner','intensity','early_bird');

            v_capacity := GREATEST(0, v_cross_challenge_daily_cap - v_already_today_for_user);
            IF v_total_points > v_capacity THEN
                v_total_points := v_capacity;
            END IF;
        END IF;

        -- Credit to the league balance.
        IF v_total_points > 0 THEN
            SELECT add_league_points(
                v_participant.user_id,
                v_total_points,
                'challenge_daily',
                p_challenge_id::TEXT || ':' || p_day::TEXT
            ) INTO v_add_result;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'challenge_id', p_challenge_id,
        'challenge_kind', v_effective_kind,
        'cadence', v_target_cadence,
        'day', p_day,
        'awards_written', v_award_rows,
        'participant_count', v_participant_count
    );
END;
$$;

COMMENT ON FUNCTION compute_challenge_daily_awards(TEXT, UUID, DATE) IS
    'Daily Duel rollup — cadence-aware since 20260813. Reads target_cadence from the challenge parent row and computes effective_target_hit per cadence: daily/per_session use per-row target_hit semantics; weekly fires once on threshold-crossing day per ISO week; total fires once per challenge on cumulative-cross day. Idempotent via challenge_league_awards UNIQUE. Service-role / pg_cron only.';

GRANT EXECUTE ON FUNCTION compute_challenge_daily_awards(TEXT, UUID, DATE) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. AUDIT — fail-loud verification
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_tier_count        INTEGER;
    v_function_count    INTEGER;
    v_function_body     TEXT;
    v_missing_types     TEXT[];
BEGIN
    -- Every Swift ChallengeType raw value must have a tier row. Hard-coded
    -- list mirrors the enum's rawValues at the time of this migration.
    v_missing_types := ARRAY(
        SELECT t FROM unnest(ARRAY[
            'steps','walk','run','lift','workout_streak','active_minutes',
            'hydrate','calories','protein',
            'sleep_hours','readiness_average','strain_budget',
            'cycling','swim','stairs_climbed','total_volume_lifted','mind_body_minutes'
        ]) t
        WHERE NOT EXISTS (
            SELECT 1 FROM challenge_award_tiers WHERE challenge_type = t
        )
    );

    IF array_length(v_missing_types, 1) > 0 THEN
        RAISE EXCEPTION
            '[20260813 audit] challenge_award_tiers missing rows for: %',
            array_to_string(v_missing_types, ', ');
    END IF;

    SELECT COUNT(*) INTO v_tier_count FROM challenge_award_tiers;
    IF v_tier_count < 17 THEN
        RAISE EXCEPTION
            '[20260813 audit] challenge_award_tiers count = % (expected ≥ 17 = 12 original + 5 new)',
            v_tier_count;
    END IF;

    -- Exactly one compute_challenge_daily_awards overload.
    SELECT COUNT(*), MAX(prosrc)
      INTO v_function_count, v_function_body
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'compute_challenge_daily_awards';

    IF v_function_count <> 1 THEN
        RAISE EXCEPTION
            '[20260813 audit] expected exactly 1 compute_challenge_daily_awards overload, got %',
            v_function_count;
    END IF;

    -- The new body MUST reference target_cadence (proves the recreate landed).
    IF v_function_body !~ 'v_target_cadence' THEN
        RAISE EXCEPTION
            '[20260813 audit] compute_challenge_daily_awards body missing cadence-aware branch';
    END IF;

    -- The new body MUST reference effective_target_hit.
    IF v_function_body !~ 'effective_target_hit' THEN
        RAISE EXCEPTION
            '[20260813 audit] compute_challenge_daily_awards body missing effective_target_hit recomputation';
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ MIGRATION #179 COMPLETE — challenge League Points cadence-aware';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • % tier rows seeded (5 new types added)', v_tier_count;
    RAISE NOTICE '   • compute_challenge_daily_awards now respects target_cadence';
    RAISE NOTICE '   • daily/per_session use per-row target_hit; weekly/total';
    RAISE NOTICE '     compute threshold-crossing on the fly';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
