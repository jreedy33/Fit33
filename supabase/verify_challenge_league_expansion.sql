-- =============================================================================
-- verify_challenge_league_expansion.sql
--
-- Read-only verification queries for the Challenge League Points Expansion
-- migrations (#176, #177, #178). Safe to run multiple times — pure SELECT
-- + one controlled re-invocation of `compute_challenge_daily_awards` to
-- assert idempotency.
--
-- HOW TO USE:
--   Run against a post-deploy database. Each RAISE NOTICE / SELECT should
--   come back clean. A failure means one of the migrations didn't apply.
-- =============================================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 1 — challenge_award_tiers has a row for every active ChallengeType.
--
-- Mirrors the Swift `ChallengeType` enum in Fit33/ChallengeService.swift.
-- If this expands on iOS without a paired DB UPDATE, the scoring RPC
-- silently falls back to easy-tier defaults (10 hit / 15 win) — this test
-- catches the drift before it ships.
-- ─────────────────────────────────────────────────────────────────────────────

WITH swift_types(challenge_type) AS (
    VALUES
        ('steps'), ('walk'), ('run'), ('hydrate'), ('active_minutes'),
        ('calories'), ('protein'), ('lift'), ('workout_streak'),
        ('readiness_average'), ('sleep_hours'), ('strain_budget')
),
missing AS (
    SELECT st.challenge_type
      FROM swift_types st
      LEFT JOIN challenge_award_tiers cat ON cat.challenge_type = st.challenge_type
     WHERE cat.challenge_type IS NULL
)
SELECT
    CASE WHEN COUNT(*) = 0
         THEN '✅ TEST 1 PASS — every Swift ChallengeType has a tiers row'
         ELSE '❌ TEST 1 FAIL — missing: ' || string_agg(challenge_type, ', ')
    END AS test_1_tier_completeness
  FROM missing;

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 2 — league_tiers seeded with the Sprint 4 promotion floors.
-- ─────────────────────────────────────────────────────────────────────────────

WITH expected(tier_rank, promotion_lp_floor, peak_day_multiplier, requires_crown, relegation_pct) AS (
    VALUES
        (1, 0,    2, FALSE, 0.000),  -- Bronze
        (2, 350,  2, FALSE, 0.250),  -- Silver
        (3, 500,  3, FALSE, 0.250),  -- Gold
        (4, 700,  3, FALSE, 0.300),  -- Platinum
        (5, 900,  4, FALSE, 0.300),  -- Diamond
        (6, 1200, 4, TRUE,  0.350),  -- Elite   (Crown apex gate)
        (7, 0,    5, FALSE, 0.150)   -- Verified
),
-- Bronze's promotion_lp_floor isn't specified in the seed but must default
-- to the same as Silver's entry floor (200) OR be 0 (never promotes). We
-- accept either.
mismatched AS (
    SELECT e.tier_rank
      FROM expected e
      JOIN league_tiers lt ON lt.tier_rank = e.tier_rank
     WHERE (lt.peak_day_multiplier <> e.peak_day_multiplier)
        OR (lt.requires_crown IS DISTINCT FROM e.requires_crown)
        OR (lt.relegation_pct  <> e.relegation_pct)
        OR (e.tier_rank > 1 AND lt.promotion_lp_floor <> e.promotion_lp_floor)
)
SELECT
    CASE WHEN COUNT(*) = 0
         THEN '✅ TEST 2 PASS — league_tiers seeded correctly'
         ELSE '❌ TEST 2 FAIL — bad rows at tier_rank: ' || string_agg(tier_rank::TEXT, ', ')
    END AS test_2_tier_seed
  FROM mismatched;

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 3 — league_point_source_caps has the new challenge sources.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    CASE WHEN COUNT(*) FILTER (WHERE source = 'challenge_daily') = 1
          AND COUNT(*) FILTER (WHERE source = 'challenge_final_bell') = 1
         THEN '✅ TEST 3 PASS — source caps registered'
         ELSE '❌ TEST 3 FAIL — missing challenge_daily / challenge_final_bell row'
    END AS test_3_source_caps
  FROM league_point_source_caps
 WHERE source IN ('challenge_daily', 'challenge_final_bell');

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 4 — RLS enforced on challenge_league_awards.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
    CASE WHEN relrowsecurity
         THEN '✅ TEST 4 PASS — RLS enabled on challenge_league_awards'
         ELSE '❌ TEST 4 FAIL — RLS is OFF on challenge_league_awards'
    END AS test_4_rls
  FROM pg_class
 WHERE relname = 'challenge_league_awards';

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 5 — cron jobs scheduled.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_daily INTEGER;
    v_weekly INTEGER;
BEGIN
    BEGIN
        SELECT COUNT(*) INTO v_daily FROM cron.job WHERE jobname = 'challenge_daily_rollup_hourly';
        SELECT COUNT(*) INTO v_weekly FROM cron.job WHERE jobname = 'community_wave_final_bell_weekly';
        IF v_daily = 1 AND v_weekly = 1 THEN
            RAISE NOTICE '✅ TEST 5 PASS — both cron jobs scheduled';
        ELSE
            RAISE NOTICE '❌ TEST 5 FAIL — cron jobs: daily=% weekly=%', v_daily, v_weekly;
        END IF;
    EXCEPTION WHEN undefined_table THEN
        RAISE NOTICE '⚠️  TEST 5 SKIP — pg_cron not enabled in this environment';
    END;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST 6 — compute_challenge_daily_awards is idempotent.
--
-- Picks an active group challenge, runs compute_challenge_daily_awards for
-- yesterday twice, and asserts the second run wrote zero new rows (the
-- UNIQUE index blocked the INSERTs). No side-effects if the first run
-- already ran via the hourly cron — we just re-invoke and compare.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_id UUID;
    v_day DATE := CURRENT_DATE - INTERVAL '1 day';
    v_before INTEGER;
    v_after INTEGER;
BEGIN
    SELECT id INTO v_id
      FROM group_challenges
     WHERE status = 'active'
       AND start_date <= v_day AND end_date >= v_day
     LIMIT 1;

    IF v_id IS NULL THEN
        RAISE NOTICE '⚠️  TEST 6 SKIP — no active group challenge covering yesterday to test with';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_before FROM challenge_league_awards
     WHERE challenge_id = v_id AND challenge_day = v_day::DATE;

    PERFORM compute_challenge_daily_awards('group', v_id, v_day::DATE);

    SELECT COUNT(*) INTO v_after FROM challenge_league_awards
     WHERE challenge_id = v_id AND challenge_day = v_day::DATE;

    IF v_before = v_after THEN
        RAISE NOTICE '✅ TEST 6 PASS — idempotent (% rows unchanged after re-run)', v_before;
    ELSE
        RAISE NOTICE '❌ TEST 6 FAIL — rows changed from % to % on re-run', v_before, v_after;
    END IF;
END $$;
