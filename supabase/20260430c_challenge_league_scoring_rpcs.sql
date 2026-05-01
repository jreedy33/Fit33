-- =============================================================================
-- 20260430c_challenge_league_scoring_rpcs.sql
--
-- Challenge League Points Expansion — "Daily Duels, Final Bell" (Part 3 of 3).
-- The scoring engine.
--
-- DELIVERS (plan: challenge-league-points-expansion):
--   • compute_challenge_daily_awards(p_challenge_kind, p_challenge_id, p_day)
--     — per-challenge daily rollup. Computes hit/winner/intensity/early-bird
--     awards per participant, writes ledger rows, calls add_league_points
--     with the summed per-user amount (so Peak Day multiplier composes on
--     the total).
--   • compute_challenge_final_bell(p_challenge_kind, p_challenge_id)
--     — fires on 1v1/group/private status transition to completed. Pot is
--     round(25 * sqrt(duration_days)); payouts by rank (1v1) or percentile
--     (group/private). Unbroken Chain multiplier when user hit target every
--     single day.
--   • compute_community_wave_final_bell(p_challenge_id, p_wave_end_date)
--     — Sunday 23:59 UTC cron. Percentile payouts (top 1% = 2x pot, top 5%
--     = 1x, top 10% = 0.5x, top 25% = 0.25x, top 50% = 0.1x) for the
--     wave's 7-day window.
--   • run_challenge_daily_rollup_hourly() + pg_cron '0 * * * *' — detects
--     per-challenge creator_timezone midnight passing and rolls up yesterday.
--     Idempotent via the ledger UNIQUE constraint.
--   • auto_complete_expired_challenges() updated to fire Final Bell.
--   • get_challenge_details extended with daily_league_awards array.
--   • get_challenge_league_awards / get_league_member_breakdown read RPCs.
--
-- INVARIANTS:
--   • Every writer RPC is SECURITY DEFINER and takes NO user_id parameter
--     (per supabase-rules.mdc). Service role / pg_cron bypass the auth.uid()
--     gate.
--   • Ledger UNIQUE indexes (created in Part 1) make re-runs idempotent —
--     ON CONFLICT DO NOTHING + summed insert-or-skip pattern.
--   • Peak Day multiplier is NOT applied inside these RPCs. It is applied
--     inside add_league_points at credit time so the Sprint 3 multiplier
--     chain is the single source of truth.
--   • get_league_member_breakdown is own-user-only (IDOR-guarded). Cross-user
--     breakdown visibility is out of scope for this migration; iOS will
--     render "tap your own row" only.
--
-- PAIRS WITH:
--   • `20260430_challenge_league_awards_schema.sql` (Part 1 — tables + seed).
--   • `20260430b_league_tier_promotion_floors.sql` (Part 2 — promotion floors).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Helper: fetch challenge header (type, target, duration, timezone, dates)
--
-- Polymorphic across the four challenge surfaces. Returns a single-row
-- RECORD-shaped result so compute_* RPCs can run one SELECT and branch on the
-- unified fields.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS _challenge_league_header(TEXT, UUID);

CREATE OR REPLACE FUNCTION _challenge_league_header(
    p_kind TEXT,
    p_challenge_id UUID
)
RETURNS TABLE (
    challenge_type TEXT,
    daily_target INTEGER,
    duration_days INTEGER,
    start_date DATE,
    end_date DATE,
    creator_timezone TEXT,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_kind IN ('1v1','group') THEN
        RETURN QUERY
        SELECT gc.challenge_type, gc.daily_target,
               COALESCE(gc.duration_days, GREATEST(1, (gc.end_date - gc.start_date)::INT))::INTEGER,
               gc.start_date::DATE, gc.end_date::DATE,
               COALESCE(gc.creator_timezone, 'UTC'), gc.status
          FROM group_challenges gc
         WHERE gc.id = p_challenge_id;
    ELSIF p_kind = 'private' THEN
        RETURN QUERY
        SELECT pc.challenge_type, pc.daily_target,
               COALESCE((pc.end_date - pc.start_date)::INT, 7)::INTEGER,
               pc.start_date::DATE, pc.end_date::DATE,
               'UTC'::TEXT, pc.status
          FROM private_challenges pc
         WHERE pc.id = p_challenge_id;
    ELSIF p_kind = 'community' THEN
        RETURN QUERY
        SELECT cc.challenge_type, cc.daily_target,
               COALESCE((cc.end_date - cc.start_date)::INT, 7)::INTEGER,
               cc.start_date::DATE, cc.end_date::DATE,
               'UTC'::TEXT, cc.status
          FROM community_challenges cc
         WHERE cc.id = p_challenge_id;
    ELSE
        RAISE EXCEPTION 'Unknown challenge_kind: %', p_kind;
    END IF;
END;
$$;

COMMENT ON FUNCTION _challenge_league_header(TEXT, UUID) IS
    'Internal helper for the Challenge League Points scoring RPCs — unifies the group/private/community challenge headers into a single RECORD shape.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. compute_challenge_daily_awards — the Daily Duel rollup
--
-- Per-challenge, per-day rollup. Computes scoring for every participant and
-- writes one ledger row per (user, award_kind), then calls add_league_points
-- once per user with the summed total so the Sprint 3 Peak Day multiplier
-- applies to the whole daily haul (not each row).
--
-- Scoring (plan §Layer 1):
--   • hit_target — base_hit when progress_value >= daily_target
--   • day_winner — 2x (1v1) or 1.5x (group/private top 10%) multiplier
--     on the base when user hit target AND has the daily leader value
--   • intensity — 1.25x (>=150%), 1.5x (>=200%), 2x (>=300%)
--   • early_bird — 1v1 only, +10 flat when user was first to hit target
--     (earliest updated_at where progress reached target)
--
-- Anti-exploit caps:
--   • Per-challenge daily max: 100 LP (before Peak Day)
--   • Cross-challenge daily max: 500 LP (checked against today's
--     challenge_league_awards.final_points sum before the add_league_points
--     call; excess is skipped, not clipped mid-row)
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

    -- Bail if the day is outside the challenge window. Avoids scoring the
    -- opening / closing ceremonies twice.
    IF p_day < v_header.start_date OR p_day > v_header.end_date THEN
        RETURN json_build_object('success', false, 'reason', 'day_outside_window',
                                  'day', p_day,
                                  'start_date', v_header.start_date,
                                  'end_date', v_header.end_date);
    END IF;

    -- Tier lookup (falls back to easy defaults if a new ChallengeType ships
    -- without a paired tiers row). `SELECT ... INTO` gives us a named-field
    -- RECORD so v_tier.base_hit access works even in the fallback branch.
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

    v_week_start := get_current_week_monday();

    -- Resolve the effective "kind" — 1v1 is a group_challenges row with exactly
    -- 2 accepted participants. Detecting this here lets callers pass either
    -- '1v1' or 'group' for a group_challenges row and still get the right
    -- multipliers.
    IF p_challenge_kind IN ('1v1','group') THEN
        SELECT CASE WHEN COUNT(*) = 2 THEN '1v1' ELSE 'group' END
          INTO v_effective_kind
          FROM challenge_participants
         WHERE challenge_id = p_challenge_id
           AND status = 'accepted';
    ELSE
        v_effective_kind := p_challenge_kind;
    END IF;

    -- Build the per-participant progress snapshot into a temp-style CTE.
    -- We materialize into a temp table (ON COMMIT DROP) so the subsequent
    -- passes (leader, early bird, writer loop) don't re-JOIN on the four
    -- daily_progress shapes.
    CREATE TEMP TABLE IF NOT EXISTS _cda_rows (
        user_id UUID,
        progress_value INTEGER,
        target_hit BOOLEAN,
        updated_at TIMESTAMPTZ
    ) ON COMMIT DROP;
    TRUNCATE _cda_rows;

    IF v_effective_kind IN ('1v1','group') THEN
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, updated_at)
        SELECT cdp.user_id, cdp.progress_value, cdp.target_hit, cdp.updated_at
          FROM challenge_daily_progress cdp
         WHERE cdp.challenge_id = p_challenge_id
           AND cdp.progress_date = p_day;
    ELSIF v_effective_kind = 'private' THEN
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, updated_at)
        SELECT pcdp.user_id, pcdp.progress_value, pcdp.target_hit, pcdp.updated_at
          FROM private_challenge_daily_progress pcdp
         WHERE pcdp.challenge_id = p_challenge_id
           AND pcdp.progress_date = p_day;
    ELSE
        INSERT INTO _cda_rows (user_id, progress_value, target_hit, updated_at)
        SELECT ccdp.user_id, ccdp.progress_value, ccdp.target_hit, ccdp.updated_at
          FROM community_challenge_daily_progress ccdp
         WHERE ccdp.challenge_id = p_challenge_id
           AND ccdp.progress_date = p_day;
    END IF;

    SELECT COUNT(*) INTO v_participant_count FROM _cda_rows;

    IF v_participant_count = 0 THEN
        RETURN json_build_object('success', true, 'awards_written', 0,
                                  'reason', 'no_progress_rows');
    END IF;

    -- Daily leader (highest progress_value, ties excluded from winner bonus).
    SELECT MAX(progress_value) INTO v_leader_value FROM _cda_rows WHERE target_hit;
    SELECT COUNT(*) INTO v_winner_count
      FROM _cda_rows
     WHERE target_hit AND progress_value = v_leader_value;

    -- Early bird (1v1 only): first user to hit target this day.
    IF v_effective_kind = '1v1' THEN
        SELECT user_id INTO v_early_bird_user
          FROM _cda_rows
         WHERE target_hit
         ORDER BY updated_at ASC NULLS LAST
         LIMIT 1;
    END IF;

    -- Walk every participant and score them.
    FOR v_participant IN
        SELECT user_id, progress_value, target_hit, updated_at FROM _cda_rows
    LOOP
        v_total_points := 0;

        -- Award 1: hit_target
        IF v_participant.target_hit THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_participant.user_id, v_effective_kind, p_challenge_id, p_day,
                'hit_target',
                v_tier.base_hit, 1.0, v_tier.base_hit, v_week_start,
                format('Hit %s daily target (%s)', v_tier.effort_tier, v_header.challenge_type)
            )
            ON CONFLICT DO NOTHING;
            IF FOUND THEN
                v_total_points := v_total_points + v_tier.base_hit;
                v_award_rows := v_award_rows + 1;
            END IF;
        END IF;

        -- Award 2: day_winner (sole leader only, ties fall through)
        IF v_participant.target_hit
           AND v_leader_value > 0
           AND v_participant.progress_value = v_leader_value
           AND v_winner_count = 1
        THEN
            DECLARE
                v_multiplier NUMERIC;
                v_extra INTEGER;
            BEGIN
                IF v_effective_kind = '1v1' THEN
                    v_multiplier := 2.0;  -- 2x on base_win
                ELSIF v_effective_kind IN ('group','private') THEN
                    v_multiplier := 1.5;
                ELSE
                    v_multiplier := 1.25;  -- community: smaller swing (many participants)
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

        -- Award 3: intensity (>=150/200/300% of target)
        IF v_participant.target_hit
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
                    v_intensity_multiplier := 1.0;  -- extra 100% of base_hit
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
           AND v_participant.target_hit
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
                'First to hit target'
            )
            ON CONFLICT DO NOTHING;
            IF FOUND THEN
                v_total_points := v_total_points + 10;
                v_award_rows := v_award_rows + 1;
            END IF;
        END IF;

        -- Clip to per-challenge daily cap.
        IF v_total_points > v_per_challenge_cap THEN
            v_total_points := v_per_challenge_cap;
        END IF;

        -- Cross-challenge daily cap (before Peak Day). Read existing
        -- challenge-domain awards for today and clip.
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

        -- Credit to the league balance. add_league_points enforces source
        -- caps + applies Peak Day tier multiplier.
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
        'day', p_day,
        'awards_written', v_award_rows,
        'participant_count', v_participant_count
    );
END;
$$;

COMMENT ON FUNCTION compute_challenge_daily_awards(TEXT, UUID, DATE) IS
    'Daily Duel rollup — computes hit/winner/intensity/early-bird League Point awards for a challenge on one day. Idempotent via challenge_league_awards UNIQUE. Calls add_league_points with summed per-user total so Peak Day tier multiplier composes on the whole daily haul. Service-role / pg_cron only.';

GRANT EXECUTE ON FUNCTION compute_challenge_daily_awards(TEXT, UUID, DATE) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. compute_challenge_final_bell — 1v1 / group / private end-of-challenge pot
--
-- Fires on status transition active -> completed. Pot size scales with
-- duration (plan §Layer 2: `pot = round(25 * sqrt(duration_days))`). Payout:
--   • 1v1: winner 100%, loser 0%. Tie -> both 50%.
--   • Group / Private: rank 1 = 100%, rank 2 = 60%, rank 3 = 40%, rank 4+ =
--     max(10%, their_total / winner_total * 100%).
--
-- Unbroken Chain: user hit target every single day of the challenge -> 1.5x
-- multiplier on the final_bell row.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS compute_challenge_final_bell(TEXT, UUID);

CREATE OR REPLACE FUNCTION compute_challenge_final_bell(
    p_challenge_kind TEXT,
    p_challenge_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_header RECORD;
    v_effective_kind TEXT;
    v_pot INTEGER;
    v_duration INTEGER;
    v_participant RECORD;
    v_winner_total INTEGER := 0;
    v_week_start DATE;
    v_award_rows INTEGER := 0;
    v_hit_days INTEGER;
    v_unbroken BOOLEAN;
    v_chain_multiplier NUMERIC;
    v_base INTEGER;
    v_share NUMERIC;
    v_final_points INTEGER;
    v_note TEXT;
BEGIN
    IF p_challenge_kind NOT IN ('1v1','group','private') THEN
        RAISE EXCEPTION 'Invalid kind for Final Bell: %', p_challenge_kind
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_header FROM _challenge_league_header(
        CASE WHEN p_challenge_kind = '1v1' THEN 'group' ELSE p_challenge_kind END,
        p_challenge_id
    );

    IF v_header.challenge_type IS NULL THEN
        RETURN json_build_object('success', false, 'reason', 'challenge_not_found');
    END IF;

    v_duration := GREATEST(1, v_header.duration_days);
    v_pot := GREATEST(1, ROUND(25.0 * SQRT(v_duration))::INTEGER);
    v_week_start := get_current_week_monday();

    -- Resolve kind (1v1 vs group) from participant count.
    IF p_challenge_kind IN ('1v1','group') THEN
        SELECT CASE WHEN COUNT(*) = 2 THEN '1v1' ELSE 'group' END
          INTO v_effective_kind
          FROM challenge_participants
         WHERE challenge_id = p_challenge_id
           AND status = 'accepted';
    ELSE
        v_effective_kind := 'private';
    END IF;

    -- Build ranked participant snapshot into a temp working set.
    CREATE TEMP TABLE IF NOT EXISTS _fb_rows (
        user_id UUID,
        total_progress INTEGER,
        final_rank INTEGER
    ) ON COMMIT DROP;
    TRUNCATE _fb_rows;

    IF v_effective_kind IN ('1v1','group') THEN
        INSERT INTO _fb_rows (user_id, total_progress, final_rank)
        SELECT cp.user_id, cp.total_progress,
               ROW_NUMBER() OVER (ORDER BY cp.total_progress DESC, cp.user_id ASC)
          FROM challenge_participants cp
         WHERE cp.challenge_id = p_challenge_id
           AND cp.status = 'accepted';
    ELSE
        INSERT INTO _fb_rows (user_id, total_progress, final_rank)
        SELECT pcm.user_id, pcm.total_progress,
               ROW_NUMBER() OVER (ORDER BY pcm.total_progress DESC, pcm.user_id ASC)
          FROM private_challenge_members pcm
         WHERE pcm.challenge_id = p_challenge_id
           AND pcm.is_active = TRUE;
    END IF;

    SELECT total_progress INTO v_winner_total FROM _fb_rows WHERE final_rank = 1;
    v_winner_total := COALESCE(v_winner_total, 0);

    IF (SELECT COUNT(*) FROM _fb_rows) = 0 THEN
        RETURN json_build_object('success', false, 'reason', 'no_participants');
    END IF;

    FOR v_participant IN
        SELECT user_id, total_progress, final_rank FROM _fb_rows ORDER BY final_rank ASC
    LOOP
        -- Unbroken Chain detection — count distinct days where this user
        -- hit target, compare to challenge duration.
        IF v_effective_kind IN ('1v1','group') THEN
            SELECT COUNT(DISTINCT progress_date) INTO v_hit_days
              FROM challenge_daily_progress
             WHERE challenge_id = p_challenge_id
               AND user_id = v_participant.user_id
               AND target_hit = TRUE
               AND progress_date BETWEEN v_header.start_date AND v_header.end_date;
        ELSE
            SELECT COUNT(DISTINCT progress_date) INTO v_hit_days
              FROM private_challenge_daily_progress
             WHERE challenge_id = p_challenge_id
               AND user_id = v_participant.user_id
               AND target_hit = TRUE
               AND progress_date BETWEEN v_header.start_date AND v_header.end_date;
        END IF;

        v_unbroken := (v_hit_days >= v_duration);
        v_chain_multiplier := CASE WHEN v_unbroken THEN 1.5 ELSE 1.0 END;

        -- Payout share by kind + rank.
        IF v_effective_kind = '1v1' THEN
            -- Tie = both 50%.
            IF (SELECT COUNT(*) FROM _fb_rows WHERE total_progress = v_winner_total) = 2 THEN
                v_share := 0.5;
                v_note := 'Tie — 50% pot';
            ELSIF v_participant.final_rank = 1 AND v_participant.total_progress > 0 THEN
                v_share := 1.0;
                v_note := 'Winner — full pot';
            ELSE
                v_share := 0.0;
                v_note := 'Lost';
            END IF;
        ELSE
            -- Group / private:
            IF v_participant.final_rank = 1 THEN
                v_share := 1.0;
                v_note := 'Rank 1 — full pot';
            ELSIF v_participant.final_rank = 2 THEN
                v_share := 0.6;
                v_note := 'Rank 2 — 60% pot';
            ELSIF v_participant.final_rank = 3 THEN
                v_share := 0.4;
                v_note := 'Rank 3 — 40% pot';
            ELSE
                IF v_winner_total > 0 AND v_participant.total_progress > 0 THEN
                    v_share := GREATEST(0.10, v_participant.total_progress::NUMERIC / v_winner_total::NUMERIC);
                    IF v_share > 1.0 THEN v_share := 1.0; END IF;
                ELSE
                    v_share := 0.10;
                END IF;
                v_note := format('Rank %s — %s%% pot', v_participant.final_rank, ROUND(v_share * 100));
            END IF;
        END IF;

        v_base := ROUND(v_pot * v_share)::INTEGER;
        v_final_points := ROUND(v_base * v_chain_multiplier)::INTEGER;

        IF v_final_points > 0 THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_participant.user_id, v_effective_kind, p_challenge_id, NULL,
                'final_bell',
                v_base, v_chain_multiplier, v_final_points, v_week_start,
                v_note || CASE WHEN v_unbroken THEN ' + Unbroken Chain 1.5x' ELSE '' END
            )
            ON CONFLICT DO NOTHING;

            IF FOUND THEN
                v_award_rows := v_award_rows + 1;
                PERFORM add_league_points(
                    v_participant.user_id,
                    v_final_points,
                    'challenge_final_bell',
                    p_challenge_id::TEXT
                );
            END IF;
        END IF;

        -- Also write a separate unbroken_chain row (legibility — the battle
        -- log header shows the "consistency" bullet even when the pot share
        -- is small). Zero-point row — accounting only.
        IF v_unbroken THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_participant.user_id, v_effective_kind, p_challenge_id,
                v_header.end_date, 'unbroken_chain',
                0, 1.0, 0, v_week_start,
                format('Hit target every single day (%s/%s)', v_hit_days, v_duration)
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'challenge_id', p_challenge_id,
        'kind', v_effective_kind,
        'pot', v_pot,
        'duration_days', v_duration,
        'awards_written', v_award_rows
    );
END;
$$;

COMMENT ON FUNCTION compute_challenge_final_bell(TEXT, UUID) IS
    'Final Bell — end-of-challenge League Points pot for 1v1/group/private. Duration-scaled (25 * sqrt(days)). 1v1 winner-take-all; group/private rank tiers + scaled participation. Unbroken Chain 1.5x multiplier. Idempotent. Service-role only.';

GRANT EXECUTE ON FUNCTION compute_challenge_final_bell(TEXT, UUID) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. compute_community_wave_final_bell — weekly community wave payout
--
-- Community challenges are typically recurring. A 7-day "wave" gives them
-- rhythm without forcing restart. Payouts by percentile rank of the wave's
-- total_progress (accumulated within [wave_end_date-6 .. wave_end_date]):
--   • Top 1%  -> 200% of pot
--   • Top 5%  -> 100%
--   • Top 10% -> 50%
--   • Top 25% -> 25%
--   • Top 50% -> 10%
--
-- Unbroken Chain: 1.25x (smaller than 1v1/group/private because the denominator
-- is bigger and the pot already scales with participant count via the pot
-- formula). 7-day default pot = round(25 * sqrt(7)) = 66 LP.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS compute_community_wave_final_bell(UUID, DATE);

CREATE OR REPLACE FUNCTION compute_community_wave_final_bell(
    p_challenge_id UUID,
    p_wave_end_date DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_header RECORD;
    v_pot INTEGER;
    v_wave_start DATE;
    v_wave_duration CONSTANT INTEGER := 7;
    v_participant_count INTEGER;
    v_week_start DATE;
    v_award_rows INTEGER := 0;
    v_p RECORD;
    v_share NUMERIC;
    v_pct NUMERIC;
    v_base INTEGER;
    v_final_points INTEGER;
    v_chain_multiplier NUMERIC;
    v_unbroken BOOLEAN;
    v_hit_days INTEGER;
    v_note TEXT;
BEGIN
    SELECT * INTO v_header FROM _challenge_league_header('community', p_challenge_id);
    IF v_header.challenge_type IS NULL THEN
        RETURN json_build_object('success', false, 'reason', 'challenge_not_found');
    END IF;

    v_wave_start := p_wave_end_date - (v_wave_duration - 1);
    v_pot := GREATEST(1, ROUND(25.0 * SQRT(v_wave_duration))::INTEGER);
    v_week_start := get_current_week_monday();

    -- Build snapshot of wave totals (only users with any progress in-window).
    CREATE TEMP TABLE IF NOT EXISTS _cwfb_rows (
        user_id UUID,
        wave_progress BIGINT,
        hit_days INTEGER,
        final_rank INTEGER,
        rank_pct NUMERIC
    ) ON COMMIT DROP;
    TRUNCATE _cwfb_rows;

    INSERT INTO _cwfb_rows (user_id, wave_progress, hit_days, final_rank, rank_pct)
    SELECT
        user_id,
        wave_progress,
        hit_days,
        ROW_NUMBER() OVER (ORDER BY wave_progress DESC, user_id ASC) AS final_rank,
        (ROW_NUMBER() OVER (ORDER BY wave_progress DESC, user_id ASC))::NUMERIC /
            NULLIF(COUNT(*) OVER (), 0)::NUMERIC AS rank_pct
      FROM (
          SELECT ccdp.user_id,
                 SUM(ccdp.progress_value)::BIGINT AS wave_progress,
                 COUNT(*) FILTER (WHERE ccdp.target_hit)::INTEGER AS hit_days
            FROM community_challenge_daily_progress ccdp
           WHERE ccdp.challenge_id = p_challenge_id
             AND ccdp.progress_date BETWEEN v_wave_start AND p_wave_end_date
           GROUP BY ccdp.user_id
           HAVING SUM(ccdp.progress_value) > 0
      ) agg;

    SELECT COUNT(*) INTO v_participant_count FROM _cwfb_rows;

    IF v_participant_count = 0 THEN
        RETURN json_build_object('success', true, 'awards_written', 0,
                                  'reason', 'no_wave_progress');
    END IF;

    FOR v_p IN
        SELECT user_id, wave_progress, hit_days, final_rank, rank_pct
          FROM _cwfb_rows ORDER BY final_rank ASC
    LOOP
        v_pct := v_p.rank_pct;

        IF v_pct <= 0.01 THEN
            v_share := 2.00;
            v_note := 'Top 1% — 200% pot';
        ELSIF v_pct <= 0.05 THEN
            v_share := 1.00;
            v_note := 'Top 5% — full pot';
        ELSIF v_pct <= 0.10 THEN
            v_share := 0.50;
            v_note := 'Top 10% — 50% pot';
        ELSIF v_pct <= 0.25 THEN
            v_share := 0.25;
            v_note := 'Top 25% — 25% pot';
        ELSIF v_pct <= 0.50 THEN
            v_share := 0.10;
            v_note := 'Top 50% — 10% pot';
        ELSE
            v_share := 0;
            v_note := 'Below top 50% — participation only';
        END IF;

        IF v_share = 0 THEN CONTINUE; END IF;

        v_unbroken := (v_p.hit_days >= v_wave_duration);
        v_chain_multiplier := CASE WHEN v_unbroken THEN 1.25 ELSE 1.0 END;

        v_base := ROUND(v_pot * v_share)::INTEGER;
        v_final_points := ROUND(v_base * v_chain_multiplier)::INTEGER;

        IF v_final_points > 0 THEN
            INSERT INTO challenge_league_awards (
                user_id, challenge_kind, challenge_id, challenge_day, award_kind,
                base_points, multiplier_applied, final_points, week_start, note
            ) VALUES (
                v_p.user_id, 'community', p_challenge_id,
                p_wave_end_date, 'wave_final_bell',
                v_base, v_chain_multiplier, v_final_points, v_week_start,
                v_note || CASE WHEN v_unbroken THEN ' + Unbroken Chain 1.25x' ELSE '' END
            )
            ON CONFLICT DO NOTHING;

            IF FOUND THEN
                v_award_rows := v_award_rows + 1;
                PERFORM add_league_points(
                    v_p.user_id,
                    v_final_points,
                    'challenge_final_bell',
                    p_challenge_id::TEXT || ':wave:' || p_wave_end_date::TEXT
                );
            END IF;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'challenge_id', p_challenge_id,
        'wave_end_date', p_wave_end_date,
        'pot', v_pot,
        'participant_count', v_participant_count,
        'awards_written', v_award_rows
    );
END;
$$;

COMMENT ON FUNCTION compute_community_wave_final_bell(UUID, DATE) IS
    'Community wave Final Bell — percentile payout for one 7-day community challenge wave (Sunday 23:59 UTC). Pot = round(25*sqrt(7)) = 66 LP. Unbroken Chain 1.25x. Idempotent via challenge_league_awards UNIQUE. Service-role only.';

GRANT EXECUTE ON FUNCTION compute_community_wave_final_bell(UUID, DATE) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. run_challenge_daily_rollup_hourly — cron entrypoint
--
-- Runs every hour. Detects per-challenge "yesterday in creator_timezone just
-- ended" via:
--   (NOW() AT TIME ZONE gc.creator_timezone)::DATE > (previous roll DATE)
-- In practice: for every active 1v1/group/private/community challenge, we
-- compute `yesterday_in_tz` and call compute_challenge_daily_awards for that
-- date. The ledger UNIQUE constraint makes this safe to re-run — if awards
-- already exist for (user, challenge, day, kind) the INSERT ... ON CONFLICT
-- DO NOTHING skips silently.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS run_challenge_daily_rollup_hourly();

CREATE OR REPLACE FUNCTION run_challenge_daily_rollup_hourly()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_chal RECORD;
    v_yesterday DATE;
    v_invocations INTEGER := 0;
BEGIN
    -- Active group / 1v1 challenges
    FOR v_chal IN
        SELECT id, COALESCE(creator_timezone, 'UTC') AS tz,
               start_date, end_date
          FROM group_challenges
         WHERE status = 'active'
    LOOP
        v_yesterday := ((NOW() AT TIME ZONE v_chal.tz)::DATE) - INTERVAL '1 day';
        IF v_yesterday >= v_chal.start_date AND v_yesterday <= v_chal.end_date THEN
            PERFORM compute_challenge_daily_awards('group', v_chal.id, v_yesterday::DATE);
            v_invocations := v_invocations + 1;
        END IF;
    END LOOP;

    -- Active private challenges (UTC — no creator_timezone column).
    FOR v_chal IN
        SELECT id, start_date, end_date FROM private_challenges
         WHERE status = 'active'
    LOOP
        v_yesterday := (CURRENT_DATE - INTERVAL '1 day');
        IF v_yesterday >= v_chal.start_date
           AND (v_chal.end_date IS NULL OR v_yesterday <= v_chal.end_date) THEN
            PERFORM compute_challenge_daily_awards('private', v_chal.id, v_yesterday::DATE);
            v_invocations := v_invocations + 1;
        END IF;
    END LOOP;

    -- Active community challenges (UTC — no creator_timezone column).
    FOR v_chal IN
        SELECT id, start_date, end_date FROM community_challenges
         WHERE status = 'active'
    LOOP
        v_yesterday := (CURRENT_DATE - INTERVAL '1 day');
        IF v_yesterday >= v_chal.start_date
           AND (v_chal.end_date IS NULL OR v_yesterday <= v_chal.end_date) THEN
            PERFORM compute_challenge_daily_awards('community', v_chal.id, v_yesterday::DATE);
            v_invocations := v_invocations + 1;
        END IF;
    END LOOP;

    RETURN json_build_object('success', true, 'invocations', v_invocations);
END;
$$;

COMMENT ON FUNCTION run_challenge_daily_rollup_hourly() IS
    'pg_cron entrypoint for Daily Duel rollup. Runs every hour, detects per-challenge timezone midnight, and invokes compute_challenge_daily_awards for yesterday. Idempotent via ledger UNIQUE.';

GRANT EXECUTE ON FUNCTION run_challenge_daily_rollup_hourly() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. run_community_wave_final_bell_weekly — Sunday 23:59 UTC cron
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS run_community_wave_final_bell_weekly();

CREATE OR REPLACE FUNCTION run_community_wave_final_bell_weekly()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_chal RECORD;
    v_wave_end DATE;
    v_invocations INTEGER := 0;
BEGIN
    v_wave_end := CURRENT_DATE;  -- Sunday when cron fires at 23:59 UTC

    FOR v_chal IN
        SELECT id FROM community_challenges WHERE status = 'active'
    LOOP
        PERFORM compute_community_wave_final_bell(v_chal.id, v_wave_end);
        v_invocations := v_invocations + 1;
    END LOOP;

    RETURN json_build_object('success', true,
                              'wave_end_date', v_wave_end,
                              'invocations', v_invocations);
END;
$$;

COMMENT ON FUNCTION run_community_wave_final_bell_weekly() IS
    'pg_cron entrypoint for the weekly community wave Final Bell. Fires Sunday 23:59 UTC.';

GRANT EXECUTE ON FUNCTION run_community_wave_final_bell_weekly() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. auto_complete_expired_challenges — extended to fire Final Bell
--
-- Replaces the existing body so that when a 1v1/group challenge transitions
-- from active -> completed we synchronously fire compute_challenge_final_bell.
-- Private challenges have their own `end_private_challenge` path (see below).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION auto_complete_expired_challenges()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_chal RECORD;
    v_fb_result JSON;
BEGIN
    FOR v_chal IN
        SELECT id, title
          FROM group_challenges
         WHERE status = 'active'
           AND end_date::DATE < CURRENT_DATE
    LOOP
        -- Fire Final Bell FIRST so the award rows exist before status flips.
        -- Roll up yesterday one more time to catch the last active day
        -- (challenges with a same-day end_date won't otherwise roll up).
        PERFORM compute_challenge_daily_awards(
            'group', v_chal.id, (CURRENT_DATE - INTERVAL '1 day')::DATE
        );

        SELECT compute_challenge_final_bell('group', v_chal.id) INTO v_fb_result;

        UPDATE group_challenges SET status = 'completed' WHERE id = v_chal.id;

        RAISE NOTICE '🏆 Challenge "%" completed. Final Bell: %', v_chal.title, v_fb_result;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION auto_complete_expired_challenges() IS
    'Sweeps expired active 1v1/group challenges -> completed. As of 20260430c: fires a last-day rollup + compute_challenge_final_bell synchronously before status flip.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. end_private_challenge — hook Final Bell into admin-end flow
--
-- Replaces the existing body. Additions:
--   • Last-day rollup before status flip.
--   • compute_challenge_final_bell('private', …).
-- Preserves: admin-only auth, system chat message, pending-invite expiration.
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS end_private_challenge(TEXT);

CREATE OR REPLACE FUNCTION end_private_challenge(
    p_challenge_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_role TEXT;
    v_challenge_uuid UUID;
    v_fb_result JSON;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_uuid := p_challenge_id::UUID;

    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_uuid
      AND user_id = current_user_uuid
      AND is_active = TRUE;

    IF v_role IS NULL OR v_role <> 'admin' THEN
        RAISE EXCEPTION 'Only admins can end this challenge';
    END IF;

    -- Final Bell BEFORE flipping status, so the scoring function sees the
    -- participant roster and daily progress while they are still active.
    BEGIN
        PERFORM compute_challenge_daily_awards(
            'private', v_challenge_uuid, (CURRENT_DATE - INTERVAL '1 day')::DATE
        );
    EXCEPTION WHEN OTHERS THEN
        -- Non-fatal — let end_private_challenge proceed even if yesterday's
        -- rollup fails (e.g. no progress rows).
        RAISE NOTICE 'end_private_challenge: daily rollup error: %', SQLERRM;
    END;

    BEGIN
        SELECT compute_challenge_final_bell('private', v_challenge_uuid) INTO v_fb_result;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'end_private_challenge: final_bell error: %', SQLERRM;
    END;

    UPDATE private_challenges
       SET status = 'ended',
           end_date = CURRENT_DATE,
           updated_at = NOW()
     WHERE id = v_challenge_uuid;

    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (v_challenge_uuid, current_user_uuid, 'system',
            'This challenge has ended. Great job everyone! 🏆');

    UPDATE private_challenge_invites
       SET status = 'expired'
     WHERE challenge_id = v_challenge_uuid
       AND status = 'pending';

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION end_private_challenge(TEXT) IS
    'Admin-only end of a private challenge. As of 20260430c: fires compute_challenge_daily_awards for yesterday + compute_challenge_final_bell BEFORE flipping status to ended. Non-fatal on scoring errors (log + continue).';

GRANT EXECUTE ON FUNCTION end_private_challenge(TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Reader RPCs — battle log + leaderboard breakdown
--
-- These are client-facing reads. Both IDOR-guarded (own-user only) for
-- privacy parity with the league_point_awards ledger.
-- ─────────────────────────────────────────────────────────────────────────────

-- 9a. get_challenge_league_awards — per-day / final-bell awards for a
-- challenge, for the caller. Used by ChallengeDetailView battle log to
-- render the per-day LP chip.
DROP FUNCTION IF EXISTS get_challenge_league_awards(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_league_awards(
    p_challenge_id TEXT
)
RETURNS TABLE (
    challenge_day DATE,
    award_kind TEXT,
    base_points INTEGER,
    multiplier_applied NUMERIC,
    final_points INTEGER,
    note TEXT,
    awarded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_cid UUID;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    v_cid := p_challenge_id::UUID;

    RETURN QUERY
    SELECT cla.challenge_day,
           cla.award_kind,
           cla.base_points,
           cla.multiplier_applied,
           cla.final_points,
           cla.note,
           cla.awarded_at
      FROM challenge_league_awards cla
     WHERE cla.user_id = v_uid
       AND cla.challenge_id = v_cid
     ORDER BY cla.challenge_day ASC NULLS LAST, cla.awarded_at ASC;
END;
$$;

COMMENT ON FUNCTION get_challenge_league_awards(TEXT) IS
    'Returns the calling user''s challenge_league_awards rows for one challenge, ordered by day then awarded_at. Drives the BattleLogRow LP chip.';

GRANT EXECUTE ON FUNCTION get_challenge_league_awards(TEXT) TO authenticated;

-- 9b. get_league_member_breakdown — per-source weekly LP breakdown for a
-- user's current week. Drives the leaderboard tap-to-expand panel.
-- Own-user only — respects league_point_awards RLS posture.
DROP FUNCTION IF EXISTS get_league_member_breakdown(DATE);
DROP FUNCTION IF EXISTS get_league_member_breakdown(UUID, DATE);

CREATE OR REPLACE FUNCTION get_league_member_breakdown(
    p_week_start DATE DEFAULT NULL
)
RETURNS TABLE (
    source TEXT,
    award_count INTEGER,
    total_points INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_week DATE;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    v_week := COALESCE(p_week_start, get_current_week_monday());

    RETURN QUERY
    SELECT lpa.source,
           COUNT(*)::INTEGER AS award_count,
           COALESCE(SUM(lpa.awarded_points), 0)::INTEGER AS total_points
      FROM league_point_awards lpa
     WHERE lpa.user_id = v_uid
       AND lpa.week_start = v_week
     GROUP BY lpa.source
     ORDER BY total_points DESC;
END;
$$;

COMMENT ON FUNCTION get_league_member_breakdown(DATE) IS
    'Returns the calling user''s per-source LP totals for one week. Drives the WeeklyLeagueViews tap-to-expand breakdown panel.';

GRANT EXECUTE ON FUNCTION get_league_member_breakdown(DATE) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Extend get_challenge_details with daily_league_awards
--
-- Re-defines the 16-column RPC (unchanged signature) and appends one new
-- JSONB column `daily_league_awards` so the iOS battle log can render the
-- LP chip without a second round-trip. Only the caller's own awards are
-- returned (RLS applies at the source table, and we filter by auth.uid()
-- inside the subselect as defense in depth).
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_challenge_details(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_details(
    p_challenge_id TEXT
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    status TEXT,
    created_at TIMESTAMPTZ,
    notify_on_opponent_complete BOOLEAN,
    participants JSONB,
    daily_league_awards JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    RETURN QUERY
    SELECT
        gc.id,
        gc.challenge_type,
        gc.title,
        gc.description,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        gc.status,
        gc.created_at,
        my_cp.notify_on_opponent_complete,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', cp2.user_id,
                'name', up2.name,
                'username', up2.username,
                'photo_url', up2.profile_photo_url,
                'status', cp2.status,
                'total_progress', COALESCE(cp2.total_progress, 0),
                'days_completed', COALESCE(cp2.days_completed, 0),
                'current_streak', COALESCE(cp2.current_streak, 0),
                'best_streak', COALESCE(cp2.best_streak, 0),
                'is_creator', (cp2.user_id = gc.created_by),
                'daily_progress', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'date', cdp.progress_date::TEXT,
                        'value', cdp.progress_value,
                        'source', cdp.source
                    ) ORDER BY cdp.progress_date)
                    FROM challenge_daily_progress cdp
                    WHERE cdp.challenge_id = gc.id AND cdp.user_id = cp2.user_id
                )
            ))
            FROM challenge_participants cp2
            JOIN user_profiles up2 ON up2.id = cp2.user_id
            WHERE cp2.challenge_id = gc.id
        ) AS participants,
        -- Caller's daily LP awards (for BattleLogRow).
        COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'day', cla.challenge_day::TEXT,
                'award_kind', cla.award_kind,
                'base_points', cla.base_points,
                'multiplier', cla.multiplier_applied,
                'points', cla.final_points,
                'note', cla.note
            ) ORDER BY cla.challenge_day ASC NULLS LAST, cla.awarded_at ASC)
              FROM challenge_league_awards cla
             WHERE cla.challenge_id = gc.id
               AND cla.user_id = current_user_uuid
        ), '[]'::jsonb) AS daily_league_awards
    FROM group_challenges gc
    JOIN challenge_participants my_cp
      ON my_cp.challenge_id = gc.id
     AND my_cp.user_id = current_user_uuid
    WHERE gc.id = challenge_uuid;
END;
$$;

COMMENT ON FUNCTION get_challenge_details(TEXT) IS
    'Challenge details for 1v1/group. As of 20260430c: new `daily_league_awards` JSONB column returns the caller''s per-day + final-bell LP award rows so BattleLogRow can render the LP chip without a round-trip. All pre-existing columns preserved.';

GRANT EXECUTE ON FUNCTION get_challenge_details(TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. pg_cron scheduling
--
-- Idempotent schedule — `cron.unschedule` by name first to avoid duplicates
-- if this migration re-runs.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_job_id INTEGER;
BEGIN
    -- Hourly daily rollup. Top of every hour UTC.
    SELECT jobid INTO v_job_id FROM cron.job
     WHERE jobname = 'challenge_daily_rollup_hourly';
    IF v_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(v_job_id);
    END IF;
    PERFORM cron.schedule(
        'challenge_daily_rollup_hourly',
        '0 * * * *',
        $cron$ SELECT public.run_challenge_daily_rollup_hourly(); $cron$
    );

    -- Weekly community wave Final Bell. Sunday 23:59 UTC.
    SELECT jobid INTO v_job_id FROM cron.job
     WHERE jobname = 'community_wave_final_bell_weekly';
    IF v_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(v_job_id);
    END IF;
    PERFORM cron.schedule(
        'community_wave_final_bell_weekly',
        '59 23 * * 0',
        $cron$ SELECT public.run_community_wave_final_bell_weekly(); $cron$
    );

EXCEPTION WHEN undefined_table OR undefined_function OR invalid_schema_name THEN
    -- `cron` extension may not be enabled in local / test environments.
    -- Skip scheduling in that case — migration still deploys the functions
    -- themselves so manual invocation works.
    RAISE NOTICE 'pg_cron not available — skipping schedule. Run cron.schedule() manually after enabling.';
END $$;

COMMIT;

-- =============================================================================
-- Verification (manual after deploy):
--
-- -- Sanity of the new helper:
-- SELECT * FROM _challenge_league_header('group', '<some-group-challenge-id>');
--
-- -- Dry-run the daily rollup for one challenge:
-- SELECT compute_challenge_daily_awards('group', '<id>', CURRENT_DATE - 1);
--
-- -- Confirm cron jobs are scheduled:
-- SELECT jobname, schedule FROM cron.job
--  WHERE jobname IN ('challenge_daily_rollup_hourly',
--                    'community_wave_final_bell_weekly');
--
-- -- Confirm ledger + tier seeds:
-- SELECT count(*) FROM challenge_award_tiers;   -- expect 12
-- SELECT count(*) FROM league_point_source_caps WHERE source LIKE 'challenge_%';  -- 2
-- =============================================================================

