-- When a user has an active step challenge (e.g. 10K daily), any step-related
-- daily quest should match the challenge target instead of the hardcoded template
-- value.  This avoids the confusing UX where a quest says "7.5K" while the
-- challenge card right below says "10K".
--
-- New parameter: p_active_step_challenge_target (default 0 = no active challenge).
-- The app sends the highest dailyTarget from any active step/walk challenge.

-- Drop the old function signature first so Postgres doesn't keep the 15-arg overload
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN, INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT);

CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id           TEXT,
    p_timezone           TEXT DEFAULT 'America/New_York',
    p_has_program        BOOLEAN DEFAULT FALSE,
    p_has_friends        BOOLEAN DEFAULT FALSE,
    p_has_challenge      BOOLEAN DEFAULT FALSE,
    p_step_goal          INT DEFAULT 10000,
    p_fitness_goal       TEXT DEFAULT 'general',
    p_is_subscriber      BOOLEAN DEFAULT FALSE,
    p_workout_streak     INT DEFAULT 0,
    p_total_workouts     INT DEFAULT 0,
    p_preferred_time     TEXT DEFAULT 'any',
    p_avg_duration       INT DEFAULT 45,
    p_has_weight_log     BOOLEAN DEFAULT FALSE,
    p_hydration_active   BOOLEAN DEFAULT FALSE,
    p_league_rank        INT DEFAULT 0,
    p_active_step_challenge_target INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := p_user_id::UUID;
    v_today         DATE;
    v_quest_count   INT;
    v_streak        RECORD;
    v_bonus_claimed BOOLEAN := FALSE;
    v_all_complete  BOOLEAN := FALSE;
    v_day_seed      INT;
    v_difficulty_profile TEXT;
    v_quest_keys    TEXT[] := '{}';
    v_pool_easy     TEXT[];
    v_pool_medium   TEXT[];
    v_pool_hard     TEXT[];
    v_completed_keys TEXT[];
    v_recent_keys   TEXT[];
    v_hour          INT;
    v_preferred     TEXT := COALESCE(p_preferred_time, 'any');
    v_total_wk      INT := COALESCE(p_total_workouts, 0);
    v_wk_streak     INT := COALESCE(p_workout_streak, 0);
    v_step_target   INT;
    v_step_keys     TEXT[] := ARRAY['walk_3k_steps','walk_5k_steps','walk_7500_steps','walk_10k_steps','hit_step_goal'];
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_hour  := EXTRACT(HOUR FROM now() AT TIME ZONE p_timezone)::INT;

    -- Day-seed for deterministic but varied selection
    v_day_seed := (EXTRACT(DOY FROM v_today)::INT * 7 + EXTRACT(YEAR FROM v_today)::INT) % 100;

    -- Difficulty profile
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

    -- Check if quests already exist for today
    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    IF v_quest_count = 0 THEN
        -- Get recently completed quest keys (last 3 days) to avoid repetition
        SELECT ARRAY_AGG(DISTINCT quest_key) INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '3 days'
          AND quest_date < v_today;
        v_recent_keys := COALESCE(v_recent_keys, '{}');

        -- Get completed quest keys (lifetime) for progressive unlock
        SELECT ARRAY_AGG(DISTINCT quest_key) INTO v_completed_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id AND is_completed = TRUE;
        v_completed_keys := COALESCE(v_completed_keys, '{}');

        -- Build pools based on eligibility
        SELECT ARRAY_AGG(quest_key) INTO v_pool_easy
        FROM quest_templates
        WHERE difficulty = 'easy'
          AND quest_key != ALL(v_recent_keys)
          AND (
              (category = 'workout')
              OR (category = 'social'    AND p_has_friends)
              OR (category = 'nutrition')
              OR (category = 'health')
              OR (category = 'challenge' AND p_has_challenge)
              OR (category = 'steps')
          );
        v_pool_easy := COALESCE(v_pool_easy, ARRAY['complete_workout']);

        SELECT ARRAY_AGG(quest_key) INTO v_pool_medium
        FROM quest_templates
        WHERE difficulty = 'medium'
          AND quest_key != ALL(v_recent_keys)
          AND (
              (category = 'workout')
              OR (category = 'social'    AND p_has_friends)
              OR (category = 'nutrition')
              OR (category = 'health')
              OR (category = 'challenge' AND p_has_challenge)
              OR (category = 'steps')
          );
        v_pool_medium := COALESCE(v_pool_medium, ARRAY['exercise_sets_10']);

        SELECT ARRAY_AGG(quest_key) INTO v_pool_hard
        FROM quest_templates
        WHERE difficulty = 'hard'
          AND quest_key != ALL(v_recent_keys)
          AND (
              (category = 'workout')
              OR (category = 'social'    AND p_has_friends)
              OR (category = 'nutrition')
              OR (category = 'health')
              OR (category = 'challenge' AND p_has_challenge)
              OR (category = 'steps')
          );
        v_pool_hard := COALESCE(v_pool_hard, ARRAY['complete_2_workouts']);

        -- Select quest keys based on difficulty profile
        IF v_difficulty_profile = 'easy_day' THEN
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed % array_length(v_pool_easy, 1))],
                v_pool_easy[1 + ((v_day_seed + 1) % array_length(v_pool_easy, 1))],
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))]
            ];
        ELSIF v_difficulty_profile = 'hard_day' THEN
            v_quest_keys := ARRAY[
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed % array_length(v_pool_hard, 1))],
                v_pool_medium[1 + ((v_day_seed + 2) % array_length(v_pool_medium, 1))]
            ];
        ELSE -- mixed_day
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed % array_length(v_pool_easy, 1))],
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed % array_length(v_pool_hard, 1))]
            ];
        END IF;

        -- Ensure streak record exists
        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        -- Insert quests — override step targets when an active step challenge exists
        INSERT INTO user_daily_quests (user_id, quest_date, quest_key, title, description, icon, category, target_value, target_unit, xp_reward, league_points, difficulty)
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN CASE
                        WHEN p_active_step_challenge_target >= 10000 THEN (p_active_step_challenge_target / 1000) || 'K Challenge Steps'
                        ELSE p_active_step_challenge_target::TEXT || ' Challenge Steps'
                    END
                ELSE qt.title
            END,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN 'Hit your ' || CASE
                        WHEN p_active_step_challenge_target >= 10000 THEN (p_active_step_challenge_target / 1000) || 'K'
                        ELSE p_active_step_challenge_target::TEXT
                    END || ' step challenge target'
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

    -- Update streak
    SELECT
        COALESCE(current_streak, 0) AS current_streak,
        COALESCE(longest_streak, 0) AS longest_streak,
        COALESCE(total_quests_completed, 0) AS total_completed_days
    INTO v_streak
    FROM user_quest_streaks
    WHERE user_id = v_user_id;

    IF NOT FOUND THEN
        SELECT 0 AS current_streak, 0 AS longest_streak, 0 AS total_completed_days
        INTO v_streak;
    END IF;

    -- Check if all quests are complete
    SELECT
        COUNT(*) = COUNT(*) FILTER (WHERE is_completed = TRUE) AND COUNT(*) > 0
    INTO v_all_complete
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    -- Check if bonus already claimed
    IF v_all_complete THEN
        SELECT bonus_claimed INTO v_bonus_claimed
        FROM user_daily_quests
        WHERE user_id = v_user_id AND quest_date = v_today
        LIMIT 1;
    END IF;

    -- Return the response
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
        'all_complete', v_all_complete,
        'bonus_xp', CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 50 ELSE 0 END,
        'bonus_league_points', CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 30 ELSE 0 END,
        'quest_date', v_today,
        'streak', COALESCE(v_streak.current_streak, 0),
        'longest_streak', COALESCE(v_streak.longest_streak, 0),
        'total_completed', COALESCE(v_streak.total_completed_days, 0),
        'difficulty_profile', v_difficulty_profile
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN, INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT) TO authenticated;
