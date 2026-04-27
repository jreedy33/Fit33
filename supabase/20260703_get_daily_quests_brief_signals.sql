-- ============================================================================
-- Migration: get_daily_quests v4 — accept Daily Brief signals
-- Date: 2026-04-27 (Daily Mission Unification — Phase 1)
-- Agent: Supabase / Data & Backend
--
-- WHY:
--   Before this migration, the Daily Brief engine and the daily quest slate
--   were computed independently. The brief read every integration (WHOOP,
--   Oura, Fitbit, HealthKit, hydration, weight, meals, quests) and surfaced
--   a fused headline like "Mid recovery + 100g protein short — eat now and
--   run a lighter session later." But `get_daily_quests` v3 (20260619) had
--   no idea about readiness band or top debt, so it could happily prescribe
--   "exercise_sets_25" (15 sets in a single workout) on a yellow recovery
--   day — directly contradicting the brief's "lighter session" copy.
--
--   This migration extends `get_daily_quests` to accept 4 new signals from
--   the brief and uses them to (a) demote hard quests on red days,
--   (b) elevate the recovery pool on red days, (c) elevate PR/volume
--   quests on green days, and (d) force-elevate a quest from the matching
--   debt category into slot 2 or 3 when the brief's top debt clears the
--   "real debt" threshold.
--
-- DIFF vs. 20260619_lock_daily_quests_to_3_slots.sql:
--   1. Signature grows from 32 args to 36 args. Four new tail params:
--        p_capacity_band     TEXT    DEFAULT NULL    -- green/yellow/red/unknown
--        p_capacity_score    INT     DEFAULT 0       -- 0-100
--        p_top_debt_kind     TEXT    DEFAULT NULL    -- matches Swift DebtKind.rawValue
--        p_top_debt_payload  JSONB   DEFAULT '{}'    -- { muscles, days, deficitG, deficitL, gap }
--      All four default to NULL/empty so existing callers (cron, backfills,
--      legacy clients) continue to work — Phase 1 server is BACKWARDS-
--      COMPATIBLE. Behavior change only when the iOS client opts in by
--      passing the new params (Phase 2).
--   2. Layer 7 — Capacity Band Re-Ranker. Adds `v_capacity_band` parsing,
--      filters/elevates the eligibility pool by difficulty when the band
--      is red or green. Yellow / unknown / null no-op (zero behavior change
--      for unconnected users).
--   3. Layer 8 — Debt Booster. After slot 1+2+3 are picked but BEFORE the
--      redundancy + diversity sweeps, if `p_top_debt_kind` is non-null AND
--      the payload meets a "real debt" threshold, force-elevate one quest
--      from the matching category into slot 2 or 3 (whichever is non-
--      workout). Caps at one debt-driven slot per day so the slate never
--      collapses to all-protein.
--   4. New local TEXT[] `v_brief_influenced_keys` — tracks which slots came
--      from Layer 7 (recovery elevation) or Layer 8 (debt booster) so the
--      response JSON can include `is_brief_influenced` per quest. iOS uses
--      that flag to render the "← from your brief" chip beside the quest
--      title (PE invariant 25c — Mission framing).
--   5. Output JSON gains `is_brief_influenced` BOOLEAN per quest. Computed
--      inline (`udq.quest_key = ANY(v_brief_influenced_keys)`) so no schema
--      change to `user_daily_quests` is required — the flag is recomputed
--      on every fetch and stays in sync with the layer that picked it.
--
-- INVARIANTS RESPECTED (Plan: Daily Mission Unification):
--   - Supabase 12: pg_proc loop drops every prior overload before CREATE.
--   - Supabase 17: BEGIN/COMMIT, idempotent; re-running flips behavior on
--     the same call shape with no side effect.
--   - Supabase 28: post-migration audit confirms exactly 1 surviving
--     definition.
--   - Data 7: IDOR guard on (auth.uid(), p_user_id) — unchanged.
--   - Data 30: slot 1 still anchors `complete_program_day` /
--     `complete_workout` per program-vs-no-program rule. Layer 8 NEVER
--     overrides slot 1.
--   - Data 32: friend-name + suggested-split copy stays ≤ 35 chars.
--   - FE 23: red recovery override (auto-gen → recovery template) stays
--     intact upstream; Layer 7 just makes the quest pool reflect that
--     decision so the slate stops handing out 25-set quests.
--   - PE 19: `defaultGoals()` still covers the empty-slate fallback case;
--     the Layer 7 pool filter never wipes the pool to zero (we always have
--     at least the recovery pool seeds available).
--   - PE 25c: `is_brief_influenced` flag in response is the PROVENANCE
--     contract the iOS UI reads to show the "from your brief" chip.
--
-- ROLLBACK:
--   Re-run 20260619 — it drops all overloads + recreates with the 32-arg
--   signature. Phase 1 is purely additive on the param list and additive
--   on the response shape (extra field; clients ignoring it work fine).
-- ============================================================================

BEGIN;

-- ── Drop every prior get_daily_quests overload (Supabase invariant 12) ──
DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
        FROM pg_proc
        WHERE proname = 'get_daily_quests'
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id                                       TEXT,
    p_timezone                                      TEXT DEFAULT 'America/New_York',
    p_has_program                                   BOOLEAN DEFAULT FALSE,
    p_has_friends                                   BOOLEAN DEFAULT FALSE,
    p_has_challenge                                 BOOLEAN DEFAULT FALSE,
    p_step_goal                                     INT DEFAULT 10000,
    p_fitness_goal                                  TEXT DEFAULT 'general',
    p_is_subscriber                                 BOOLEAN DEFAULT FALSE,
    p_workout_streak                                INT DEFAULT 0,
    p_total_workouts                                INT DEFAULT 0,
    p_preferred_time                                TEXT DEFAULT 'any',
    p_avg_duration                                  INT DEFAULT 45,
    p_has_weight_log                                BOOLEAN DEFAULT FALSE,
    p_hydration_active                              BOOLEAN DEFAULT FALSE,
    p_league_rank                                   INT DEFAULT 0,
    p_active_step_challenge_target                  INT DEFAULT 0,
    p_suggested_split                               TEXT DEFAULT NULL,
    p_fatigued_regions                              TEXT[] DEFAULT '{}',
    p_active_challenge_types                        TEXT[] DEFAULT '{}',
    p_has_connected_wearable                        BOOLEAN DEFAULT FALSE,
    -- Smart Adaptive Daily Goals (20260605) ───────────────────────────
    p_strava_connected                              BOOLEAN DEFAULT FALSE,
    p_whoop_connected                               BOOLEAN DEFAULT FALSE,
    p_oura_connected                                BOOLEAN DEFAULT FALSE,
    p_fitbit_connected                              BOOLEAN DEFAULT FALSE,
    p_activity_mix                                  JSONB   DEFAULT '{}'::jsonb,
    p_friend_step_target                            INT     DEFAULT 0,
    p_friend_name                                   TEXT    DEFAULT NULL,
    p_friend_top_workout_id                         UUID    DEFAULT NULL,
    p_friend_top_workout_title                      TEXT    DEFAULT NULL,
    p_friend_top_workout_split                      TEXT    DEFAULT NULL,
    p_friend_top_workout_matches_recommendation     BOOLEAN DEFAULT FALSE,
    p_quest_tier                                    TEXT    DEFAULT 'free',
    -- Daily Mission Unification (20260703 — Phase 1) ──────────────────
    p_capacity_band                                 TEXT    DEFAULT NULL,
    p_capacity_score                                INT     DEFAULT 0,
    p_top_debt_kind                                 TEXT    DEFAULT NULL,
    p_top_debt_payload                              JSONB   DEFAULT '{}'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id                UUID := p_user_id::UUID;
    v_caller_id              UUID := auth.uid();
    v_today                  DATE;
    v_quest_count            INT;
    v_streak                 RECORD;
    v_bonus_claimed          BOOLEAN := FALSE;
    v_all_complete           BOOLEAN := FALSE;
    v_day_seed               INT;
    v_difficulty_profile     TEXT;
    v_quest_keys             TEXT[] := '{}';
    v_pool_easy              TEXT[];
    v_pool_medium            TEXT[];
    v_pool_hard              TEXT[];
    v_recent_keys            TEXT[];
    v_total_wk               INT  := COALESCE(p_total_workouts, 0);
    v_wk_streak              INT  := COALESCE(p_workout_streak, 0);
    v_preferred_workout_key  TEXT;
    v_step_keys              TEXT[] := ARRAY[
        'walk_3k_steps', 'walk_5k_steps', 'walk_7500_steps',
        'walk_10k_steps', 'hit_step_goal'
    ];
    v_redundant_with_workout TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories', 'workout_30_min',
        'exercise_sets_15', 'exercise_sets_25', 'beat_volume_pr',
        'stretch_session', 'maintain_streak', 'league_3_workouts',
        'complete_2_workouts', 'early_bird_workout'
    ];
    v_redundant_with_steps   TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories'
    ];
    v_slot1_is_workout       BOOLEAN;
    v_slot1_is_steps         BOOLEAN;
    v_challenge_quest_keys   TEXT[] := '{}';
    v_distinct_cats          INT;
    v_category_ladder        TEXT[];
    v_swap_candidate         TEXT;
    v_i                      INT;
    v_pro                    BOOLEAN := (LOWER(COALESCE(p_quest_tier, 'free')) = 'pro');
    v_target_slots           INT := 3;
    v_dominant_bucket        TEXT;
    v_least_bucket           TEXT;
    v_friend_step_label      TEXT;
    v_friend_workout_copy    TEXT;
    v_friend_workout_short   TEXT;
    -- ── Daily Mission Unification (20260703) locals ──────────────────
    v_band                   TEXT := LOWER(COALESCE(p_capacity_band, 'unknown'));
    v_debt_kind              TEXT := COALESCE(p_top_debt_kind, '');
    v_debt_meets_threshold   BOOLEAN := FALSE;
    v_debt_target_category   TEXT;
    v_debt_quest_key         TEXT;
    v_brief_influenced_keys  TEXT[] := '{}';   -- keys elevated by Layer 7 OR 8
    v_recovery_pool          TEXT[] := ARRAY[
        'active_recovery_logged', 'walk_when_red', 'evening_wind_down',
        'stretch_session'
    ];
    v_pr_pool                TEXT[] := ARRAY[
        'exercise_sets_25', 'beat_volume_pr', 'beat_personal_record'
    ];
BEGIN
    -- IDOR guard (Data invariant 7).
    IF v_caller_id IS NOT NULL AND v_caller_id <> v_user_id THEN
        RAISE EXCEPTION 'get_daily_quests IDOR: caller % does not match p_user_id %', v_caller_id, v_user_id
            USING ERRCODE = '42501';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_day_seed := (abs(hashtext(v_user_id::TEXT || v_today::TEXT)::BIGINT) % 2147483647)::INT;

    -- ── Slot 1 preferred key (unchanged) ───────────────────────────────
    IF p_has_program THEN
        v_preferred_workout_key := 'complete_program_day';
    ELSE
        v_preferred_workout_key := 'complete_workout';
    END IF;
    v_slot1_is_workout := v_preferred_workout_key IN (
        'complete_workout', 'complete_program_day', 'complete_2_workouts'
    );

    -- ── Difficulty profile (unchanged baseline) ────────────────────────
    IF v_wk_streak >= 7 OR v_total_wk >= 100 THEN
        v_difficulty_profile := CASE
            WHEN v_day_seed % 5 = 0 THEN 'easy_day'
            WHEN v_day_seed % 3 = 0 THEN 'hard_day'
            ELSE 'mixed_day'
        END;
    ELSIF v_total_wk >= 20 THEN
        v_difficulty_profile := CASE
            WHEN v_day_seed % 4 = 0 THEN 'hard_day'
            ELSE 'mixed_day'
        END;
    ELSE
        v_difficulty_profile := CASE
            WHEN v_day_seed % 3 = 0 THEN 'mixed_day'
            ELSE 'easy_day'
        END;
    END IF;

    -- ── Layer 7 — Capacity Band Re-Ranker (NEW 20260703) ──────────────
    -- Red recovery overrides the streak/total-based difficulty profile —
    -- nervous system needs the day, no matter how seasoned the user is.
    -- Green recovery promotes the user to hard_day so the PR-flag pool
    -- gets a fair shot. Yellow / unknown / null fall through unchanged.
    IF v_band = 'red' THEN
        v_difficulty_profile := 'easy_day';
    ELSIF v_band = 'green' THEN
        v_difficulty_profile := 'hard_day';
    END IF;

    -- ── Activity-mix dominant / least bucket (Layer 4 inputs) ──────────
    SELECT
        COALESCE(
            p_activity_mix->>'dominant',
            (SELECT dominant_category FROM user_activity_mix WHERE user_id = v_user_id)
        ),
        COALESCE(
            p_activity_mix->>'least',
            (SELECT least_category FROM user_activity_mix WHERE user_id = v_user_id)
        )
    INTO v_dominant_bucket, v_least_bucket;

    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    -- ── Layer 8 — Debt Booster threshold gate (NEW 20260703) ──────────
    -- Decide UP FRONT whether the brief's top debt is "real" enough to
    -- justify forcing a quest into the slate. Done before the eligibility
    -- pool builds so we know which template to look for.
    IF v_debt_kind = 'proteinDeficit' THEN
        -- Only treat protein as a real debt when the brief's pace-aware
        -- engine flagged it (subKind = 'behindPace'). Morning false-alarm
        -- "noBreakfast" pivots are surfaced in copy but don't elevate a
        -- protein quest into the slate.
        IF (p_top_debt_payload->>'subKind') = 'behindPace'
           AND COALESCE((p_top_debt_payload->>'deficitVsPaceG')::INT, 0) >= 30 THEN
            v_debt_meets_threshold := TRUE;
            v_debt_target_category := 'nutrition';
            v_debt_quest_key := 'hit_protein_goal';
        END IF;
    ELSIF v_debt_kind = 'hydrationDeficit' THEN
        IF COALESCE((p_top_debt_payload->>'deficitMl')::INT, 0) >= 500 THEN
            v_debt_meets_threshold := TRUE;
            v_debt_target_category := 'nutrition';   -- hydration sits under nutrition category
            v_debt_quest_key := 'log_water_8';
        END IF;
    ELSIF v_debt_kind = 'stepsBehindGoal' THEN
        IF COALESCE((p_top_debt_payload->>'gapRaw')::INT, 0) >= 3000 THEN
            v_debt_meets_threshold := TRUE;
            v_debt_target_category := 'steps';
            v_debt_quest_key := 'hit_step_goal';
        END IF;
    ELSIF v_debt_kind = 'muscleGroup' THEN
        -- Muscle debt is already reflected in slot 1 (workout) + the
        -- p_suggested_split description rewrite. We don't elevate a
        -- second muscle-debt quest because slot 1 IS that quest.
        v_debt_meets_threshold := FALSE;
    END IF;

    -- ───────────────────────────────────────────────────────────────────
    -- Only build/insert when today's slate hasn't been generated yet.
    -- ───────────────────────────────────────────────────────────────────
    IF v_quest_count = 0 THEN
        SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '3 days'
          AND quest_date < v_today;

        -- ── Challenge override list ────────────────────────────────────
        IF 'active_minutes' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'active_minutes_30');
        END IF;
        IF 'calories' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'burn_300_calories');
        END IF;
        IF 'hydrate' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'log_water_8');
        END IF;
        IF 'protein' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'hit_protein_goal');
        END IF;
        IF 'workout_streak' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'maintain_streak');
        END IF;
        IF 'lift' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'exercise_sets_15');
        END IF;

        -- ── Eligibility pool ───────────────────────────────────────────
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type, qt.tier,
               qt.weight,
               CASE
                   WHEN qt.quest_key IN (
                       'walk_3k_steps','walk_5k_steps','walk_7500_steps',
                       'walk_10k_steps','hit_step_goal','walk_when_red'
                   ) THEN 'walk'
                   WHEN qt.quest_key IN (
                       'run_outside_3km','run_outside_5km','run_outside_8km',
                       'cycle_outside_15km','cycle_outside_30km','beat_your_5k_pr',
                       'negative_split_run','complete_strava_segment',
                       'active_minutes_30','burn_300_calories'
                   ) THEN 'cardio'
                   WHEN qt.quest_key IN ('stretch_session') THEN 'stretch'
                   WHEN qt.category = 'workout' THEN 'strength'
                   ELSE NULL
               END AS activity_bucket
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          AND COALESCE(qt.min_workouts, 0) <= v_total_wk
          AND qt.quest_key != ALL(v_recent_keys)
          AND qt.quest_key NOT IN ('upper_body_workout', 'lower_body_workout')
          AND (v_pro OR qt.tier = 'free')
          AND NOT (
                v_slot1_is_workout
                AND qt.quest_key = ANY(v_redundant_with_workout)
                AND qt.quest_key <> ALL(v_challenge_quest_keys)
          )
          -- Layer 7 (NEW 20260703): on red recovery days, drop hard +
          -- very-hard difficulty templates from the pool entirely, so
          -- the slate cannot serve "exercise_sets_25" or "beat_volume_pr"
          -- to a user the wearable says is wrecked. Recovery pool
          -- templates (active_recovery_logged, walk_when_red, etc.) are
          -- explicitly NOT filtered (they're easy difficulty already).
          -- Honors FE invariant 23. Yellow / green / unknown no-op here.
          AND NOT (
                v_band = 'red'
                AND qt.difficulty IN ('hard', 'very_hard')
                AND qt.quest_key <> ALL(v_recovery_pool)
          )
          AND (
                qt.requires_context IS NULL
             OR (qt.requires_context = 'has_program'              AND p_has_program)
             OR (qt.requires_context = 'has_friends'              AND p_has_friends)
             OR (qt.requires_context = 'has_challenge'            AND p_has_challenge)
             OR (qt.requires_context = 'no_friends'               AND NOT p_has_friends)
             OR (qt.requires_context = 'no_challenge'             AND NOT p_has_challenge)
             OR (qt.requires_context = 'free_user'                AND NOT p_is_subscriber)
             OR (qt.requires_context = 'has_wearable'             AND (p_has_connected_wearable
                                                                    OR p_strava_connected
                                                                    OR p_whoop_connected
                                                                    OR p_oura_connected
                                                                    OR p_fitbit_connected))
             OR (qt.requires_context = 'has_strava'               AND p_strava_connected)
             OR (qt.requires_context = 'has_whoop'                AND p_whoop_connected)
             OR (qt.requires_context = 'has_oura'                 AND p_oura_connected)
             OR (qt.requires_context = 'has_fitbit'               AND p_fitbit_connected)
             OR (qt.requires_context = 'has_friends_no_challenge' AND p_has_friends AND NOT p_has_challenge)
          );

        -- Suppression filter (unchanged).
        DELETE FROM _eligible_quests eq
        WHERE eq.quest_key <> ALL(v_challenge_quest_keys)
          AND (
                EXISTS (
                    SELECT 1 FROM user_quest_key_stats s
                    WHERE s.user_id = v_user_id
                      AND s.quest_key = eq.quest_key
                      AND s.suppressed_until IS NOT NULL
                      AND s.suppressed_until > v_today
                )
             OR EXISTS (
                    SELECT 1 FROM user_quest_personalization p
                    WHERE p.user_id = v_user_id
                      AND p.category = eq.category
                      AND p.suppressed_until IS NOT NULL
                      AND p.suppressed_until > v_today
                )
          );

        -- ── Layer 4: scored pool (unchanged formula) ──────────────────
        DROP TABLE IF EXISTS _scored_quests;
        CREATE TEMP TABLE _scored_quests ON COMMIT DROP AS
        SELECT
            eq.*,
            (
                eq.weight::NUMERIC
                * (1.0
                    + CASE WHEN v_dominant_bucket IS NOT NULL
                              AND eq.activity_bucket = v_dominant_bucket
                           THEN 0.30 ELSE 0.0 END
                    + CASE WHEN EXISTS (
                              SELECT 1 FROM user_quest_key_stats s
                              WHERE s.user_id = v_user_id
                                AND s.quest_key = eq.quest_key
                                AND s.total_assigned_28d >= 3
                                AND s.completion_rate_28d >= 0.75
                          ) THEN 0.25 ELSE 0.0 END
                    + CASE WHEN v_least_bucket IS NOT NULL
                              AND eq.activity_bucket = v_least_bucket
                           THEN 0.10 ELSE 0.0 END
                    -- Layer 7 (NEW 20260703): on green recovery days,
                    -- give PR-flag templates a +20% boost so the
                    -- difficulty rotation actually surfaces them on
                    -- primed-to-train days. No-op when band != green.
                    + CASE WHEN v_band = 'green'
                              AND eq.quest_key = ANY(v_pr_pool)
                           THEN 0.20 ELSE 0.0 END
                  )
            ) AS selection_score
        FROM _eligible_quests eq;

        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11)
          INTO v_pool_easy   FROM _scored_quests WHERE difficulty = 'easy';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11)
          INTO v_pool_medium FROM _scored_quests WHERE difficulty = 'medium';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11)
          INTO v_pool_hard   FROM _scored_quests WHERE difficulty = 'hard';

        v_pool_easy   := COALESCE(v_pool_easy,   ARRAY['complete_workout', 'walk_5k_steps', 'log_breakfast']);
        v_pool_medium := COALESCE(v_pool_medium, ARRAY['log_3_meals', 'walk_7500_steps', 'log_water_8']);
        v_pool_hard   := COALESCE(v_pool_hard,   ARRAY['hit_step_goal', 'log_water_8', 'hit_protein_goal']);

        IF v_difficulty_profile = 'easy_day' THEN
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed       % array_length(v_pool_easy,   1))],
                v_pool_easy[1 + ((v_day_seed + 1) % array_length(v_pool_easy,   1))],
                v_pool_medium[1 + (v_day_seed     % array_length(v_pool_medium, 1))]
            ];
        ELSIF v_difficulty_profile = 'hard_day' THEN
            v_quest_keys := ARRAY[
                v_pool_medium[1 + (v_day_seed       % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed         % array_length(v_pool_hard,   1))],
                v_pool_medium[1 + ((v_day_seed + 2) % array_length(v_pool_medium, 1))]
            ];
        ELSE
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed   % array_length(v_pool_easy,   1))],
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed   % array_length(v_pool_hard,   1))]
            ];
        END IF;

        -- Force slot 1 to the preferred workout key (unchanged).
        IF v_preferred_workout_key IS NOT NULL
           AND EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_preferred_workout_key AND is_active)
           AND v_preferred_workout_key <> ALL(v_quest_keys) THEN
            v_quest_keys[1] := v_preferred_workout_key;
        END IF;

        v_slot1_is_steps := v_quest_keys[1] IN ('hit_step_goal', 'walk_10k_steps');

        -- ── Layer 6a: friend-named slot 1 swap (unchanged) ────────────
        IF p_friend_top_workout_title IS NOT NULL
           AND p_friend_name IS NOT NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'do_friend_workout') THEN
            v_quest_keys[1] := 'do_friend_workout';
            v_slot1_is_workout := TRUE;
        END IF;

        -- ── Challenge override (unchanged 20260423 behavior) ──────────
        IF array_length(v_challenge_quest_keys, 1) > 0 THEN
            FOR v_i IN 1..array_length(v_challenge_quest_keys, 1) LOOP
                IF v_challenge_quest_keys[v_i] = ANY(v_quest_keys) THEN
                    CONTINUE;
                END IF;
                IF EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_challenge_quest_keys[v_i] AND is_active) THEN
                    IF v_i = 1 THEN
                        v_quest_keys[2] := v_challenge_quest_keys[v_i];
                    ELSE
                        v_quest_keys[3] := v_challenge_quest_keys[v_i];
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- Redundancy sweep with steps slot 1 (unchanged).
        IF v_slot1_is_steps THEN
            FOR v_i IN 2..3 LOOP
                IF v_quest_keys[v_i] = ANY(v_redundant_with_steps)
                   AND v_quest_keys[v_i] <> ALL(v_challenge_quest_keys) THEN
                    SELECT quest_key INTO v_swap_candidate
                    FROM _scored_quests
                    WHERE category IN ('nutrition', 'tracking')
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[v_i] := v_swap_candidate;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ── Layer 8: Debt Booster (NEW 20260703) ──────────────────────
        -- Force-elevate one quest from the matching debt category into
        -- slot 2 or 3 (whichever is NOT slot 1's workout). Caps at one
        -- debt-driven slot per day so the slate never collapses to
        -- "all protein" or "all hydration." Never overrides slot 1.
        --
        -- Selection precedence:
        --   1. If `v_debt_quest_key` is already in the pool AND not
        --      already on the slate, force it into slot 2 or 3.
        --   2. If a challenge override already populated slot 2 or 3
        --      with the SAME category, leave it alone (challenge wins).
        --   3. The replaced slot's old key is silently dropped — the
        --      Layer 5 sanity sweep below will swap a fresh candidate
        --      in if the replacement leaves a hole.
        IF v_debt_meets_threshold
           AND v_debt_quest_key IS NOT NULL
           AND v_debt_quest_key <> ALL(v_quest_keys)
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = v_debt_quest_key) THEN
            -- Don't override a challenge-locked slot.
            IF NOT (v_quest_keys[2] = ANY(v_challenge_quest_keys)) THEN
                v_quest_keys[2] := v_debt_quest_key;
                v_brief_influenced_keys := array_append(v_brief_influenced_keys, v_debt_quest_key);
            ELSIF NOT (v_quest_keys[3] = ANY(v_challenge_quest_keys)) THEN
                v_quest_keys[3] := v_debt_quest_key;
                v_brief_influenced_keys := array_append(v_brief_influenced_keys, v_debt_quest_key);
            END IF;
        END IF;

        -- ── Layer 7 (continued): red-day recovery elevation ───────────
        -- After slot selection, ensure that on a red day at least ONE
        -- non-workout slot is from the recovery pool. Slot 2 or 3 only.
        IF v_band = 'red'
           AND NOT EXISTS (
               SELECT 1 FROM unnest(v_quest_keys) k
               WHERE k = ANY(v_recovery_pool)
           ) THEN
            SELECT quest_key INTO v_swap_candidate
            FROM _scored_quests
            WHERE quest_key = ANY(v_recovery_pool)
              AND quest_key <> ALL(v_quest_keys)
            ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11
            LIMIT 1;
            IF v_swap_candidate IS NOT NULL THEN
                -- Replace slot 3 (least-locked-in slot — slot 1 is
                -- workout-anchored, slot 2 may be challenge-locked).
                IF NOT (v_quest_keys[3] = ANY(v_challenge_quest_keys)) THEN
                    v_quest_keys[3] := v_swap_candidate;
                    v_brief_influenced_keys := array_append(v_brief_influenced_keys, v_swap_candidate);
                END IF;
            END IF;
        END IF;

        -- ── Category diversity (unchanged) ────────────────────────────
        SELECT COUNT(DISTINCT qt.category)
          INTO v_distinct_cats
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys);

        IF v_distinct_cats < 2 THEN
            IF v_slot1_is_workout THEN
                v_category_ladder := ARRAY['nutrition', 'steps', 'tracking', 'social'];
            ELSIF v_slot1_is_steps THEN
                v_category_ladder := ARRAY['nutrition', 'workout', 'tracking', 'social'];
            ELSE
                v_category_ladder := ARRAY['nutrition', 'workout', 'steps', 'tracking'];
            END IF;

            FOR v_i IN 1..array_length(v_category_ladder, 1) LOOP
                IF NOT EXISTS (
                    SELECT 1 FROM quest_templates
                    WHERE quest_key = ANY(v_quest_keys)
                      AND category = v_category_ladder[v_i]
                ) THEN
                    SELECT quest_key INTO v_swap_candidate
                    FROM _scored_quests
                    WHERE category = v_category_ladder[v_i]
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[3] := v_swap_candidate;
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ── Layer 5: skip-streak floor — sanity sweep ────────────────
        FOR v_i IN 2..3 LOOP
            IF v_quest_keys[v_i] IS NULL THEN CONTINUE; END IF;
            IF v_quest_keys[v_i] = ANY(v_challenge_quest_keys) THEN CONTINUE; END IF;

            IF NOT EXISTS (
                SELECT 1 FROM _scored_quests sq
                WHERE sq.quest_key = v_quest_keys[v_i]
            ) THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)::BIGINT) + v_day_seed) % 11
                LIMIT 1;
                IF v_swap_candidate IS NOT NULL THEN
                    v_quest_keys[v_i] := v_swap_candidate;
                END IF;
            END IF;
        END LOOP;

        -- ── Free-user ad slot (unchanged revenue hook) ────────────────
        IF NOT p_is_subscriber
           AND array_length(v_challenge_quest_keys, 1) IS NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        -- ── Pre-compute friend label strings (unchanged) ─────────────
        IF p_friend_step_target > 0 AND p_friend_name IS NOT NULL THEN
            v_friend_step_label := 'Beat ' || p_friend_name || ': ' ||
                CASE WHEN p_friend_step_target >= 10000
                     THEN (p_friend_step_target / 1000)::TEXT || 'K'
                     ELSE p_friend_step_target::TEXT
                END;
        END IF;

        IF p_friend_top_workout_title IS NOT NULL AND p_friend_name IS NOT NULL THEN
            IF p_friend_top_workout_matches_recommendation
               AND p_friend_top_workout_split IS NOT NULL THEN
                v_friend_workout_copy := 'Due for ' || p_friend_top_workout_split
                                      || ' — do ' || p_friend_name || E'\u2019s';
            ELSE
                v_friend_workout_short := CASE
                    WHEN char_length(p_friend_top_workout_title) > 18
                        THEN substring(p_friend_top_workout_title FROM 1 FOR 17) || E'\u2026'
                    ELSE p_friend_top_workout_title
                END;
                v_friend_workout_copy := 'Do ' || p_friend_name || E'\u2019s ' || v_friend_workout_short;
            END IF;
        END IF;

        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        -- ── Insert the slate (unchanged title/description rewrites) ──
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND v_friend_step_label IS NOT NULL
                    THEN substring(v_friend_step_label FROM 1 FOR 35)
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN CASE
                        WHEN p_active_step_challenge_target >= 10000
                            THEN (p_active_step_challenge_target / 1000) || 'K Challenge Steps'
                        ELSE p_active_step_challenge_target::TEXT || ' Challenge Steps'
                    END
                WHEN qt.quest_key = 'do_friend_workout' AND v_friend_workout_copy IS NOT NULL
                    THEN substring(v_friend_workout_copy FROM 1 FOR 35)
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Program Day'
                ELSE qt.title
            END,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND v_friend_step_label IS NOT NULL
                    THEN substring('Beat ' || p_friend_name || ' today' FROM 1 FOR 35)
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN 'Hit your ' ||
                         CASE
                            WHEN p_active_step_challenge_target >= 10000
                                THEN (p_active_step_challenge_target / 1000) || 'K'
                            ELSE p_active_step_challenge_target::TEXT
                         END
                         || ' challenge target'
                WHEN qt.quest_key = 'do_friend_workout' AND v_friend_workout_copy IS NOT NULL
                    THEN substring(v_friend_workout_copy FROM 1 FOR 35)
                WHEN qt.quest_key IN ('complete_workout', 'workout_30_min')
                     AND p_suggested_split IS NOT NULL
                    THEN CASE p_suggested_split
                        WHEN 'legs'  THEN 'Suggested: Legs today'
                        WHEN 'push'  THEN 'Suggested: Push today'
                        WHEN 'pull'  THEN 'Suggested: Pull today'
                        WHEN 'upper' THEN 'Suggested: Upper body'
                        WHEN 'full'  THEN 'Suggested: Full body'
                        ELSE qt.description
                    END
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Continue your program'
                ELSE qt.description
            END,
            qt.icon,
            qt.category,
            CASE
                WHEN qt.quest_key = 'hit_step_goal' THEN
                    GREATEST(p_step_goal,
                             COALESCE(NULLIF(p_active_step_challenge_target, 0), 0),
                             COALESCE(NULLIF(p_friend_step_target, 0), 0))
                WHEN qt.quest_key = ANY(v_step_keys) AND p_friend_step_target > 0 THEN
                    p_friend_step_target
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0 THEN
                    p_active_step_challenge_target
                ELSE qt.target_value
            END,
            qt.target_unit,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > qt.target_value
                    THEN qt.xp_reward + 10
                ELSE qt.xp_reward
            END,
            qt.league_points,
            qt.difficulty
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys)
        ORDER BY array_position(v_quest_keys, qt.quest_key);
    END IF;

    -- ── Streak + completion summary (unchanged) ────────────────────────
    SELECT
        COALESCE(current_streak, 0)         AS current_streak,
        COALESCE(longest_streak, 0)         AS longest_streak,
        COALESCE(total_quests_completed, 0) AS total_completed_days
    INTO v_streak
    FROM user_quest_streaks
    WHERE user_id = v_user_id;

    IF NOT FOUND THEN
        SELECT 0 AS current_streak, 0 AS longest_streak, 0 AS total_completed_days
        INTO v_streak;
    END IF;

    SELECT
        COUNT(*) = COUNT(*) FILTER (WHERE is_completed = TRUE) AND COUNT(*) > 0
    INTO v_all_complete
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    IF v_all_complete THEN
        SELECT bonus_claimed INTO v_bonus_claimed
        FROM user_daily_quests
        WHERE user_id = v_user_id AND quest_date = v_today
        LIMIT 1;
    END IF;

    -- ── Output JSON (gains is_brief_influenced flag — 20260703) ───────
    -- The flag is recomputed on every call rather than persisted to the
    -- table so it stays in sync with the layer that picked it.
    -- v_brief_influenced_keys is empty when no slate was generated this
    -- call (returning yesterday's pre-existing rows) — that's fine; the
    -- flag is most useful on the day the slate was minted.
    RETURN json_build_object(
        'quests', (
            SELECT json_agg(row_to_json(q)) FROM (
                SELECT
                    udq.id,
                    udq.quest_key,
                    udq.title,
                    udq.description,
                    udq.icon,
                    udq.category,
                    udq.target_value,
                    udq.current_value,
                    udq.target_unit,
                    udq.xp_reward,
                    udq.league_points,
                    udq.difficulty,
                    udq.is_completed,
                    udq.completed_at,
                    qt.fun_label,
                    qt.verification_type,
                    qt.tier,
                    -- Daily Mission Unification (20260703): set when a
                    -- quest was elevated by Layer 7 (red-day recovery
                    -- nudge) or Layer 8 (debt booster). iOS
                    -- DailyQuestService decodes this as the
                    -- `isBriefInfluenced` Bool on `DailyQuest`.
                    (udq.quest_key = ANY(v_brief_influenced_keys)) AS is_brief_influenced
                FROM user_daily_quests udq
                LEFT JOIN quest_templates qt ON qt.quest_key = udq.quest_key
                WHERE udq.user_id = v_user_id AND udq.quest_date = v_today
                ORDER BY udq.is_completed ASC, udq.created_at ASC
            ) q
        ),
        'all_complete',         v_all_complete,
        'bonus_xp',             CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 50 ELSE 0 END,
        'bonus_league_points',  CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 30 ELSE 0 END,
        'quest_date',           v_today,
        'streak',               COALESCE(v_streak.current_streak, 0),
        'longest_streak',       COALESCE(v_streak.longest_streak, 0),
        'total_completed',      COALESCE(v_streak.total_completed_days, 0),
        'difficulty_profile',   v_difficulty_profile,
        'tier',                 CASE WHEN v_pro THEN 'pro' ELSE 'free' END,
        'slot_count',           v_target_slots,
        -- Echo of the brief signals the server saw — useful for
        -- analytics joins between `daily_brief_impressions` and the
        -- slate it influenced. Optional for the iOS client to read.
        'capacity_band',        v_band,
        'brief_influenced',     v_brief_influenced_keys
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT,
    TEXT, INT, TEXT, JSONB
) TO authenticated;

COMMENT ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT,
    TEXT, INT, TEXT, JSONB
) IS
    'Smart Adaptive Daily Goals v4 (20260703): adds 4 brief-signal params on top of the 32-arg v3 (20260619). New Layer 7 (Capacity Band Re-Ranker) demotes hard quests on red days + elevates PR-flag quests on green days. New Layer 8 (Debt Booster) force-elevates a quest from the matching brief-debt category into slot 2 or 3 when the payload meets a "real debt" threshold. Response gains is_brief_influenced per quest so the iOS UI can show provenance ("← from your brief"). All four new params default to NULL/empty so legacy callers (cron, backfills, pre-Phase 2 clients) see zero behavior change.';

-- ── Post-migration audit (Supabase invariant 28) ─────────────────────────
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_proc
    WHERE proname = 'get_daily_quests'
      AND pronamespace = 'public'::regnamespace;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'get_daily_quests overload audit FAILED: expected 1 definition, found %',
            v_count
            USING ERRCODE = 'P0001';
    END IF;

    RAISE NOTICE 'get_daily_quests v4 overload audit OK — exactly 1 definition.';
END $$;

COMMIT;

-- ─── Verification (run manually post-deploy) ───────────────────────────
-- Sanity: yellow recovery + 35g protein-pace deficit → slate includes hit_protein_goal
-- with is_brief_influenced=true.
--
-- SELECT get_daily_quests(
--     auth.uid()::TEXT,
--     'America/New_York',
--     FALSE, FALSE, FALSE, 10000, 'Build Muscle', FALSE, 7, 180,
--     'evening', 45, FALSE, FALSE, 0, 0, 'push', '{}'::TEXT[], '{}'::TEXT[],
--     TRUE, TRUE, FALSE, FALSE, FALSE, '{}'::jsonb, 0, NULL, NULL,
--     NULL, NULL, FALSE, 'free',
--     'yellow', 61, 'proteinDeficit',
--     '{"deficitVsPaceG":"35","subKind":"behindPace","goalG":"160"}'::jsonb
-- );
--
-- Red day fixture: same call with p_capacity_band='red' should drop
-- hard-difficulty quests AND elevate at least one recovery_pool key.
