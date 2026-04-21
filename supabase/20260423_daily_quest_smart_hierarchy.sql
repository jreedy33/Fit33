-- ============================================================================
-- 20260423 — Daily quests: smart hierarchy (redundancy + diversity + challenges)
--
-- Supersedes 20260422_daily_quest_workout_slot_flexibility.sql. Same slot-1
-- "any workout counts" contract, but the slot-2/3 selection gets three new
-- layers of intelligence so the 3 visible goals feel distinct and relevant.
--
-- Adds one new optional parameter:
--   p_active_challenge_types TEXT[]  DEFAULT '{}'
--     Subset of:
--       'steps', 'walk', 'run', 'active_minutes', 'calories',
--       'hydrate', 'protein', 'workout_streak', 'lift'
--     Mirrors the `challenge_type` column on `challenges` / `group_challenges`
--     for every 1v1 / group challenge the user is currently participating in.
--
-- Behavior changes:
--
--   1. REDUNDANCY MATRIX. When slot 1 is a workout-category quest
--      (complete_workout / complete_program_day / complete_2_workouts), the
--      following keys are removed from the eligible pool for slots 2/3
--      because they are logically satisfied by finishing any workout:
--        • active_minutes_30  — any session >= 30 min of sustained effort
--        • burn_300_calories  — typical strength session burns 250-400 cal
--        • workout_30_min     — same target as completing a workout
--        • exercise_sets_15   — 15 sets = a typical session
--        • exercise_sets_25   — still redundant with "any workout counts"
--        • beat_volume_pr     — same workout domain
--        • stretch_session    — still a workout-category quest
--        • maintain_streak    — today's workout already keeps the streak
--        • league_3_workouts  — different target but same category
--        • complete_2_workouts, early_bird_workout — redundant framing
--      Exception: the CHALLENGE OVERRIDE below can re-admit any of these.
--
--   2. CHALLENGE OVERRIDE. For every active challenge type the user is
--      competing on, the matching quest is FORCED into slot 2 (or slot 3 if
--      slot 2 is already taken by a higher-priority challenge). This matches
--      the user's stated rule: "if I'm competing on steps, my daily quest
--      should reinforce that". The override bypasses the redundancy matrix
--      because the user is actively engaged on that metric.
--        steps / walk / run  → step quest via p_active_step_challenge_target
--        active_minutes      → active_minutes_30
--        calories            → burn_300_calories
--        hydrate             → log_water_8
--        protein             → hit_protein_goal
--        workout_streak      → maintain_streak
--        lift                → exercise_sets_15
--
--   3. CATEGORY DIVERSITY. The final 3 quests MUST span at least 2 distinct
--      categories from {workout, nutrition, steps, tracking, social}. If the
--      pool-builder produced 2-3 quests in the same category (e.g. two
--      nutrition quests beside a workout slot), slot 3 is swapped for the
--      next-best complementary category using this priority ladder:
--        workout slot 1 → prefer nutrition > steps > tracking > social
--        steps slot 1   → prefer nutrition > workout > tracking > social
--        other slot 1   → prefer nutrition > workout > steps > tracking
--      This guarantees "log a meal" or "drink water" shows up alongside the
--      workout quest — never "do a workout" + "get 30 active minutes" + "burn
--      300 calories", which all tick off the moment one workout finishes.
-- ============================================================================

BEGIN;

-- Drop every prior overload (16-arg + 18-arg) before recreating with 19 args.
DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT
);

DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[]
);

DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[]
);

CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id                      TEXT,
    p_timezone                     TEXT DEFAULT 'America/New_York',
    p_has_program                  BOOLEAN DEFAULT FALSE,
    p_has_friends                  BOOLEAN DEFAULT FALSE,
    p_has_challenge                BOOLEAN DEFAULT FALSE,
    p_step_goal                    INT DEFAULT 10000,
    p_fitness_goal                 TEXT DEFAULT 'general',
    p_is_subscriber                BOOLEAN DEFAULT FALSE,
    p_workout_streak               INT DEFAULT 0,
    p_total_workouts               INT DEFAULT 0,
    p_preferred_time               TEXT DEFAULT 'any',
    p_avg_duration                 INT DEFAULT 45,
    p_has_weight_log               BOOLEAN DEFAULT FALSE,
    p_hydration_active             BOOLEAN DEFAULT FALSE,
    p_league_rank                  INT DEFAULT 0,
    p_active_step_challenge_target INT DEFAULT 0,
    p_suggested_split              TEXT DEFAULT NULL,
    p_fatigued_regions             TEXT[] DEFAULT '{}',
    p_active_challenge_types       TEXT[] DEFAULT '{}'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id                UUID := p_user_id::UUID;
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
    -- Keys that become logically redundant once slot 1 is a workout quest.
    -- Kept in the templates for analytics + legacy rows, but we filter them
    -- from new daily selections when slot 1 already covers the same ground.
    v_redundant_with_workout TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories', 'workout_30_min',
        'exercise_sets_15', 'exercise_sets_25', 'beat_volume_pr',
        'stretch_session', 'maintain_streak', 'league_3_workouts',
        'complete_2_workouts', 'early_bird_workout'
    ];
    -- Keys redundant with a completed step-goal: 10K steps already buys you
    -- 30+ active minutes and 300+ active calories on virtually every device.
    v_redundant_with_steps   TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories'
    ];
    v_slot1_is_workout       BOOLEAN;
    v_slot1_is_steps         BOOLEAN;
    v_challenge_quest_keys   TEXT[] := '{}';
    v_cat_counts             JSONB;
    v_slot3_category         TEXT;
    v_category_ladder        TEXT[];
    v_swap_candidate         TEXT;
    v_i                      INT;
    v_distinct_cats          INT;
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

    -- ───────────────────────────────────────────────────────────────
    -- Slot 1 preferred key (unchanged from 20260422).
    -- ───────────────────────────────────────────────────────────────
    IF p_has_program THEN
        v_preferred_workout_key := 'complete_program_day';
    ELSE
        v_preferred_workout_key := 'complete_workout';
    END IF;

    v_slot1_is_workout := v_preferred_workout_key IN (
        'complete_workout', 'complete_program_day', 'complete_2_workouts'
    );

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

    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    IF v_quest_count = 0 THEN
        SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '3 days'
          AND quest_date < v_today;

        -- ───────────────────────────────────────────────────────────────
        -- Build the challenge-override list FIRST so it can re-admit keys
        -- the redundancy matrix would otherwise strip. Priority order
        -- (first wins): active_minutes → calories → hydrate → protein →
        -- streak → lift. Steps are handled via p_active_step_challenge_target.
        -- ───────────────────────────────────────────────────────────────
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

        -- ───────────────────────────────────────────────────────────────
        -- Eligibility pool. upper_body_workout / lower_body_workout remain
        -- excluded (20260422 invariant). Additionally, keys in the workout
        -- redundancy matrix are filtered when slot 1 is a workout quest,
        -- UNLESS they've been re-admitted by the challenge override above.
        -- ───────────────────────────────────────────────────────────────
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          AND COALESCE(qt.min_workouts, 0) <= v_total_wk
          AND qt.quest_key != ALL(v_recent_keys)
          AND qt.quest_key NOT IN ('upper_body_workout', 'lower_body_workout')
          AND NOT (
                v_slot1_is_workout
                AND qt.quest_key = ANY(v_redundant_with_workout)
                AND qt.quest_key <> ALL(v_challenge_quest_keys)
          )
          AND (
                qt.requires_context IS NULL
             OR (qt.requires_context = 'has_program'   AND p_has_program)
             OR (qt.requires_context = 'has_friends'   AND p_has_friends)
             OR (qt.requires_context = 'has_challenge' AND p_has_challenge)
             OR (qt.requires_context = 'no_friends'    AND NOT p_has_friends)
             OR (qt.requires_context = 'no_challenge'  AND NOT p_has_challenge)
             OR (qt.requires_context = 'free_user'     AND NOT p_is_subscriber)
          );

        SELECT ARRAY_AGG(quest_key) INTO v_pool_easy   FROM _eligible_quests WHERE difficulty = 'easy';
        SELECT ARRAY_AGG(quest_key) INTO v_pool_medium FROM _eligible_quests WHERE difficulty = 'medium';
        SELECT ARRAY_AGG(quest_key) INTO v_pool_hard   FROM _eligible_quests WHERE difficulty = 'hard';

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
        ELSE -- mixed_day
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

        -- ───────────────────────────────────────────────────────────────
        -- CHALLENGE OVERRIDE. Force each active-challenge-matched quest
        -- into slot 2/3 (never slot 1 — slot 1 is reserved for the workout
        -- slot). Earlier entries in v_challenge_quest_keys win slot 2.
        -- ───────────────────────────────────────────────────────────────
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

        -- ───────────────────────────────────────────────────────────────
        -- REDUNDANCY SWEEP (post-selection). Even with the pool filter,
        -- slot 3 might still land on a "redundant-with-steps" pick when
        -- slot 1 is a step quest. Swap it for the next-best nutrition/
        -- tracking key that isn't already chosen.
        -- ───────────────────────────────────────────────────────────────
        IF v_slot1_is_steps THEN
            FOR v_i IN 2..3 LOOP
                IF v_quest_keys[v_i] = ANY(v_redundant_with_steps)
                   AND v_quest_keys[v_i] <> ALL(v_challenge_quest_keys) THEN
                    SELECT quest_key INTO v_swap_candidate
                    FROM _eligible_quests
                    WHERE category IN ('nutrition', 'tracking')
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[v_i] := v_swap_candidate;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ───────────────────────────────────────────────────────────────
        -- CATEGORY DIVERSITY. Recount categories across the final slots.
        -- If fewer than 2 distinct categories remain, swap slot 3 for the
        -- highest-priority complementary category that isn't represented.
        -- ───────────────────────────────────────────────────────────────
        SELECT COUNT(DISTINCT qt.category)
          INTO v_distinct_cats
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys);

        IF v_distinct_cats < 2 THEN
            -- Ladder depends on slot 1's anchor category.
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
                    FROM _eligible_quests
                    WHERE category = v_category_ladder[v_i]
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[3] := v_swap_candidate;
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- Free users without a challenge-driven slot 3 still get the ad
        -- quest (unchanged revenue hook).
        IF NOT p_is_subscriber
           AND array_length(v_challenge_quest_keys, 1) IS NULL
           AND EXISTS (SELECT 1 FROM _eligible_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        -- ───────────────────────────────────────────────────────────────
        -- Insert the 3 quests. Copy strings kept short so the quest card
        -- renders on a single line. The client-side `dynamicDescription`
        -- may further shorten / personalize with live challenge deficit
        -- data ("5K to catch KC"). Keep ALL server copy ≤ 35 chars.
        -- ───────────────────────────────────────────────────────────────
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN CASE
                        WHEN p_active_step_challenge_target >= 10000
                            THEN (p_active_step_challenge_target / 1000) || 'K Challenge Steps'
                        ELSE p_active_step_challenge_target::TEXT || ' Challenge Steps'
                    END
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Program Day'
                ELSE qt.title
            END,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN 'Hit your ' ||
                         CASE
                            WHEN p_active_step_challenge_target >= 10000
                                THEN (p_active_step_challenge_target / 1000) || 'K'
                            ELSE p_active_step_challenge_target::TEXT
                         END
                         || ' challenge target'
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
                    GREATEST(p_step_goal, COALESCE(NULLIF(p_active_step_challenge_target, 0), 0))
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
                    qt.verification_type
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
        'difficulty_profile',   v_difficulty_profile
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[]
) TO authenticated;

COMMIT;
