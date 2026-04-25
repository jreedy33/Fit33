-- ============================================================================
-- 20260605 — Smart Adaptive Daily Goals: get_daily_quests v3 (6 layers)
--
-- Resolves: e656ad7a4fb1323db476cd8f2cf6ac39 — get_daily_quests PGRST202 (Report 5 / 04-25 audit)
-- Resolves: 486b89c025c019b7f2b6c427a437811e — same PGRST202, log variant (Report 20 / 04-25 audit)
--
-- Phase 5 of the personalization upgrade. New body keeps every existing
-- contract from 20260423 (slot 1 workout, redundancy matrix, challenge
-- override, category diversity) and adds three new layers:
--
--   Layer 4: ACTIVITY-MIX BIAS + PER-USER WEIGHTING
--     +30% selection score when quest activity-bucket aligns with the
--           user's dominant share in p_activity_mix (cardio user → cardio).
--     +25% when quest_key has user_quest_key_stats.completion_rate_28d ≥ 0.75
--           (the user keeps finishing this — surface it again).
--     +10% gentle "exploration" bump on the user's least-touched bucket
--           (sneak in cardio for a strength-heavy user, etc.) — only when
--           the category is NOT suppressed.
--     −90% when (user_id, quest_key) or (user_id, category) is suppressed
--           (effectively excluded — "stop showing it if they keep skipping").
--
--   Layer 5: SKIP-STREAK FLOOR
--     If after layer 4 a slot still wins with a suppressed quest (because
--     the pool is too thin), fall back to the next-best non-suppressed
--     category from the existing diversity ladder.
--
--   Layer 6: FRIEND-NAMED COPY + PRO EXTRA SLOTS
--     * Step quests rewritten to "Beat <FriendName>: 8.4K" when
--       p_friend_step_target > 0.
--     * do_friend_workout preferred over complete_workout for slot 1 when
--       p_friend_top_workout_title is set, with split-recommendation-aware
--       copy:
--         matches_recommendation = TRUE  → "Due for <split> — do <Friend>'s"
--         matches_recommendation = FALSE → "Do <Friend>'s <Title>"
--     * p_quest_tier = 'pro' → 5 slots (slot 4 exploration, slot 5 hard wildcard).
--
-- New eligibility predicates added to the requires_context branch (this
-- also retires the stub at the bottom of 20260509_wearable_quests.sql):
--   has_wearable / has_strava / has_whoop / has_oura / has_fitbit /
--   has_friends_no_challenge.
--
-- New params (all nullable / default-safe — old clients don't break):
--   p_strava_connected, p_whoop_connected, p_oura_connected,
--   p_fitbit_connected, p_activity_mix JSONB, p_friend_step_target,
--   p_friend_name, p_friend_top_workout_id, p_friend_top_workout_title,
--   p_friend_top_workout_split, p_friend_top_workout_matches_recommendation,
--   p_quest_tier.
--
-- Idempotent: drops every existing overload via the canonical pg_proc loop
-- before CREATE OR REPLACE (Supabase invariant 12).
-- ============================================================================

BEGIN;

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
    p_quest_tier                                    TEXT    DEFAULT 'free'
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
    v_target_slots           INT := CASE WHEN v_pro THEN 5 ELSE 3 END;
    v_dominant_bucket        TEXT;
    v_least_bucket           TEXT;
    v_friend_step_label      TEXT;
    v_friend_workout_copy    TEXT;
    v_friend_workout_short   TEXT;
BEGIN
    -- IDOR guard (Data invariant 7). The RPC is SECURITY DEFINER; we
    -- never trust p_user_id when an authenticated caller is present.
    -- Service-role + cron contexts (auth.uid() IS NULL) are allowed
    -- through unchanged so backfills + admin tools still work.
    IF v_caller_id IS NOT NULL AND v_caller_id <> v_user_id THEN
        RAISE EXCEPTION 'get_daily_quests IDOR: caller % does not match p_user_id %', v_caller_id, v_user_id
            USING ERRCODE = '42501';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

    -- ── Slot 1 preferred key (unchanged) ───────────────────────────────
    IF p_has_program THEN
        v_preferred_workout_key := 'complete_program_day';
    ELSE
        v_preferred_workout_key := 'complete_workout';
    END IF;
    v_slot1_is_workout := v_preferred_workout_key IN (
        'complete_workout', 'complete_program_day', 'complete_2_workouts'
    );

    -- ── Difficulty profile (unchanged) ─────────────────────────────────
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

    -- ── Activity-mix dominant / least bucket (Layer 4 inputs) ──────────
    -- Read from p_activity_mix JSONB OR fall back to user_activity_mix table.
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

        -- ── Eligibility pool (with NEW context predicates + Pro tier) ──
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type, qt.tier,
               qt.weight,
               -- Activity bucket per quest (mapped from quest_key for granularity).
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
          -- Tier gating: free tier excludes 'pro' templates.
          AND (v_pro OR qt.tier = 'free')
          AND NOT (
                v_slot1_is_workout
                AND qt.quest_key = ANY(v_redundant_with_workout)
                AND qt.quest_key <> ALL(v_challenge_quest_keys)
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

        -- Suppression filter (Layer 4 / "stop showing it if they keep
        -- skipping it"). Removes any quest_key whose (user, key) has an
        -- active suppressed_until OR whose (user, category) is suppressed.
        -- Challenge-override keys are NEVER suppressed — challenges always
        -- win the floor.
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

        -- ── Layer 4: scored pool ──────────────────────────────────────
        -- Score = base weight × (1 + dominant_bias + favorite_bias + explore_bias)
        -- Suppression already removed above (effectively −∞), so we don't
        -- recompute the −90% term — it's enforced by exclusion.
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
                  )
            ) AS selection_score
        FROM _eligible_quests eq;

        -- Snap pool buckets from scored set so the existing ARRAY index
        -- math still works.
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_easy   FROM _scored_quests WHERE difficulty = 'easy';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_medium FROM _scored_quests WHERE difficulty = 'medium';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_hard   FROM _scored_quests WHERE difficulty = 'hard';

        -- Fallback seeds if a bucket came up empty (e.g. brand new user
        -- with thin templates after suppression).
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

        -- Force slot 1 to the preferred workout key.
        IF v_preferred_workout_key IS NOT NULL
           AND EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_preferred_workout_key AND is_active)
           AND v_preferred_workout_key <> ALL(v_quest_keys) THEN
            v_quest_keys[1] := v_preferred_workout_key;
        END IF;

        v_slot1_is_steps := v_quest_keys[1] IN ('hit_step_goal', 'walk_10k_steps');

        -- ── Layer 6a: friend-named slot 1 swap ────────────────────────
        -- When the user has a recent shared friend workout AND
        -- do_friend_workout is in the eligibility pool, prefer it over
        -- the generic workout slot. The Swift caller has already done
        -- the muscle-recovery-aware ranking; here we just honor the seed.
        IF p_friend_top_workout_title IS NOT NULL
           AND p_friend_name IS NOT NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'do_friend_workout') THEN
            v_quest_keys[1] := 'do_friend_workout';
            v_slot1_is_workout := TRUE;  -- still anchors as workout for diversity ladder
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
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[v_i] := v_swap_candidate;
                    END IF;
                END IF;
            END LOOP;
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
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[3] := v_swap_candidate;
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ── Layer 5: skip-streak floor — sanity sweep ────────────────
        -- After all the above, ensure no slot ended up with a key that's
        -- still suppressed (could happen if the pool was so thin it had
        -- to be filled from fallback seeds). Replace any suppressed slot
        -- with the highest-scored non-suppressed candidate not already
        -- chosen. Slot 1 is never replaced (anchor invariant).
        FOR v_i IN 2..3 LOOP
            IF v_quest_keys[v_i] IS NULL THEN CONTINUE; END IF;
            IF v_quest_keys[v_i] = ANY(v_challenge_quest_keys) THEN CONTINUE; END IF;

            IF NOT EXISTS (
                SELECT 1 FROM _scored_quests sq
                WHERE sq.quest_key = v_quest_keys[v_i]
            ) THEN
                -- The picked key is NOT in the post-suppression pool →
                -- swap for top non-chosen scored candidate.
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
                IF v_swap_candidate IS NOT NULL THEN
                    v_quest_keys[v_i] := v_swap_candidate;
                END IF;
            END IF;
        END LOOP;

        -- ── Layer 6b: Pro extra slots (4 + 5) ─────────────────────────
        IF v_pro THEN
            -- Slot 4: fresh exploration category — least_bucket if known.
            IF v_least_bucket IS NOT NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE activity_bucket = v_least_bucket
                  AND quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NOT NULL THEN
                v_quest_keys[4] := v_swap_candidate;
                v_swap_candidate := NULL;
            END IF;

            -- Slot 5: hard-tier wildcard.
            SELECT quest_key INTO v_swap_candidate
            FROM _scored_quests
            WHERE difficulty = 'hard'
              AND quest_key <> ALL(v_quest_keys)
            ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
            LIMIT 1;
            IF v_swap_candidate IS NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NOT NULL THEN
                v_quest_keys[5] := v_swap_candidate;
                v_swap_candidate := NULL;
            END IF;
        END IF;

        -- ── Free-user ad slot (unchanged revenue hook) ────────────────
        IF NOT p_is_subscriber
           AND array_length(v_challenge_quest_keys, 1) IS NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        -- ── Pre-compute friend label strings (≤ 35 chars) ────────────
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
                -- "Due for chest — do Paul's"   (≤ 35 chars target)
                v_friend_workout_copy := 'Due for ' || p_friend_top_workout_split
                                      || ' — do ' || p_friend_name || E'\u2019s';
            ELSE
                -- Fallback generic copy.
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

        -- ── Insert the slate ──────────────────────────────────────────
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            -- Title rewrites:
            --   * step quests get "Beat <Friend>: 8.4K" when seeded
            --   * do_friend_workout gets the split-aware copy
            --   * complete_program_day shorthand (legacy)
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
            -- Description rewrites: same logic, but description may be
            -- slightly longer (server still <= 35 chars per Data #32).
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
                    qt.tier
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
        'slot_count',           v_target_slots
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT
) TO authenticated;

COMMENT ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT
) IS
    'Smart Adaptive Daily Goals v3 (20260605): 6-layer personalized quest selection. Layers — 1 workout slot, 2 redundancy matrix, 3 challenge override, 4 activity-mix bias + per-user weighting + suppression, 5 skip-streak floor, 6 friend-named copy + Pro 5-slot expansion. Replaces the 20-arg signature from 20260509b.';

COMMIT;
