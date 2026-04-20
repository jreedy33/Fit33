-- ============================================================================
-- 20260420 — Daily quests: actionable, skill-aware, non-confusing
--
-- Fixes three user-facing bugs in get_daily_quests:
--
--   1. "Program Day — complete your next program day" was handed out to users
--      who have NO active program. The previous selector (20260325_quest_
--      challenge_sync.sql) built its pools by category only and never looked
--      at quest_templates.requires_context, so every has_program / has_friends
--      / no_friends / no_challenge / free_user gate was silently bypassed.
--
--   2. "Double Session — knock out 2 workouts today" is retired. Two full
--      workouts in one day is not general-audience advice and most users
--      cannot complete it. We mark the template inactive so it stops
--      appearing, and we make sure the hard-day fallback no longer points
--      at it.
--
--   3. The pool WHERE clause dropped the `tracking`, `wildcard`, and
--      `reward` categories entirely and never respected `min_workouts`, so
--      brand-new users could draw hard "beat a PR" quests while veteran
--      users never saw quests like `beat_personal_record`, `perfect_day`,
--      `early_bird_workout`, `log_cardio`, or `watch_ads`. We now filter on
--      `min_workouts <= p_total_workouts` and include every category the
--      selector pipeline knows how to complete.
--
-- Also sets reasonable `min_workouts` gates on a handful of existing
-- templates so the first week of quests stays achievable.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Retire the "2 workouts in a day" quest — bad training advice.
--    Keep the row so historical user_daily_quests rows still resolve to a
--    template (for title / icon lookups), but stop giving it out.
-- ────────────────────────────────────────────────────────────────────────────
UPDATE quest_templates
SET is_active = FALSE,
    weight = 0
WHERE quest_key = 'complete_2_workouts';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Add skill-level gating via min_workouts.
--    These keep brand-new users out of the high-volume / PR-style quests
--    and give them achievable, morale-building goals in week one.
--    min_workouts = 0 means "available from day one".
-- ────────────────────────────────────────────────────────────────────────────
UPDATE quest_templates SET min_workouts = 0  WHERE quest_key IN (
    'complete_workout', 'complete_program_day', 'workout_30_min',
    'upper_body_workout', 'lower_body_workout', 'try_new_exercise',
    'stretch_session',
    'log_breakfast', 'log_lunch', 'log_dinner', 'log_snack',
    'log_3_meals', 'log_water_3', 'log_high_protein_meal',
    'walk_3k_steps', 'walk_5k_steps', 'hit_step_goal',
    'add_friend', 'invite_friend', 'start_first_challenge',
    'log_weight', 'check_progress', 'log_cardio',
    'favorite_a_workout', 'watch_ads',
    'sleep_7_hours', 'weekly_weigh_in', 'hydration_before_noon',
    'active_minutes_30'
);

UPDATE quest_templates SET min_workouts = 3  WHERE quest_key IN (
    'exercise_sets_15', 'walk_7500_steps', 'early_bird_workout',
    'send_challenge', 'start_1v1_challenge', 'react_to_workout',
    'share_workout', 'maintain_streak'
);

UPDATE quest_templates SET min_workouts = 6  WHERE quest_key IN (
    'walk_10k_steps', 'log_water_8', 'log_high_protein_meal',
    'log_all_macros', 'burn_300_calories', 'beat_friend_steps'
);

UPDATE quest_templates SET min_workouts = 10 WHERE quest_key IN (
    'exercise_sets_25', 'hit_protein_goal', 'perfect_day'
);

UPDATE quest_templates SET min_workouts = 15 WHERE quest_key IN (
    'beat_personal_record', 'beat_volume_pr', 'league_3_workouts'
);

UPDATE quest_templates SET min_workouts = 50 WHERE quest_key = 'top_3_league';

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Replace get_daily_quests with a selector that:
--      • respects requires_context (NO "program day" without a program, etc.)
--      • respects min_workouts (skill-level gating)
--      • draws from every relevant category, not just six
--      • keeps the step-challenge title/target override behaviour
--      • keeps the 16-arg signature the iOS client already calls
-- ────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT
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
    p_active_step_challenge_target INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id            UUID := p_user_id::UUID;
    v_today              DATE;
    v_quest_count        INT;
    v_streak             RECORD;
    v_bonus_claimed      BOOLEAN := FALSE;
    v_all_complete       BOOLEAN := FALSE;
    v_day_seed           INT;
    v_difficulty_profile TEXT;
    v_quest_keys         TEXT[] := '{}';
    v_pool_easy          TEXT[];
    v_pool_medium        TEXT[];
    v_pool_hard          TEXT[];
    v_recent_keys        TEXT[];
    v_total_wk           INT  := COALESCE(p_total_workouts, 0);
    v_wk_streak          INT  := COALESCE(p_workout_streak, 0);
    v_step_keys          TEXT[] := ARRAY[
        'walk_3k_steps', 'walk_5k_steps', 'walk_7500_steps',
        'walk_10k_steps', 'hit_step_goal'
    ];
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Deterministic per-day seed (same user + day ⇒ same quests).
    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

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
        -- Fewer than 20 workouts → never a full hard day.
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
        -- Eligibility pool — the ONE source of truth for "can this user
        -- complete this quest today?". Category is only used for variety
        -- downstream; gating happens here.
        -- ───────────────────────────────────────────────────────────────
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          AND COALESCE(qt.min_workouts, 0) <= v_total_wk
          AND qt.quest_key != ALL(v_recent_keys)
          -- ★ requires_context is enforced here — no more "program day"
          --   for users without a program.
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

        -- Safe fallbacks — complete_workout + walk_5k are always appropriate.
        v_pool_easy   := COALESCE(v_pool_easy,   ARRAY['complete_workout', 'walk_5k_steps', 'log_breakfast']);
        v_pool_medium := COALESCE(v_pool_medium, ARRAY['workout_30_min', 'walk_7500_steps', 'log_3_meals']);
        -- Hard fallback: NOT complete_2_workouts anymore. Volume+steps are safe.
        v_pool_hard   := COALESCE(v_pool_hard,   ARRAY['exercise_sets_25', 'walk_10k_steps', 'hit_step_goal']);

        -- ───────────────────────────────────────────────────────────────
        -- Select 3 quest keys according to the day's difficulty profile.
        -- Uses day seed for deterministic-but-varied rotation.
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

        -- Insert the 3 quests — keep the step-challenge title/target override
        -- so a 10K step challenge surfaces "10K Challenge Steps" rather than
        -- a stale "7.5K" quest alongside it.
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
                         || ' step challenge target'
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

    -- Streak row (named fields preserved — fixes the earlier RECORD bug).
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
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT
) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Clean up today's in-flight quests for anyone who was already dealt
--    the bad keys AND has not yet completed anything today. We clear the
--    full day's set so the selector re-runs with the correct context-aware
--    rules on next fetch (partial deletes won't trigger re-selection —
--    the selector only runs when COUNT(*) = 0 for that user/date).
--    Users who already completed at least one quest today keep their
--    progress; the bad quest simply sits unfinished until tomorrow.
-- ────────────────────────────────────────────────────────────────────────────
DELETE FROM user_daily_quests
WHERE (user_id, quest_date) IN (
    SELECT user_id, quest_date
    FROM user_daily_quests
    WHERE quest_date = CURRENT_DATE
    GROUP BY user_id, quest_date
    HAVING bool_or(quest_key IN ('complete_2_workouts', 'complete_program_day'))
       AND bool_and(is_completed = FALSE)
);
