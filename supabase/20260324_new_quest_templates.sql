-- New metric-driven quest templates for progressive personalization
-- Adds 12 new quest types: workout-metric, health-metric, social-competitive, tracking/consistency

-- Add min_workouts column for progressive unlock gating
ALTER TABLE quest_templates
    ADD COLUMN IF NOT EXISTS min_workouts INT DEFAULT 0;

INSERT INTO quest_templates (quest_key, title, description, icon, category, target_value, target_unit, xp_reward, league_points, difficulty, weight, requires_context, fun_label, verification_type, min_workouts) VALUES

    -- Workout-metric quests
    ('beat_volume_pr',       'Volume Crusher',         'Beat your best total volume in a workout',       'flame.fill',           'workout',   1, 'workout',   50, 30, 'hard',   6,  NULL,           '🏆 New PR territory',          'auto',   21),
    ('maintain_streak',      'Streak Keeper',          'Keep your workout streak alive today',            'flame.fill',           'workout',   1, 'workout',   35, 20, 'medium', 12, NULL,           '🔥 Don''t break the chain',    'auto',   3),
    ('stretch_session',      'Stretch It Out',         'Complete a guided stretch session',               'figure.flexibility',   'workout',   1, 'workout',   20, 10, 'easy',   10, NULL,           '🧘 Recovery matters',          'auto',   0),

    -- Health-metric quests (HealthKit auto-tracked)
    ('active_minutes_30',    'Get Moving',             'Accumulate 30 active minutes today',             'figure.walk',          'steps',     30, 'minutes',  30, 15, 'medium', 10, NULL,           '🏃 Every minute counts',       'auto',   0),
    ('burn_300_calories',    'Calorie Torch',          'Burn 300 active calories today',                 'bolt.fill',            'steps',     300,'calories', 35, 20, 'medium', 8,  NULL,           '🔥 Light it up',               'auto',   6),
    ('sleep_7_hours',        'Sleep Champion',         'Get 7+ hours of quality sleep',                  'moon.fill',            'tracking',  7,  'hours',    25, 10, 'easy',   8,  NULL,           '😴 Rest is gains',             'auto',   0),

    -- Social-competitive quests
    ('beat_friend_steps',    'Step Showdown',          'Outpace a friend in steps today',                'figure.run',           'social',    1, 'goal',      40, 25, 'hard',   8,  'has_challenge','⚔️ Friendly fire',             'auto',   6),
    ('league_3_workouts',    'League Grinder',         'Log 3 workouts to climb the league',             'chart.bar.fill',       'workout',   3, 'workouts',  45, 30, 'hard',   6,  NULL,           '📈 Climb the ranks',           'auto',   21),
    ('top_3_league',         'Podium Finish',          'Finish top 3 in your league this week',          'medal.fill',           'social',    1, 'goal',      50, 35, 'hard',   4,  NULL,           '🥇 Glory awaits',              'auto',   50),

    -- Tracking/consistency quests
    ('log_all_macros',       'Macro Master',           'Log protein, carbs, and fat today',              'chart.pie.fill',       'nutrition', 3, 'meals',     30, 15, 'medium', 10, NULL,           '📊 Know your numbers',         'manual', 6),
    ('hydration_before_noon','Morning Hydration',      'Log 4 glasses of water before noon',             'drop.fill',            'nutrition', 4, 'glasses',   25, 10, 'medium', 8,  NULL,           '💧 Early bird drinks',         'manual', 0),
    ('weekly_weigh_in',      'Weekly Check-In',        'Log your weight this week',                      'scalemass.fill',       'tracking',  1, 'day',       20, 10, 'easy',   10, NULL,           '⚖️ Track the trend',          'manual', 0)

ON CONFLICT (quest_key) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    category = EXCLUDED.category,
    target_value = EXCLUDED.target_value,
    target_unit = EXCLUDED.target_unit,
    xp_reward = EXCLUDED.xp_reward,
    league_points = EXCLUDED.league_points,
    difficulty = EXCLUDED.difficulty,
    weight = EXCLUDED.weight,
    requires_context = EXCLUDED.requires_context,
    fun_label = EXCLUDED.fun_label,
    verification_type = EXCLUDED.verification_type,
    min_workouts = EXCLUDED.min_workouts;
