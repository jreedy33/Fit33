-- Adaptive quest selection: progressive unlock, anti-repetition, streak/time-of-day personalization
-- Replaces get_daily_quests with expanded parameters from client context

-- Drop ALL old overloads to prevent "could not choose the best candidate function" ambiguity.
-- The 2-arg version (original), 8-arg version (v2), and any partial-match signatures must go.
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT);
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT);
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN);

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
    p_league_rank        INT DEFAULT 0
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
    v_quest_cats    TEXT[] := '{}';
    v_rec           RECORD;
    v_recent_keys   TEXT[];
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    
    -- Check if quests already assigned for today
    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;
    
    IF v_quest_count = 0 THEN
    
        v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));
        
        -- Difficulty profile
        v_difficulty_profile := CASE (v_day_seed % 10)
            WHEN 0 THEN 'easy_day'
            WHEN 1 THEN 'easy_day'
            WHEN 2 THEN 'easy_day'
            WHEN 3 THEN 'easy_day'
            WHEN 4 THEN 'mixed_day'
            WHEN 5 THEN 'mixed_day'
            WHEN 6 THEN 'mixed_day'
            WHEN 7 THEN 'mixed_day'
            WHEN 8 THEN 'hard_day'
            WHEN 9 THEN 'hard_day'
        END;
        
        -- Anti-repetition: get quest keys from last 7 days
        SELECT COALESCE(array_agg(DISTINCT quest_key), '{}')
        INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '7 days'
          AND quest_date < v_today;
        
        -- Build quest pool with adaptive weights
        DROP TABLE IF EXISTS _daily_quest_pool;
        CREATE TEMP TABLE _daily_quest_pool ON COMMIT DROP AS
        SELECT 
            qt.quest_key,
            qt.category,
            qt.verification_type,
            GREATEST(
                (qt.weight
                -- Context boosts (existing)
                + CASE
                    WHEN qt.requires_context = 'has_program' AND p_has_program THEN 15
                    WHEN qt.requires_context = 'has_friends' AND p_has_friends THEN 10
                    WHEN qt.requires_context = 'has_challenge' AND p_has_challenge THEN 10
                    WHEN qt.requires_context = 'no_challenge' AND NOT p_has_challenge THEN 15
                    WHEN qt.requires_context = 'no_friends' AND NOT p_has_friends THEN 15
                    WHEN qt.quest_key IN ('hit_protein_goal', 'log_high_protein_meal')
                         AND (p_fitness_goal ILIKE '%muscle%' OR p_fitness_goal ILIKE '%gain%' OR p_fitness_goal ILIKE '%bulk%') THEN 8
                    WHEN qt.category = 'steps' AND (p_fitness_goal ILIKE '%lose%' OR p_fitness_goal ILIKE '%lean%' OR p_fitness_goal ILIKE '%cardio%') THEN 5
                    ELSE 0
                END
                -- Streak-aware boosts
                + CASE
                    WHEN qt.quest_key = 'maintain_streak' AND p_workout_streak >= 3 THEN 20
                    WHEN qt.quest_key = 'complete_workout' AND p_workout_streak = 0 THEN 10
                    ELSE 0
                END
                -- Time-of-day personalization
                + CASE
                    WHEN qt.quest_key = 'early_bird_workout' AND p_preferred_time = 'morning' THEN 10
                    WHEN qt.quest_key = 'early_bird_workout' AND p_preferred_time = 'evening' THEN -15
                    ELSE 0
                END
                -- Weight/hydration context
                + CASE
                    WHEN qt.quest_key IN ('log_weight', 'weekly_weigh_in') AND NOT p_has_weight_log THEN -20
                    WHEN qt.quest_key IN ('log_water_3', 'log_water_8', 'hydration_before_noon') AND NOT p_hydration_active THEN -20
                    ELSE 0
                END
                -- League context
                + CASE
                    WHEN qt.quest_key IN ('top_3_league', 'league_3_workouts') AND p_league_rank BETWEEN 1 AND 5 THEN 12
                    WHEN qt.quest_key = 'top_3_league' AND p_league_rank > 10 THEN -10
                    ELSE 0
                END
                )
                -- Anti-repetition penalty: quests seen in last 7 days get 30% weight
                * CASE
                    WHEN qt.quest_key = ANY(v_recent_keys) THEN 0.3
                    ELSE 1.0
                END
                -- Difficulty multiplier
                * CASE v_difficulty_profile
                    WHEN 'easy_day' THEN
                        CASE qt.difficulty WHEN 'easy' THEN 3 WHEN 'medium' THEN 2 WHEN 'hard' THEN 0 END
                    WHEN 'mixed_day' THEN
                        CASE qt.difficulty WHEN 'easy' THEN 2 WHEN 'medium' THEN 2 WHEN 'hard' THEN 1 END
                    WHEN 'hard_day' THEN
                        CASE qt.difficulty WHEN 'easy' THEN 1 WHEN 'medium' THEN 2 WHEN 'hard' THEN 3 END
                END,
                0
            ) AS final_weight
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          -- Progressive unlock: only show quests the user has earned
          AND COALESCE(qt.min_workouts, 0) <= p_total_workouts
          -- Context requirements
          AND (
              qt.requires_context IS NULL
              OR (qt.requires_context = 'has_program' AND p_has_program)
              OR (qt.requires_context = 'has_friends' AND p_has_friends)
              OR (qt.requires_context = 'has_challenge' AND p_has_challenge)
              OR (qt.requires_context = 'no_challenge' AND NOT p_has_challenge)
              OR (qt.requires_context = 'no_friends' AND NOT p_has_friends)
              OR (qt.requires_context = 'free_user' AND NOT p_is_subscriber)
          );
        
        -- SLOT 0: Guaranteed ad quest for free users
        IF NOT p_is_subscriber THEN
            IF EXISTS (SELECT 1 FROM _daily_quest_pool WHERE quest_key = 'watch_ads') THEN
                v_quest_keys := array_append(v_quest_keys, 'watch_ads');
                v_quest_cats := array_append(v_quest_cats, 'reward');
            END IF;
        END IF;
        
        -- SLOT 1: Guaranteed verified quest
        FOR v_rec IN (
            SELECT quest_key, category
            FROM _daily_quest_pool
            WHERE verification_type IN ('auto', 'social')
              AND final_weight > 0
              AND quest_key != 'watch_ads'
            ORDER BY random() * final_weight DESC
        ) LOOP
            EXIT WHEN COALESCE(array_length(v_quest_keys, 1), 0) >= 2;
            IF NOT (v_rec.category = ANY(v_quest_cats)) THEN
                v_quest_keys := array_append(v_quest_keys, v_rec.quest_key);
                v_quest_cats := array_append(v_quest_cats, v_rec.category);
                EXIT;
            END IF;
        END LOOP;
        
        -- SLOTS 2-3: Fill with category diversity
        FOR v_rec IN (
            SELECT quest_key, category
            FROM _daily_quest_pool
            WHERE final_weight > 0
            ORDER BY random() * final_weight DESC
        ) LOOP
            EXIT WHEN COALESCE(array_length(v_quest_keys, 1), 0) >= 3;
            IF NOT (v_rec.quest_key = ANY(v_quest_keys))
               AND NOT (v_rec.category = ANY(v_quest_cats)) THEN
                v_quest_keys := array_append(v_quest_keys, v_rec.quest_key);
                v_quest_cats := array_append(v_quest_cats, v_rec.category);
            END IF;
        END LOOP;
        
        -- Fallback: relax category constraint
        IF COALESCE(array_length(v_quest_keys, 1), 0) < 3 THEN
            FOR v_rec IN (
                SELECT quest_key, category
                FROM _daily_quest_pool
                WHERE final_weight > 0
                ORDER BY random() * final_weight DESC
            ) LOOP
                EXIT WHEN COALESCE(array_length(v_quest_keys, 1), 0) >= 3;
                IF NOT (v_rec.quest_key = ANY(v_quest_keys)) THEN
                    v_quest_keys := array_append(v_quest_keys, v_rec.quest_key);
                    v_quest_cats := array_append(v_quest_cats, v_rec.category);
                END IF;
            END LOOP;
        END IF;
        
        -- Insert selected quests
        INSERT INTO user_daily_quests (user_id, quest_key, quest_date, title, description, icon, category, target_value, target_unit, xp_reward, league_points, difficulty)
        SELECT
            v_user_id,
            qt.quest_key,
            v_today,
            qt.title,
            qt.description,
            qt.icon,
            qt.category,
            CASE
                WHEN qt.quest_key = 'hit_step_goal' THEN p_step_goal
                ELSE qt.target_value
            END,
            qt.target_unit,
            qt.xp_reward,
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
        v_streak := ROW(0, 0, 0);
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
