-- Migration: Achievement/Badge system
-- Date: 2026-03-07
-- Reason: Add gamification achievements for user engagement

BEGIN;

-- ============================================================================
-- 1. ACHIEVEMENTS DEFINITION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS achievements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('workout', 'streak', 'social', 'nutrition', 'level', 'special')),
    threshold INT NOT NULL DEFAULT 1,
    xp_reward INT NOT NULL DEFAULT 0,
    rarity TEXT NOT NULL DEFAULT 'common' CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 2. USER ACHIEVEMENTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_achievements (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id UUID NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    progress INT NOT NULL DEFAULT 0,
    unlocked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, achievement_id)
);

ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own_achievements" ON user_achievements
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "users_select_friend_achievements" ON user_achievements
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM friendships
            WHERE status = 'accepted'
              AND ((requester_id = auth.uid() AND addressee_id = user_achievements.user_id)
                OR (requester_id = user_achievements.user_id AND addressee_id = auth.uid()))
        )
    );

CREATE INDEX IF NOT EXISTS idx_user_achievements_user ON user_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_achievements_unlocked ON user_achievements(user_id, unlocked_at) WHERE unlocked_at IS NOT NULL;

-- ============================================================================
-- 3. SEED ACHIEVEMENTS
-- ============================================================================

INSERT INTO achievements (key, title, description, icon, category, threshold, xp_reward, rarity, sort_order) VALUES
-- Workout achievements
('first_workout',       'First Rep',            'Complete your first workout',                      'dumbbell.fill',                    'workout', 1,   50,  'common',    10),
('workouts_10',         'Getting Started',      'Complete 10 workouts',                             'flame.fill',                       'workout', 10,  100, 'common',    20),
('workouts_50',         'Dedicated',            'Complete 50 workouts',                             'bolt.fill',                        'workout', 50,  250, 'uncommon',  30),
('workouts_100',        'Centurion',            'Complete 100 workouts',                            'star.fill',                        'workout', 100, 500, 'rare',      40),
('workouts_500',        'Iron Will',            'Complete 500 workouts',                            'trophy.fill',                      'workout', 500, 1000,'epic',      50),
('first_pr',            'New Heights',          'Set your first personal record',                   'arrow.up.circle.fill',             'workout', 1,   75,  'common',    60),
('early_bird',          'Early Bird',           'Complete a workout before 6am',                    'sunrise.fill',                     'workout', 1,   50,  'uncommon',  70),
('night_owl',           'Night Owl',            'Complete a workout after 10pm',                    'moon.stars.fill',                  'workout', 1,   50,  'uncommon',  80),
('weekend_warrior',     'Weekend Warrior',      'Work out on both Saturday and Sunday',             'calendar.badge.checkmark',         'workout', 1,   75,  'uncommon',  90),

-- Streak achievements
('streak_7',            'Week Warrior',         'Maintain a 7-day streak',                          'flame.fill',                       'streak',  7,   100, 'common',    100),
('streak_14',           'Fortnight Force',      'Maintain a 14-day streak',                         'flame.fill',                       'streak',  14,  200, 'uncommon',  110),
('streak_30',           'Monthly Machine',      'Maintain a 30-day streak',                         'flame.fill',                       'streak',  30,  500, 'rare',      120),
('streak_60',           'Two Month Titan',      'Maintain a 60-day streak',                         'flame.fill',                       'streak',  60,  750, 'epic',      130),
('streak_100',          'Unstoppable',          'Maintain a 100-day streak',                        'flame.fill',                       'streak',  100, 1500,'legendary', 140),

-- Social achievements
('first_friend',        'Social Starter',       'Add your first friend',                            'person.2.fill',                    'social',  1,   50,  'common',    200),
('friends_10',          'Squad Goals',          'Have 10 friends',                                  'person.3.fill',                    'social',  10,  150, 'uncommon',  210),
('first_challenge_won', 'Challenger',           'Win your first challenge',                         'trophy.fill',                      'social',  1,   100, 'common',    220),
('challenges_won_10',   'Champion',             'Win 10 challenges',                                'medal.fill',                       'social',  10,  300, 'rare',      230),
('first_workout_shared','Sharing is Caring',    'Share a workout with a friend',                    'square.and.arrow.up.fill',         'social',  1,   50,  'common',    240),
('reactions_sent_50',   'Hype Machine',         'Send 50 reactions to friends',                     'hands.clap.fill',                  'social',  50,  200, 'uncommon',  250),

-- Nutrition achievements
('first_meal_logged',   'Fuel Up',              'Log your first meal',                              'fork.knife',                       'nutrition',1,  50,  'common',    300),
('meals_logged_100',    'Nutrition Nerd',       'Log 100 meals',                                    'chart.bar.fill',                   'nutrition',100,250, 'uncommon',  310),
('logging_streak_7',    'Consistent Tracker',   'Log meals for 7 days straight',                    'checkmark.circle.fill',            'nutrition',7,  150, 'uncommon',  320),

-- Level achievements
('level_5',             'Rising Star',          'Reach Level 5',                                    'star.fill',                        'level',   5,   0,   'common',    400),
('level_10',            'Double Digits',        'Reach Level 10',                                   'star.circle.fill',                 'level',   10,  0,   'uncommon',  410),
('level_25',            'Veteran',              'Reach Level 25',                                   'crown.fill',                       'level',   25,  0,   'rare',      420),
('level_50',            'Legend',               'Reach Level 50',                                   'sparkles',                         'level',   50,  0,   'legendary', 430),

-- Special achievements
('quest_streak_7',      'Quest Master',         'Complete daily quests 7 days in a row',            'checklist',                        'special', 7,   200, 'rare',      500),
('all_muscle_groups',   'Full Body',            'Work every muscle group at least once',            'figure.strengthtraining.traditional','special',1,   300, 'rare',      510)
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- 4. UNLOCK ACHIEVEMENT RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION unlock_achievement(p_achievement_key TEXT, p_progress INT DEFAULT 1)
RETURNS TABLE (
    unlocked BOOLEAN,
    achievement_title TEXT,
    achievement_icon TEXT,
    achievement_rarity TEXT,
    xp_reward INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_achievement RECORD;
    v_user_achievement RECORD;
    new_progress INT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    SELECT * INTO v_achievement FROM achievements WHERE key = p_achievement_key;
    IF NOT FOUND THEN
        unlocked := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;
    
    -- Upsert user_achievement with progress
    INSERT INTO user_achievements (user_id, achievement_id, progress)
    VALUES (current_user_uuid, v_achievement.id, p_progress)
    ON CONFLICT (user_id, achievement_id) DO UPDATE
        SET progress = GREATEST(user_achievements.progress, EXCLUDED.progress)
    RETURNING * INTO v_user_achievement;
    
    new_progress := v_user_achievement.progress;
    
    -- Check if threshold met and not yet unlocked
    IF new_progress >= v_achievement.threshold AND v_user_achievement.unlocked_at IS NULL THEN
        UPDATE user_achievements
        SET unlocked_at = NOW()
        WHERE id = v_user_achievement.id;
        
        -- Award XP if any
        IF v_achievement.xp_reward > 0 THEN
            UPDATE user_profiles
            SET xp = COALESCE(xp, 0) + v_achievement.xp_reward
            WHERE id = current_user_uuid;
        END IF;
        
        unlocked := TRUE;
        achievement_title := v_achievement.title;
        achievement_icon := v_achievement.icon;
        achievement_rarity := v_achievement.rarity;
        xp_reward := v_achievement.xp_reward;
        RETURN NEXT;
        RETURN;
    END IF;
    
    unlocked := FALSE;
    achievement_title := v_achievement.title;
    achievement_icon := v_achievement.icon;
    achievement_rarity := v_achievement.rarity;
    xp_reward := 0;
    RETURN NEXT;
    RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION unlock_achievement(TEXT, INT) TO authenticated;

-- ============================================================================
-- 5. GET USER ACHIEVEMENTS RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_achievements(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (
    achievement_key TEXT,
    title TEXT,
    description TEXT,
    icon TEXT,
    category TEXT,
    threshold INT,
    xp_reward INT,
    rarity TEXT,
    progress INT,
    unlocked_at TIMESTAMPTZ,
    sort_order INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    target_user_id UUID;
BEGIN
    target_user_id := COALESCE(p_user_id, auth.uid());
    
    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    RETURN QUERY
    SELECT
        a.key AS achievement_key,
        a.title,
        a.description,
        a.icon,
        a.category,
        a.threshold,
        a.xp_reward,
        a.rarity,
        COALESCE(ua.progress, 0) AS progress,
        ua.unlocked_at,
        a.sort_order
    FROM achievements a
    LEFT JOIN user_achievements ua ON ua.achievement_id = a.id AND ua.user_id = target_user_id
    ORDER BY a.sort_order;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_achievements(UUID) TO authenticated;

COMMIT;
