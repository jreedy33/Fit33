-- ============================================================================
-- DAILY QUESTS V2 — Actionable, Personalized, Fun
-- Replaces generic quests with specific, in-app actions that vary daily.
-- The quest picker now uses user context (active program, friends, challenges,
-- step goal, fitness goal) to surface RELEVANT quests.
-- Difficulty varies day-to-day: some batches are chill, some are spicy 🌶️
--
-- V2.1: GUARANTEED VERIFIED QUEST RULE
-- At least 1 of 3 daily quests must be "auto" (app-measured via HealthKit,
-- workout tracking, etc.) or "social" (in-app action like sending a challenge).
-- This ensures real measurable engagement every day — no batch of 3 can be
-- all manual-input quests (log meals, log water, log weight).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Schema additions for V2
-- ────────────────────────────────────────────────────────────────────────────

-- Context filter: which quests require a precondition to appear
ALTER TABLE quest_templates
    ADD COLUMN IF NOT EXISTS requires_context TEXT DEFAULT NULL;
    -- NULL = always available
    -- 'has_program' = user must have an active program
    -- 'has_friends' = user must have at least 1 friend
    -- 'has_challenge' = user must have an active challenge
    -- 'no_challenge' = user has NO active challenge (prompt them to start one)
    -- 'no_friends' = user has NO friends (prompt them to add one)

-- Flavor text shown as subtitle on quest card
ALTER TABLE quest_templates
    ADD COLUMN IF NOT EXISTS fun_label TEXT DEFAULT NULL;

-- Verification type: how the app verifies quest completion
-- 'auto'   = app measures it directly (HealthKit steps, workout tracker, PR detection, etc.)
-- 'social' = in-app social action the app can verify (send challenge, add friend, share, etc.)
-- 'manual' = user self-reports (log meals, log water, log weight — not independently verified)
ALTER TABLE quest_templates
    ADD COLUMN IF NOT EXISTS verification_type TEXT NOT NULL DEFAULT 'manual';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Seed V2 Quest Templates (38 specific, actionable quests)
--    Each quest is tagged with verification_type for the selection rule.
-- ────────────────────────────────────────────────────────────────────────────

-- Clear old templates (user_daily_quests references quest_key, not template id, so this is safe)
DELETE FROM quest_templates;

INSERT INTO quest_templates (quest_key, title, description, icon, category, target_value, target_unit, xp_reward, league_points, difficulty, weight, requires_context, fun_label, verification_type) VALUES

    -- ═══════════════════════════════════════════════════════════════════════
    -- 🏋️ WORKOUT — In-app workout actions (ALL auto-verified by app)
    -- ═══════════════════════════════════════════════════════════════════════
    ('complete_workout',        'Crush a Workout',              'Complete any workout today — no excuses!',             'dumbbell.fill',        'workout',   1, 'workout',   30, 20, 'easy',   22, NULL, '💪 Just show up', 'auto'),
    ('complete_program_day',    'Program Day',                  'Complete your next program day',                        'calendar.badge.checkmark', 'workout', 1, 'day',    40, 25, 'medium', 18, 'has_program', '📋 Stay on track', 'auto'),
    ('complete_2_workouts',     'Double Session',               'Knock out 2 workouts today — beast mode',              'flame.fill',           'workout',   2, 'workouts',  65, 40, 'hard',    5, NULL, '🔥 Two-a-day energy', 'auto'),
    ('workout_30_min',          '30-Min Grind',                 'Complete a workout lasting 30+ minutes',                'timer',                'workout',   30, 'minutes',  35, 22, 'medium', 14, NULL, '⏱️ Time under tension', 'auto'),
    ('exercise_sets_15',        'Set Machine',                  'Hit 15 total sets in a single workout',                'repeat.circle.fill',   'workout',   15, 'sets',     30, 18, 'medium', 12, NULL, '🔁 Volume day', 'auto'),
    ('exercise_sets_25',        'Volume King',                  'Absolutely demolish 25+ sets in one session',           'chart.bar.fill',       'workout',   25, 'sets',     55, 35, 'hard',    4, NULL, '👑 Go big or go home', 'auto'),
    ('try_new_exercise',        'Try Something New',            'Include an exercise you haven''t done in 2 weeks',      'sparkles',             'workout',   1, 'exercise', 25, 15, 'easy',   10, NULL, '✨ Mix it up', 'auto'),
    ('upper_body_workout',      'Upper Body Pump',              'Complete a workout focused on upper body',              'figure.arms.open',     'workout',   1, 'workout',  30, 20, 'easy',   10, NULL, '💪 Arms, chest, back', 'auto'),
    ('lower_body_workout',      'Never Skip Leg Day',           'Complete a workout focused on lower body',              'figure.walk',          'workout',   1, 'workout',  30, 20, 'easy',   10, NULL, '🦵 Quads, hams, glutes', 'auto'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 🥗 NUTRITION — Logging food, protein, hydration (manual user input)
    -- ═══════════════════════════════════════════════════════════════════════
    ('log_breakfast',           'Breakfast Check-in',           'Log your breakfast to start the day right',             'sunrise.fill',         'nutrition', 1, 'meal',      20, 12, 'easy',   20, NULL, '🌅 Morning fuel', 'manual'),
    ('log_lunch',               'Lunch Log',                    'Log your lunch — keep the nutrition streak alive',      'sun.max.fill',         'nutrition', 1, 'meal',      20, 12, 'easy',   16, NULL, '☀️ Midday check-in', 'manual'),
    ('log_dinner',              'Dinner Log',                   'Log your dinner before bed',                            'moon.stars.fill',      'nutrition', 1, 'meal',      20, 12, 'easy',   14, NULL, '🌙 End the day strong', 'manual'),
    ('log_3_meals',             'Full Day Fuel',                'Log breakfast, lunch, AND dinner today',                'chart.pie.fill',       'nutrition', 3, 'meals',     45, 28, 'medium', 12, NULL, '🍽️ Triple threat', 'manual'),
    ('log_snack',               'Snack Attack',                 'Log a snack — even small bites count!',                 'carrot.fill',          'nutrition', 1, 'snack',     15, 8,  'easy',   14, NULL, '🥕 Every bite matters', 'manual'),
    ('log_water_3',             'Hydration Station',            'Log 3 glasses of water today',                          'drop.fill',            'nutrition', 3, 'glasses',   25, 15, 'easy',   18, NULL, '💧 Drink up', 'manual'),
    ('log_water_8',             'Hydration Hero',               'Log 8 glasses of water — full daily intake',            'drop.triangle.fill',   'nutrition', 8, 'glasses',   45, 28, 'hard',    6, NULL, '🌊 Stay saturated', 'manual'),
    ('hit_protein_goal',        'Protein Mission',              'Hit your daily protein goal',                           'bolt.fill',            'nutrition', 1, 'goal',      50, 30, 'hard',    7, NULL, '⚡ Fuel the gains', 'manual'),
    ('log_high_protein_meal',   'Protein Packed Meal',          'Log a meal with 30g+ protein',                          'bolt.circle.fill',     'nutrition', 1, 'meal',      25, 15, 'medium', 12, NULL, '🥩 Get those macros', 'manual'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 🚶 STEPS & MOVEMENT — HealthKit auto-tracked (ALL auto-verified)
    -- ═══════════════════════════════════════════════════════════════════════
    ('walk_3k_steps',           'Easy Stroll',                  'Walk 3,000 steps — a short walk does wonders',          'figure.walk',          'steps',     3000, 'steps',  20, 12, 'easy',   18, NULL, '🚶 Just get moving', 'auto'),
    ('walk_5k_steps',           'Halfway There',                'Walk 5,000 steps today',                                'figure.walk.motion',   'steps',     5000, 'steps',  30, 18, 'medium', 16, NULL, '👟 Solid effort', 'auto'),
    ('walk_7500_steps',         '7.5K Push',                    'Walk 7,500 steps — push a bit further',                 'figure.walk.diamond.fill', 'steps', 7500, 'steps',  40, 25, 'medium', 10, NULL, '🏃 Challenge yourself', 'auto'),
    ('hit_step_goal',           'Step Goal Crusher',            'Hit your personal daily step goal',                     'figure.run',           'steps',     1, 'goal',      50, 30, 'hard',    8, NULL, '🎯 Full goal achieved', 'auto'),
    ('walk_10k_steps',          '10K Day',                      'Walk 10,000 steps — a proper active day',               'figure.run.circle.fill', 'steps', 10000, 'steps',  55, 35, 'hard',    5, NULL, '🏆 Legendary status', 'auto'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 👥 SOCIAL — Engage with friends, challenges, community (ALL social-verified)
    -- ═══════════════════════════════════════════════════════════════════════
    ('send_challenge',          'Challenge a Friend',           'Send a challenge to a friend — any type!',              'person.2.fill',        'social',    1, 'challenge', 30, 18, 'easy',   14, 'has_friends', '🤝 Friendly competition', 'social'),
    ('start_1v1_challenge',     'Start a 1v1',                  'Start a new 1v1 challenge with a friend',               'figure.fencing',       'social',    1, 'challenge', 35, 22, 'medium', 10, 'has_friends', '⚔️ Throw down', 'social'),
    ('react_to_workout',        'Hype Your Friend',             'React to a friend''s workout — spread the love',        'heart.fill',           'social',    1, 'reaction',  15, 10, 'easy',   14, 'has_friends', '❤️ Be the hype squad', 'social'),
    ('invite_friend',           'Invite a Friend',              'Invite a friend to join Fit33',                         'person.badge.plus',    'social',    1, 'invite',    40, 25, 'medium', 10, NULL, '📱 Grow the squad', 'social'),
    ('add_friend',              'Make a New Friend',            'Send a friend request to someone new',                  'person.crop.circle.badge.plus', 'social', 1, 'request', 25, 15, 'easy', 10, 'no_friends', '👋 Connect with someone', 'social'),
    ('start_first_challenge',   'Start Your First Challenge',   'Kick off a challenge with a friend',                    'flag.fill',            'social',    1, 'challenge', 40, 25, 'medium', 12, 'no_challenge', '🏁 Let the games begin', 'social'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 📊 TRACKING — Log body stats, check progress (mixed verification)
    -- ═══════════════════════════════════════════════════════════════════════
    ('log_weight',              'Weigh In',                     'Log your weight today — consistency is key',            'scalemass.fill',       'tracking',  1, 'entry',     20, 12, 'easy',   12, NULL, '⚖️ Track the trend', 'manual'),
    ('check_progress',          'Check Your Stats',             'View your workout history or progress charts',          'chart.xyaxis.line',    'tracking',  1, 'view',      10, 8,  'easy',   10, NULL, '📈 See how far you''ve come', 'manual'),
    ('beat_personal_record',    'Break a PR',                   'Beat a personal record on any exercise',                'trophy.fill',          'tracking',  1, 'PR',        60, 40, 'hard',    4, NULL, '🏆 Smash your limits', 'auto'),
    ('log_cardio',              'Log a Cardio Session',         'Complete and log any cardio activity',                   'heart.circle.fill',    'tracking',  1, 'session',   30, 18, 'medium', 10, NULL, '❤️‍🔥 Get that heart rate up', 'auto'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 🌟 FUN / WILDCARD — Rare, spicy, bonus-feeling quests
    -- ═══════════════════════════════════════════════════════════════════════
    ('perfect_day',             'Perfect Day',                  'Log a workout AND 3 meals AND hit step goal — the trifecta', 'star.circle.fill', 'wildcard', 3, 'actions', 80, 50, 'hard', 3, NULL, '⭐ The ultimate day', 'auto'),
    ('early_bird_workout',      'Early Bird',                   'Complete a workout before noon',                        'sunrise.circle.fill',  'wildcard',  1, 'workout',  35, 22, 'medium', 8, NULL, '🐦 Rise and grind', 'auto'),
    ('share_workout',           'Share the Gains',              'Share a completed workout with a friend',               'square.and.arrow.up.fill', 'social', 1, 'share',  20, 12, 'easy',   10, 'has_friends', '📤 Show off a little', 'social'),
    ('favorite_a_workout',      'Save a Banger',                'Mark a completed workout as a favorite',                'heart.text.clipboard.fill', 'tracking', 1, 'workout', 15, 8, 'easy', 8, NULL, '⭐ Save it for later', 'manual'),

    -- ═══════════════════════════════════════════════════════════════════════
    -- 📺 REWARD — Support the app by watching a short video (FREE users only)
    -- ═══════════════════════════════════════════════════════════════════════
    ('watch_ads',               'Support Fit33',                'Watch 2 short videos to support the app — thank you!', 'play.rectangle.fill',  'reward',    2, 'videos',   25, 15, 'easy',  30, 'free_user', '📺 Quick & easy', 'auto')

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
    verification_type = EXCLUDED.verification_type;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. REPLACE get_daily_quests() with context-aware V2.1
--    Now accepts user context to pick RELEVANT quests.
--    Uses a "daily seed" so the same user gets the same quests if they re-open the app,
--    but different quests each day.
--    Ensures variety: no two quests from the same category, and difficulty mix varies.
--
--    ★ GUARANTEED VERIFIED QUEST RULE ★
--    At least 1 of the 3 quests must be verification_type = 'auto' OR 'social'.
--    This ensures the user is truly engaging — not just tapping "log" buttons.
--    Auto = app measures it (steps, workout duration, sets, PR, etc.)
--    Social = in-app social action (send challenge, add friend, share workout)
--    Exception: social quests count as verified (user's stated rule).
-- ────────────────────────────────────────────────────────────────────────────

-- Drop old function signatures to avoid overload conflicts
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT);
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id       TEXT,
    p_timezone       TEXT DEFAULT 'America/New_York',
    p_has_program    BOOLEAN DEFAULT FALSE,
    p_has_friends    BOOLEAN DEFAULT FALSE,
    p_has_challenge  BOOLEAN DEFAULT FALSE,
    p_step_goal      INT DEFAULT 10000,
    p_fitness_goal   TEXT DEFAULT 'general',
    p_is_subscriber  BOOLEAN DEFAULT FALSE
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
    v_difficulty_profile TEXT;  -- 'easy_day', 'mixed_day', 'hard_day'
    -- Procedural quest selection
    v_quest_keys    TEXT[] := '{}';
    v_quest_cats    TEXT[] := '{}';
    v_rec           RECORD;
BEGIN
    -- Determine "today" in user's timezone
    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    
    -- Check if quests already assigned for today
    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;
    
    -- If no quests assigned yet, pick 3 context-aware quests
    IF v_quest_count = 0 THEN
    
        -- Generate a daily seed for pseudo-random but deterministic selection
        -- Same user + same day = same seed (so quests don't change on re-open)
        v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));
        
        -- Pick a "difficulty profile" for the day — adds variety
        -- ~40% easy days, ~40% mixed days, ~20% hard days
        v_difficulty_profile := CASE (v_day_seed % 10)
            WHEN 0 THEN 'easy_day'    -- All easy/medium
            WHEN 1 THEN 'easy_day'
            WHEN 2 THEN 'easy_day'
            WHEN 3 THEN 'easy_day'
            WHEN 4 THEN 'mixed_day'   -- 1 easy, 1 medium, 1 hard
            WHEN 5 THEN 'mixed_day'
            WHEN 6 THEN 'mixed_day'
            WHEN 7 THEN 'mixed_day'
            WHEN 8 THEN 'hard_day'    -- Medium + hard heavy
            WHEN 9 THEN 'hard_day'
        END;
        
        -- ═══════════════════════════════════════════════════════════════════
        -- Build quest pool: eligible quests with difficulty-adjusted weights
        -- ═══════════════════════════════════════════════════════════════════
        DROP TABLE IF EXISTS _daily_quest_pool;
        CREATE TEMP TABLE _daily_quest_pool ON COMMIT DROP AS
        SELECT 
            qt.quest_key,
            qt.category,
            qt.verification_type,
            -- Final weight = (base_weight + context_boost) × difficulty_multiplier
            GREATEST(
                (qt.weight + CASE
                    -- Boost program quests if user has a program
                    WHEN qt.requires_context = 'has_program' AND p_has_program THEN 15
                    -- Boost social quests if user has friends
                    WHEN qt.requires_context = 'has_friends' AND p_has_friends THEN 10
                    -- Boost challenge quests if user has active challenges
                    WHEN qt.requires_context = 'has_challenge' AND p_has_challenge THEN 10
                    -- Boost "start challenge" if user has no challenge
                    WHEN qt.requires_context = 'no_challenge' AND NOT p_has_challenge THEN 15
                    -- Boost "add friend" if user has no friends
                    WHEN qt.requires_context = 'no_friends' AND NOT p_has_friends THEN 15
                    -- Slight boost for protein quests if user is building muscle
                    WHEN qt.quest_key IN ('hit_protein_goal', 'log_high_protein_meal') 
                         AND (p_fitness_goal ILIKE '%muscle%' OR p_fitness_goal ILIKE '%gain%' OR p_fitness_goal ILIKE '%bulk%') THEN 8
                    -- Slight boost for step quests if user has a step-related goal
                    WHEN qt.category = 'steps' AND (p_fitness_goal ILIKE '%lose%' OR p_fitness_goal ILIKE '%lean%' OR p_fitness_goal ILIKE '%cardio%') THEN 5
                    ELSE 0
                END)
                *
                CASE v_difficulty_profile
                    WHEN 'easy_day' THEN
                        CASE qt.difficulty
                            WHEN 'easy'   THEN 3
                            WHEN 'medium' THEN 2
                            WHEN 'hard'   THEN 0  -- No hard on easy days
                        END
                    WHEN 'mixed_day' THEN
                        CASE qt.difficulty
                            WHEN 'easy'   THEN 2
                            WHEN 'medium' THEN 2
                            WHEN 'hard'   THEN 1
                        END
                    WHEN 'hard_day' THEN
                        CASE qt.difficulty
                            WHEN 'easy'   THEN 1
                            WHEN 'medium' THEN 2
                            WHEN 'hard'   THEN 3
                        END
                END,
                0
            ) AS final_weight
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          -- Filter out quests whose context requirements are NOT met
          AND (
              qt.requires_context IS NULL
              OR (qt.requires_context = 'has_program' AND p_has_program)
              OR (qt.requires_context = 'has_friends' AND p_has_friends)
              OR (qt.requires_context = 'has_challenge' AND p_has_challenge)
              OR (qt.requires_context = 'no_challenge' AND NOT p_has_challenge)
              OR (qt.requires_context = 'no_friends' AND NOT p_has_friends)
              OR (qt.requires_context = 'free_user' AND NOT p_is_subscriber)
          );
        
        -- ═══════════════════════════════════════════════════════════════════
        -- ★ SLOT 0 (FREE USERS ONLY): GUARANTEED AD QUEST
        -- Free users ALWAYS get the watch_ads quest. It's auto-verified
        -- and occupies the 'reward' category, so it won't conflict with
        -- other categories. This slot is reserved before the normal
        -- selection runs, leaving 2 slots for the regular algorithm.
        -- ═══════════════════════════════════════════════════════════════════
        IF NOT p_is_subscriber THEN
            -- Check that watch_ads is in the pool (it should be for free users)
            IF EXISTS (SELECT 1 FROM _daily_quest_pool WHERE quest_key = 'watch_ads') THEN
                v_quest_keys := array_append(v_quest_keys, 'watch_ads');
                v_quest_cats := array_append(v_quest_cats, 'reward');
            END IF;
        END IF;
        
        -- ═══════════════════════════════════════════════════════════════════
        -- ★ SLOT 1: GUARANTEED VERIFIED QUEST
        -- Must be 'auto' (app-measured) or 'social' (in-app action).
        -- This is the core engagement rule — ensures at least one quest
        -- that proves the user actually did something the app can verify.
        -- (Skipped if ad quest already fills this role for free users.)
        -- ═══════════════════════════════════════════════════════════════════
        FOR v_rec IN (
            SELECT quest_key, category
            FROM _daily_quest_pool
            WHERE verification_type IN ('auto', 'social')
              AND final_weight > 0
              AND quest_key != 'watch_ads'  -- Already assigned above if free user
            ORDER BY random() * final_weight DESC
        ) LOOP
            EXIT WHEN COALESCE(array_length(v_quest_keys, 1), 0) >= 2;
            -- Pick the first one that doesn't conflict with already-chosen categories
            IF NOT (v_rec.category = ANY(v_quest_cats)) THEN
                v_quest_keys := array_append(v_quest_keys, v_rec.quest_key);
                v_quest_cats := array_append(v_quest_cats, v_rec.category);
                EXIT;  -- Got our guaranteed verified quest
            END IF;
        END LOOP;
        
        -- ═══════════════════════════════════════════════════════════════════
        -- SLOTS 2-3: Fill from the full pool (can be any verification_type)
        -- Maintain category diversity — no two quests from the same category
        -- ═══════════════════════════════════════════════════════════════════
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
        
        -- Fallback: if we couldn't get 3 with unique categories, relax the constraint
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
        
        -- ═══════════════════════════════════════════════════════════════════
        -- Insert the selected quests into user_daily_quests
        -- ═══════════════════════════════════════════════════════════════════
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id, v_today, qt.quest_key, qt.title, qt.description, qt.icon,
            qt.category, qt.target_value, qt.target_unit, qt.xp_reward, qt.league_points, qt.difficulty
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys);
        
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
    
    -- Build response (includes fun_label + verification_type from templates)
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
                    'completed_at', q.completed_at,
                    'fun_label', qt.fun_label,
                    'verification_type', COALESCE(qt.verification_type, 'manual')
                )
                ORDER BY 
                    CASE q.difficulty 
                        WHEN 'easy' THEN 1 
                        WHEN 'medium' THEN 2 
                        WHEN 'hard' THEN 3 
                    END
            )
            FROM user_daily_quests q
            LEFT JOIN quest_templates qt ON qt.quest_key = q.quest_key
            WHERE q.user_id = v_user_id AND q.quest_date = v_today
        ),
        'all_complete', v_all_complete,
        'bonus_xp', CASE WHEN v_all_complete THEN 50 ELSE 0 END,
        'bonus_league_points', CASE WHEN v_all_complete THEN 30 ELSE 0 END,
        'quest_date', v_today,
        'streak', COALESCE(v_streak.current_streak, 0),
        'longest_streak', COALESCE(v_streak.longest_streak, 0),
        'total_completed', COALESCE(v_streak.total_quests_completed, 0),
        'difficulty_profile', v_difficulty_profile
    );
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Grant execute permissions (function signature changed, re-grant)
-- ────────────────────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN) TO authenticated;

-- update_quest_progress stays the same — it's already generic enough
-- get_quest_history stays the same
