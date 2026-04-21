-- ============================================================================
-- 20260421 — Daily quests: program-aware + muscle-focus-aware workout slot
--
-- Builds on 20260420_daily_quests_actionable_fixes.sql. That migration fixed
-- requires_context gating (no more "Program Day" without a program). This
-- migration adds a second layer of intelligence for the "not-in-program"
-- audience:
--
--   1. The workout slot (slot 1) always gets a workout-category quest that
--      matches the user's recent training history:
--        • has_program   → 'complete_program_day' (same as before)
--        • legs split    → 'lower_body_workout'  (assuming lower not fatigued)
--        • push/pull/up  → 'upper_body_workout'  (assuming upper not fatigued)
--        • full body     → 'workout_30_min'
--        • fallback      → 'complete_workout'
--
--   2. Upper/lower generic workouts are EXCLUDED from the eligible pool when
--      the matching region (upper / lower) is still fatigued per client-side
--      muscle-recovery data. Never pick a goal that targets fatigued muscles.
--
--   3. When slot 1 is a generic workout key and the client passed a
--      suggested split, rewrite the stored title/description for that row so
--      the UI reads like a personalized recommendation ("Leg Day — your legs
--      are fresh"). The quest_key stays the same so XP / progress tracking
--      continues to work.
--
-- New params (both optional; old clients continue to work):
--   p_suggested_split   TEXT DEFAULT NULL
--     one of 'push' | 'pull' | 'legs' | 'upper' | 'full' | 'core_cardio'
--   p_fatigued_regions  TEXT[] DEFAULT '{}'
--     subset of {'upper','lower'}
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- Drop previous overload(s). Postgres treats each signature as a separate
-- function, so we explicitly drop the 16-arg version created by migration 54
-- before recreating with 18 args.
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT
);

DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[]
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
    p_fatigued_regions             TEXT[] DEFAULT '{}'
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
    v_upper_fatigued         BOOLEAN := 'upper' = ANY(COALESCE(p_fatigued_regions, '{}'));
    v_lower_fatigued         BOOLEAN := 'lower' = ANY(COALESCE(p_fatigued_regions, '{}'));
    v_preferred_workout_key  TEXT;
    v_step_keys              TEXT[] := ARRAY[
        'walk_3k_steps', 'walk_5k_steps', 'walk_7500_steps',
        'walk_10k_steps', 'hit_step_goal'
    ];
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Deterministic per-day seed (same user + day ⇒ same quests).
    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

    -- ───────────────────────────────────────────────────────────────
    -- Preferred workout slot. Program users always get complete_program_day
    -- (the requires_context gate below ensures it is eligible). Non-program
    -- users get a generic workout key that matches their recovered split.
    -- ───────────────────────────────────────────────────────────────
    IF p_has_program THEN
        v_preferred_workout_key := 'complete_program_day';
    ELSIF p_suggested_split = 'legs' AND NOT v_lower_fatigued THEN
        v_preferred_workout_key := 'lower_body_workout';
    ELSIF p_suggested_split IN ('push', 'pull', 'upper') AND NOT v_upper_fatigued THEN
        v_preferred_workout_key := 'upper_body_workout';
    ELSIF p_suggested_split = 'full' THEN
        v_preferred_workout_key := 'workout_30_min';
    ELSE
        v_preferred_workout_key := 'complete_workout';
    END IF;

    -- Difficulty profile — gentler for newcomers, more spice for veterans.
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
        -- Anti-repetition: last 3 days of keys.
        SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '3 days'
          AND quest_date < v_today;

        -- ───────────────────────────────────────────────────────────────
        -- Eligibility pool — all gating happens here. A row in this temp
        -- table means "the user can complete this quest today".
        -- ───────────────────────────────────────────────────────────────
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          AND COALESCE(qt.min_workouts, 0) <= v_total_wk
          AND qt.quest_key != ALL(v_recent_keys)
          AND (
                qt.requires_context IS NULL
             OR (qt.requires_context = 'has_program'   AND p_has_program)
             OR (qt.requires_context = 'has_friends'   AND p_has_friends)
             OR (qt.requires_context = 'has_challenge' AND p_has_challenge)
             OR (qt.requires_context = 'no_friends'    AND NOT p_has_friends)
             OR (qt.requires_context = 'no_challenge'  AND NOT p_has_challenge)
             OR (qt.requires_context = 'free_user'     AND NOT p_is_subscriber)
          )
          -- ★ Fatigue-aware exclusions — never deal a goal that targets
          --   muscles the user has already trained recently.
          AND NOT (qt.quest_key = 'upper_body_workout' AND v_upper_fatigued)
          AND NOT (qt.quest_key = 'lower_body_workout' AND v_lower_fatigued);

        SELECT ARRAY_AGG(quest_key) INTO v_pool_easy   FROM _eligible_quests WHERE difficulty = 'easy';
        SELECT ARRAY_AGG(quest_key) INTO v_pool_medium FROM _eligible_quests WHERE difficulty = 'medium';
        SELECT ARRAY_AGG(quest_key) INTO v_pool_hard   FROM _eligible_quests WHERE difficulty = 'hard';

        -- Safe fallbacks — complete_workout + walk_5k are always appropriate.
        v_pool_easy   := COALESCE(v_pool_easy,   ARRAY['complete_workout', 'walk_5k_steps', 'log_breakfast']);
        v_pool_medium := COALESCE(v_pool_medium, ARRAY['workout_30_min', 'walk_7500_steps', 'log_3_meals']);
        v_pool_hard   := COALESCE(v_pool_hard,   ARRAY['exercise_sets_25', 'walk_10k_steps', 'hit_step_goal']);

        -- ───────────────────────────────────────────────────────────────
        -- Select 3 quest keys from the day's difficulty profile.
        -- ───────────────────────────────────────────────────────────────
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

        -- ★ Force slot 1 to the preferred workout key if it's eligible.
        --   Slot 1 is the "workout" slot in the UI. For non-program users
        --   this picks the right generic workout quest based on recent
        --   training history. For program users it's complete_program_day.
        IF v_preferred_workout_key IS NOT NULL
           AND EXISTS (SELECT 1 FROM _eligible_quests WHERE quest_key = v_preferred_workout_key)
           AND v_preferred_workout_key <> ALL(v_quest_keys) THEN
            v_quest_keys[1] := v_preferred_workout_key;
        END IF;

        -- Guarantee the ad quest slot for free users if eligible and not
        -- already included (replaces the weakest slot deterministically).
        IF NOT p_is_subscriber
           AND EXISTS (SELECT 1 FROM _eligible_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        -- Ensure streak row exists
        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        -- ───────────────────────────────────────────────────────────────
        -- Insert the 3 quests with optional per-row personalization:
        --   • Step-challenge override (existing behavior).
        --   • Split-aware title/description override for the workout slot
        --     when the client passed p_suggested_split.
        -- ───────────────────────────────────────────────────────────────
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            -- Title
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN CASE
                        WHEN p_active_step_challenge_target >= 10000
                            THEN (p_active_step_challenge_target / 1000) || 'K Challenge Steps'
                        ELSE p_active_step_challenge_target::TEXT || ' Challenge Steps'
                    END
                WHEN qt.quest_key IN ('complete_workout', 'workout_30_min', 'upper_body_workout', 'lower_body_workout')
                     AND p_suggested_split IS NOT NULL
                    THEN CASE p_suggested_split
                        WHEN 'legs'  THEN 'Leg Day'
                        WHEN 'push'  THEN 'Push Day'
                        WHEN 'pull'  THEN 'Pull Day'
                        WHEN 'upper' THEN 'Upper Body Day'
                        WHEN 'full'  THEN 'Full Body Day'
                        ELSE qt.title
                    END
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Program Day'
                ELSE qt.title
            END,
            -- Description
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN 'Hit your ' ||
                         CASE
                            WHEN p_active_step_challenge_target >= 10000
                                THEN (p_active_step_challenge_target / 1000) || 'K'
                            ELSE p_active_step_challenge_target::TEXT
                         END
                         || ' step challenge target'
                WHEN qt.quest_key IN ('complete_workout', 'workout_30_min', 'upper_body_workout', 'lower_body_workout')
                     AND p_suggested_split IS NOT NULL
                    THEN CASE p_suggested_split
                        WHEN 'legs'  THEN 'Your legs are fresh — hit quads & hamstrings today'
                        WHEN 'push'  THEN 'Chest, shoulders & triceps are ready'
                        WHEN 'pull'  THEN 'Back & biceps are fresh — time to pull'
                        WHEN 'upper' THEN 'Upper body is recovered — chest & back are ready'
                        WHEN 'full'  THEN 'Everything is fresh — well-rounded session today'
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

    -- Streak row (named fields).
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
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[]
) TO authenticated;

COMMIT;
