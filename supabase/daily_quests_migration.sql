-- ============================================================================
-- DAILY QUESTS SYSTEM
-- Rotating daily challenges that give users bite-sized goals each day.
-- Quests reset at midnight (user's timezone). Completing all quests grants
-- a bonus. Drives daily engagement + feeds points into the Weekly League.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. quest_templates — The master list of possible daily quests
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quest_templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quest_key   TEXT UNIQUE NOT NULL,          -- e.g. 'complete_workout', 'log_meal'
    title       TEXT NOT NULL,                 -- "Complete a Workout"
    description TEXT NOT NULL,                 -- "Finish any workout today"
    icon        TEXT NOT NULL DEFAULT 'star.fill',  -- SF Symbol name
    category    TEXT NOT NULL DEFAULT 'general',    -- 'workout', 'nutrition', 'social', 'general'
    target_value INT NOT NULL DEFAULT 1,       -- How many to complete (1 workout, 2 meals, etc.)
    target_unit TEXT NOT NULL DEFAULT 'times',
    xp_reward   INT NOT NULL DEFAULT 25,       -- XP awarded on completion
    league_points INT NOT NULL DEFAULT 15,     -- League points awarded
    difficulty  TEXT NOT NULL DEFAULT 'easy',   -- 'easy', 'medium', 'hard'
    is_premium  BOOLEAN NOT NULL DEFAULT FALSE, -- Premium-only quest
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,  -- Can be selected for daily rotation
    weight      INT NOT NULL DEFAULT 10,        -- Selection weight (higher = more likely)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- 2. user_daily_quests — Today's assigned quests for each user
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_daily_quests (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    quest_date   DATE NOT NULL DEFAULT CURRENT_DATE,   -- The date these quests are for
    quest_key    TEXT NOT NULL,
    title        TEXT NOT NULL,
    description  TEXT NOT NULL,
    icon         TEXT NOT NULL,
    category     TEXT NOT NULL,
    target_value INT NOT NULL DEFAULT 1,
    current_value INT NOT NULL DEFAULT 0,
    target_unit  TEXT NOT NULL DEFAULT 'times',
    xp_reward    INT NOT NULL DEFAULT 25,
    league_points INT NOT NULL DEFAULT 15,
    difficulty   TEXT NOT NULL DEFAULT 'easy',
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    UNIQUE(user_id, quest_date, quest_key)
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_user_daily_quests_user_date 
    ON user_daily_quests(user_id, quest_date);
CREATE INDEX IF NOT EXISTS idx_user_daily_quests_completed 
    ON user_daily_quests(user_id, quest_date, is_completed);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. user_quest_streaks — Track daily quest completion streaks
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_quest_streaks (
    user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    current_streak  INT NOT NULL DEFAULT 0,
    longest_streak  INT NOT NULL DEFAULT 0,
    last_completed_date DATE,   -- Last date ALL quests were completed
    total_quests_completed INT NOT NULL DEFAULT 0,
    total_xp_earned INT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- 4. RLS Policies
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE quest_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_daily_quests ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quest_streaks ENABLE ROW LEVEL SECURITY;

-- quest_templates: readable by everyone
CREATE POLICY "quest_templates_select" ON quest_templates
    FOR SELECT USING (true);

-- user_daily_quests: users can only see/modify their own
CREATE POLICY "user_daily_quests_select" ON user_daily_quests
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_daily_quests_insert" ON user_daily_quests
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_daily_quests_update" ON user_daily_quests
    FOR UPDATE USING (auth.uid() = user_id);

-- user_quest_streaks: users can only see/modify their own
CREATE POLICY "user_quest_streaks_select" ON user_quest_streaks
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_quest_streaks_insert" ON user_quest_streaks
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_quest_streaks_update" ON user_quest_streaks
    FOR UPDATE USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Seed quest templates
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO quest_templates (quest_key, title, description, icon, category, target_value, target_unit, xp_reward, league_points, difficulty, weight) VALUES
    -- WORKOUT quests
    ('complete_workout',      'Complete a Workout',           'Finish any workout today',                          'dumbbell.fill',        'workout',   1, 'workout',   30, 20, 'easy',   20),
    ('complete_2_workouts',   'Double Down',                  'Complete 2 workouts today',                         'flame.fill',           'workout',   2, 'workouts',  60, 40, 'hard',    5),
    ('exercise_sets_10',      'Set Crusher',                  'Complete at least 10 sets in a single workout',     'repeat.circle.fill',   'workout',   10, 'sets',     25, 15, 'medium', 12),
    ('exercise_sets_20',      'Volume King',                  'Complete at least 20 sets in a single workout',     'chart.bar.fill',       'workout',   20, 'sets',     50, 30, 'hard',    6),
    ('workout_30_min',        '30-Minute Warrior',            'Complete a workout lasting 30+ minutes',            'timer',                'workout',   30, 'minutes',  35, 20, 'medium', 14),
    
    -- NUTRITION quests
    ('log_meal',              'Fuel Up',                      'Log at least 1 meal today',                         'fork.knife',           'nutrition', 1, 'meal',      20, 10, 'easy',   18),
    ('log_3_meals',           'Full Day Logging',             'Log 3 meals today',                                 'chart.pie.fill',       'nutrition', 3, 'meals',     40, 25, 'medium', 10),
    ('log_water',             'Stay Hydrated',                'Log at least 1 glass of water',                     'drop.fill',            'nutrition', 1, 'glass',     15, 10, 'easy',   16),
    ('hit_protein_goal',      'Protein Champion',             'Hit your daily protein goal',                       'bolt.fill',            'nutrition', 1, 'goal',      45, 25, 'hard',    8),
    
    -- SOCIAL quests
    ('send_challenge',        'Throw Down the Gauntlet',      'Send a challenge to a friend',                      'person.2.fill',        'social',    1, 'challenge', 25, 15, 'easy',   14),
    ('react_to_workout',      'Show Some Love',               'React to a friend''s workout',                      'heart.fill',           'social',    1, 'reaction',  15, 10, 'easy',   12),
    
    -- GENERAL / MISC quests
    ('hit_step_goal',         'Step It Up',                   'Hit your daily step goal',                          'figure.walk',          'general',   1, 'goal',      30, 20, 'medium', 12),
    ('log_weight',            'Track Your Progress',          'Log your weight today',                             'scalemass.fill',       'general',   1, 'entry',     15, 10, 'easy',   10),
    ('beat_personal_record',  'Break a Record',               'Beat a personal record on any exercise',            'trophy.fill',          'general',   1, 'PR',        50, 30, 'hard',    6)
ON CONFLICT (quest_key) DO NOTHING;

-- ════════════════════════════════════════════════════════════════════════════
-- RPC FUNCTIONS
-- ════════════════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────────────────
-- get_daily_quests(p_user_id, p_timezone)
-- Returns today's quests for the user. If none exist yet, assigns new ones.
-- Picks 3 quests (weighted random, max 1 hard per day).
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id  TEXT,
    p_timezone TEXT DEFAULT 'America/New_York'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   UUID := p_user_id::UUID;
    v_today     DATE;
    v_quest_count INT;
    v_streak    RECORD;
    v_bonus_claimed BOOLEAN := FALSE;
    v_all_complete BOOLEAN := FALSE;
BEGIN
    -- Determine "today" in user's timezone
    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    
    -- Check if quests already assigned for today
    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;
    
    -- If no quests assigned yet, pick 3 random ones
    IF v_quest_count = 0 THEN
        -- Insert 3 quests: weighted random, max 1 hard
        WITH ranked_quests AS (
            SELECT 
                qt.*,
                ROW_NUMBER() OVER (
                    PARTITION BY qt.difficulty 
                    ORDER BY random() * qt.weight DESC
                ) as rn,
                random() * qt.weight as sort_score
            FROM quest_templates qt
            WHERE qt.is_active = TRUE
              AND qt.is_premium = FALSE  -- TODO: include premium if user is premium
        ),
        -- Pick at most 1 hard quest
        hard_pick AS (
            SELECT * FROM ranked_quests 
            WHERE difficulty = 'hard' AND rn = 1
            LIMIT 1
        ),
        -- Pick easy/medium quests
        other_picks AS (
            SELECT * FROM ranked_quests
            WHERE difficulty IN ('easy', 'medium')
            ORDER BY sort_score DESC
        ),
        -- Combine: 1 hard (if available) + fill remaining from easy/medium
        final_picks AS (
            (SELECT * FROM hard_pick)
            UNION ALL
            (SELECT * FROM other_picks 
             WHERE quest_key NOT IN (SELECT quest_key FROM hard_pick)
             LIMIT 3 - (SELECT COUNT(*) FROM hard_pick))
        )
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon, 
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT 
            v_user_id, v_today, fp.quest_key, fp.title, fp.description, fp.icon,
            fp.category, fp.target_value, fp.target_unit, fp.xp_reward, fp.league_points, fp.difficulty
        FROM final_picks fp
        LIMIT 3;
        
        -- Ensure streak record exists
        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;
    END IF;
    
    -- Check if all quests are complete
    SELECT 
        (COUNT(*) = COUNT(*) FILTER (WHERE is_completed)) INTO v_all_complete
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;
    
    -- Get streak info
    SELECT * INTO v_streak
    FROM user_quest_streaks
    WHERE user_id = v_user_id;
    
    -- Build response
    RETURN json_build_object(
        'quests', (
            SELECT json_agg(
                json_build_object(
                    'id', q.id,
                    'quest_key', q.quest_key,
                    'title', q.title,
                    'description', q.description,
                    'icon', q.icon,
                    'category', q.category,
                    'target_value', q.target_value,
                    'current_value', q.current_value,
                    'target_unit', q.target_unit,
                    'xp_reward', q.xp_reward,
                    'league_points', q.league_points,
                    'difficulty', q.difficulty,
                    'is_completed', q.is_completed,
                    'completed_at', q.completed_at
                )
                ORDER BY 
                    CASE q.difficulty 
                        WHEN 'easy' THEN 1 
                        WHEN 'medium' THEN 2 
                        WHEN 'hard' THEN 3 
                    END
            )
            FROM user_daily_quests q
            WHERE q.user_id = v_user_id AND q.quest_date = v_today
        ),
        'all_complete', v_all_complete,
        'bonus_xp', CASE WHEN v_all_complete THEN 50 ELSE 0 END,
        'bonus_league_points', CASE WHEN v_all_complete THEN 30 ELSE 0 END,
        'quest_date', v_today,
        'streak', COALESCE(v_streak.current_streak, 0),
        'longest_streak', COALESCE(v_streak.longest_streak, 0),
        'total_completed', COALESCE(v_streak.total_quests_completed, 0)
    );
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- update_quest_progress(p_user_id, p_quest_key, p_increment, p_timezone)
-- Increments progress on a specific quest. Auto-completes if target reached.
-- Returns the updated quest + whether bonus was just unlocked.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_quest_progress(
    p_user_id   TEXT,
    p_quest_key TEXT,
    p_increment INT DEFAULT 1,
    p_timezone  TEXT DEFAULT 'America/New_York'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id       UUID := p_user_id::UUID;
    v_today         DATE;
    v_quest         RECORD;
    v_just_completed BOOLEAN := FALSE;
    v_all_complete   BOOLEAN := FALSE;
    v_bonus_unlocked BOOLEAN := FALSE;
    v_new_value      INT;
BEGIN
    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    
    -- Find the quest for today
    SELECT * INTO v_quest
    FROM user_daily_quests
    WHERE user_id = v_user_id 
      AND quest_date = v_today 
      AND quest_key = p_quest_key;
    
    -- If quest not found or already completed, return early
    IF v_quest IS NULL THEN
        RETURN json_build_object(
            'success', FALSE,
            'reason', 'quest_not_found',
            'quest_key', p_quest_key
        );
    END IF;
    
    IF v_quest.is_completed THEN
        RETURN json_build_object(
            'success', TRUE,
            'already_completed', TRUE,
            'quest_key', p_quest_key
        );
    END IF;
    
    -- Increment progress
    v_new_value := LEAST(v_quest.current_value + p_increment, v_quest.target_value);
    v_just_completed := (v_new_value >= v_quest.target_value);
    
    -- Update the quest
    UPDATE user_daily_quests
    SET current_value = v_new_value,
        is_completed = v_just_completed,
        completed_at = CASE WHEN v_just_completed THEN now() ELSE NULL END
    WHERE id = v_quest.id;
    
    -- If just completed, update streak tracking
    IF v_just_completed THEN
        -- Check if ALL quests for today are now complete
        SELECT 
            (COUNT(*) = COUNT(*) FILTER (WHERE is_completed OR id = v_quest.id))
        INTO v_all_complete
        FROM user_daily_quests
        WHERE user_id = v_user_id AND quest_date = v_today;
        
        -- Update quest streak
        UPDATE user_quest_streaks
        SET total_quests_completed = total_quests_completed + 1,
            total_xp_earned = total_xp_earned + v_quest.xp_reward,
            updated_at = now()
        WHERE user_id = v_user_id;
        
        -- If all quests complete, update daily streak
        IF v_all_complete THEN
            UPDATE user_quest_streaks
            SET current_streak = CASE 
                    WHEN last_completed_date = v_today - INTERVAL '1 day' THEN current_streak + 1
                    WHEN last_completed_date = v_today THEN current_streak  -- Already counted today
                    ELSE 1  -- Streak broken, start fresh
                END,
                longest_streak = GREATEST(
                    longest_streak, 
                    CASE 
                        WHEN last_completed_date = v_today - INTERVAL '1 day' THEN current_streak + 1
                        WHEN last_completed_date = v_today THEN current_streak
                        ELSE 1
                    END
                ),
                last_completed_date = v_today,
                total_xp_earned = total_xp_earned + 50,  -- Bonus XP for completing all
                updated_at = now()
            WHERE user_id = v_user_id;
            
            v_bonus_unlocked := TRUE;
        END IF;
    END IF;
    
    RETURN json_build_object(
        'success', TRUE,
        'quest_key', p_quest_key,
        'new_value', v_new_value,
        'target_value', v_quest.target_value,
        'just_completed', v_just_completed,
        'xp_reward', CASE WHEN v_just_completed THEN v_quest.xp_reward ELSE 0 END,
        'league_points', CASE WHEN v_just_completed THEN v_quest.league_points ELSE 0 END,
        'all_complete', v_all_complete,
        'bonus_unlocked', v_bonus_unlocked,
        'bonus_xp', CASE WHEN v_bonus_unlocked THEN 50 ELSE 0 END,
        'bonus_league_points', CASE WHEN v_bonus_unlocked THEN 30 ELSE 0 END
    );
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- get_quest_history(p_user_id, p_days)
-- Returns quest completion summary for the last N days.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_quest_history(
    p_user_id TEXT,
    p_days    INT DEFAULT 7
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := p_user_id::UUID;
BEGIN
    RETURN json_build_object(
        'days', (
            SELECT json_agg(day_data ORDER BY day_data->>'date' DESC)
            FROM (
                SELECT json_build_object(
                    'date', quest_date,
                    'total_quests', COUNT(*),
                    'completed', COUNT(*) FILTER (WHERE is_completed),
                    'total_xp', SUM(CASE WHEN is_completed THEN xp_reward ELSE 0 END),
                    'all_complete', (COUNT(*) = COUNT(*) FILTER (WHERE is_completed))
                ) as day_data
                FROM user_daily_quests
                WHERE user_id = v_user_id
                  AND quest_date >= CURRENT_DATE - (p_days || ' days')::INTERVAL
                GROUP BY quest_date
            ) sub
        ),
        'streak', (
            SELECT json_build_object(
                'current', COALESCE(current_streak, 0),
                'longest', COALESCE(longest_streak, 0),
                'total_completed', COALESCE(total_quests_completed, 0),
                'total_xp', COALESCE(total_xp_earned, 0)
            )
            FROM user_quest_streaks
            WHERE user_id = v_user_id
        )
    );
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- Grant execute permissions
-- ────────────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION get_daily_quests(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_quest_progress(TEXT, TEXT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_quest_history(TEXT, INT) TO authenticated;
