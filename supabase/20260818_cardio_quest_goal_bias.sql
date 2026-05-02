-- ============================================================================
-- Migration: cardio_goal_bias_score helper + onboarding-goal cardio biasing
-- Date: 2026-05-02 (Cardio Redesign Phase 1 — Wave 2c)
-- Agent: Supabase / Data & Backend / Fitness Expert
--
-- WHY:
--   The user's onboarding picks one of four canonical fitness goals
--   (`buildMuscle` / `loseFat` / `endurance` / `generalFitness` — Swift
--   `GoalFamily` enum in DailyBriefEngine.swift). Today the daily-quest
--   slate (`get_daily_quests` v4 from 20260703) treats every cardio
--   template the same regardless of the user's stated goal. That means a
--   "Get Lean" user gets the same probability of seeing
--   `active_recovery_logged` as an "Endurance" user, and a "Build Muscle"
--   user can be assigned a 5K time-trial on a hypertrophy-deload day.
--
--   This migration ships the **biasing primitive** that the next
--   `get_daily_quests` v5 will consume:
--     `public.cardio_goal_bias_score(p_quest_key TEXT, p_fitness_goal TEXT)`
--   It returns an INT in the range [-50, +30] that the slot-selection CASE
--   in v5 will ADD to the existing `selection_score` term, gently steering
--   the cardio pool toward goal-aligned quests without ever zeroing out
--   the pool. (Negative scores demote; positive scores promote; zero is
--   neutral.) The function is IMMUTABLE / STABLE so it can be inlined in
--   ORDER BY without a per-row planning hit.
--
-- BIAS MAP (per Fitness Expert §3 + DailyBriefEngine.GoalFamily):
--
--   ─── Cardio quest keys (from 20260531 + 20260604 + 20260610 + 20260611) ──
--     walk_1km, cardio_minutes_20, zone_2_minutes_20         (low-intensity)
--     run_outside_3km, run_outside_5km, run_outside_8km      (volume-aerobic)
--     beat_your_5k_pr, negative_split_run                    (intensity)
--     complete_strava_segment, cycle_outside_15km/30km       (volume-aerobic)
--     match_yesterday_strain                                 (recovery-aware)
--     active_recovery_logged, walk_when_red, evening_wind_down (recovery)
--
--   ─── Bias by goal family ─────────────────────────────────────────────────
--     loseFat            buildMuscle        endurance         generalFitness
--     walk_1km          +25  -10            +30 (Z2 base)     +15            0
--     cardio_minutes_20 +20    0            +25                +10           0
--     zone_2_minutes_20 +25  +5             +30                +10           0
--     run_outside_3km   +15  -20            +20                +5            0
--     run_outside_5km   +15  -25            +30                +5            0
--     run_outside_8km    +5  -40            +30 (anchor)        0            0
--     beat_your_5k_pr     0  -30            +25                 0            0
--     negative_split_run  0  -25            +25                 0            0
--     complete_strava_seg 0  -20            +15                 0            0
--     cycle_outside_15km +10 -15            +20                +5            0
--     cycle_outside_30km  0  -30            +25                 0            0
--     active_recovery     0  +30 (rest)      +5               +10            0
--     walk_when_red       0  +25             +5                +5            0
--     evening_wind_down   0  +25             +5                +5            0
--     match_yesterday_str 0    0            +15                 0            0
--
--   Rationale:
--     • loseFat → bias UP toward Z2 + walks + 5K (calorie burn, low
--       interference with strength). Avoid demoting any quest beyond -10.
--     • buildMuscle → bias DOWN on volume runs (interference effect on
--       hypertrophy) and bias UP on recovery-coded quests (active
--       recovery on rest days is goal-aligned).
--     • endurance → bias UP across the board on volume + intensity;
--       8K + 5K-PR + negative-split are anchors.
--     • generalFitness → no bias (zero).
--
-- INVARIANTS RESPECTED:
--   • Supabase 12: drops every prior overload via pg_proc loop before
--     CREATE.
--   • Supabase 17: BEGIN/COMMIT, idempotent, re-runnable with no side
--     effect.
--   • Supabase 28: post-migration audit confirms exactly 1 surviving
--     definition of `cardio_goal_bias_score`.
--   • PE 19d: Function does NOT make any quest impossible to complete
--     (no quest is filtered out — only re-ordered). The slate-diversity
--     guard in `get_daily_quests` v5 caps any single category at 1 slot
--     so even an `endurance` user can't end up with 3 cardio slots.
--   • Fitness Expert §3.4: `match_yesterday_strain` only meaningful for
--     `endurance` (others lack the WHOOP context anyway — gated upstream
--     by `requires_context = 'has_whoop'`).
--   • Fitness 19: passive sensor quests retired in 20260610/20260611
--     (`recovery_above_67` etc.) are NOT in the bias map — calling
--     `cardio_goal_bias_score` with their key returns 0.
--
-- WHAT THIS MIGRATION DOES NOT DO:
--   It does NOT modify `get_daily_quests` v4 — that's a separate Wave 2c
--   follow-up (`20260819_get_daily_quests_v5_goal_bias.sql`) which adds a
--   `+ cardio_goal_bias_score(qt.quest_key, p_fitness_goal)` term to the
--   existing `selection_score` CASE in the eligibility-pool sweep. The
--   v5 patch is purely additive on the score (no signature change, no
--   response-shape change), so iOS clients see no breaking change.
--
--   This split exists so the helper function can ship + be unit-tested
--   in isolation BEFORE the larger v5 rewrite is reviewed.
--
-- ROLLBACK:
--   `DROP FUNCTION IF EXISTS public.cardio_goal_bias_score(TEXT, TEXT);`
-- ============================================================================

BEGIN;

-- ── Drop every prior overload (Supabase invariant 12) ───────────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'cardio_goal_bias_score'
    ) LOOP
        EXECUTE format(
            'DROP FUNCTION IF EXISTS %I.%I(%s)',
            r.nspname, r.proname, r.args
        );
    END LOOP;
END$$;

-- ── Goal-bias score helper ──────────────────────────────────────────────────
CREATE FUNCTION public.cardio_goal_bias_score(
    p_quest_key    TEXT,
    p_fitness_goal TEXT
)
RETURNS INT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
    -- Normalize the onboarding goal. iOS persists strings like
    -- "Lose Fat", "Build Muscle", "Improve Endurance", "General Fitness"
    -- (raw values from `ProgramGoal` / `FitnessGoal` enums). DailyBrief's
    -- `GoalFamily.init(rawGoal:)` does case-insensitive substring match;
    -- we mirror the same logic here so the contract is identical.
    WITH bucket AS (
        SELECT
            CASE
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%muscle%'   THEN 'buildMuscle'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%bulk%'     THEN 'buildMuscle'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%strong%'   THEN 'buildMuscle'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%lean%'     THEN 'loseFat'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%lose%'     THEN 'loseFat'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%fat%'      THEN 'loseFat'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%cut%'      THEN 'loseFat'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%tone%'     THEN 'loseFat'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%endurance%' THEN 'endurance'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%cardio%'   THEN 'endurance'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%marathon%' THEN 'endurance'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%5k%'       THEN 'endurance'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%10k%'      THEN 'endurance'
                WHEN lower(coalesce(p_fitness_goal, '')) LIKE '%run%'      THEN 'endurance'
                ELSE 'generalFitness'
            END AS family
    )
    SELECT CASE
        -- ─── loseFat ────────────────────────────────────────────────────
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'walk_1km'           THEN 25
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'cardio_minutes_20'  THEN 20
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'zone_2_minutes_20'  THEN 25
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'run_outside_3km'    THEN 15
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'run_outside_5km'    THEN 15
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'run_outside_8km'    THEN  5
        WHEN bucket.family = 'loseFat' AND p_quest_key = 'cycle_outside_15km' THEN 10

        -- ─── buildMuscle ────────────────────────────────────────────────
        -- Active recovery + walks bias UP (rest-day quests). Volume-run
        -- quests bias DOWN (interference effect with hypertrophy).
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'active_recovery_logged' THEN  30
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'walk_when_red'          THEN  25
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'evening_wind_down'      THEN  25
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'walk_1km'               THEN -10
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'zone_2_minutes_20'      THEN   5
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'run_outside_3km'        THEN -20
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'run_outside_5km'        THEN -25
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'run_outside_8km'        THEN -40
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'beat_your_5k_pr'        THEN -30
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'negative_split_run'     THEN -25
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'complete_strava_segment' THEN -20
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'cycle_outside_15km'     THEN -15
        WHEN bucket.family = 'buildMuscle' AND p_quest_key = 'cycle_outside_30km'     THEN -30

        -- ─── endurance ──────────────────────────────────────────────────
        -- Bias UP across the board on volume + intensity. 8K + 5K-PR are
        -- the anchors (signature endurance quests). Recovery quests stay
        -- mildly positive (every endurance program has rest days).
        WHEN bucket.family = 'endurance' AND p_quest_key = 'walk_1km'             THEN 30
        WHEN bucket.family = 'endurance' AND p_quest_key = 'cardio_minutes_20'    THEN 25
        WHEN bucket.family = 'endurance' AND p_quest_key = 'zone_2_minutes_20'    THEN 30
        WHEN bucket.family = 'endurance' AND p_quest_key = 'run_outside_3km'      THEN 20
        WHEN bucket.family = 'endurance' AND p_quest_key = 'run_outside_5km'      THEN 30
        WHEN bucket.family = 'endurance' AND p_quest_key = 'run_outside_8km'      THEN 30
        WHEN bucket.family = 'endurance' AND p_quest_key = 'beat_your_5k_pr'      THEN 25
        WHEN bucket.family = 'endurance' AND p_quest_key = 'negative_split_run'   THEN 25
        WHEN bucket.family = 'endurance' AND p_quest_key = 'complete_strava_segment' THEN 15
        WHEN bucket.family = 'endurance' AND p_quest_key = 'cycle_outside_15km'   THEN 20
        WHEN bucket.family = 'endurance' AND p_quest_key = 'cycle_outside_30km'   THEN 25
        WHEN bucket.family = 'endurance' AND p_quest_key = 'match_yesterday_strain' THEN 15
        WHEN bucket.family = 'endurance' AND p_quest_key = 'active_recovery_logged' THEN 5
        WHEN bucket.family = 'endurance' AND p_quest_key = 'walk_when_red'        THEN  5
        WHEN bucket.family = 'endurance' AND p_quest_key = 'evening_wind_down'    THEN  5

        -- ─── generalFitness ────────────────────────────────────────────
        -- Modest universal bonus on the lowest-friction cardio so brand
        -- new users see a walk on day 1.
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'walk_1km'             THEN 15
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'cardio_minutes_20'    THEN 10
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'zone_2_minutes_20'    THEN 10
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'run_outside_3km'      THEN  5
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'run_outside_5km'      THEN  5
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'cycle_outside_15km'   THEN  5
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'active_recovery_logged' THEN 10
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'walk_when_red'        THEN  5
        WHEN bucket.family = 'generalFitness' AND p_quest_key = 'evening_wind_down'    THEN  5

        ELSE 0
    END
    FROM bucket;
$$;

COMMENT ON FUNCTION public.cardio_goal_bias_score(TEXT, TEXT) IS
'Returns an INT bias score in [-50, +30] for a (quest_key, fitness_goal) pair. Consumed by `get_daily_quests` v5 ORDER BY clause to gently steer the cardio quest pool toward the user''s onboarding goal (loseFat / buildMuscle / endurance / generalFitness). Zero for neutral, never filters out a quest. See migration 20260818 docstring for the full bias table + rationale.';

GRANT EXECUTE ON FUNCTION public.cardio_goal_bias_score(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cardio_goal_bias_score(TEXT, TEXT) TO service_role;

-- ── Audit: confirm exactly one definition (Supabase invariant 28) ──────────
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'cardio_goal_bias_score';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'cardio_goal_bias_score has % definitions (expected 1) — overload-loop drop failed', v_count;
    END IF;
END$$;

COMMIT;
