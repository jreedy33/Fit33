-- =============================================================================
-- Sprint 7 — Security + realtime hygiene (2026-04-26)
-- =============================================================================
-- Consolidated migration covering Q2-72, Q2-73, and a deprecation comment on
-- superseded realtime-publication adds (Q2-96 — the actual file edits are done
-- in the two March 7 realtime files directly; the Q2-95 doc-only cleanup to
-- 20260324_adaptive_quest_selection.sql is also a direct file edit).
--
--   Q2-72: Insert the canonical IDOR guard into the three remaining
--          SECURITY DEFINER RPCs that accept a `p_user_id` parameter:
--            - get_daily_quests(TEXT, TEXT, ...)
--            - get_or_join_weekly_league(UUID)
--            - get_league_leaderboard(UUID, UUID)
--          Guard pattern matches 20260417_secure_get_friend_ids.sql and
--          20260425_secure_definer_rpc_idor_fixes.sql:
--            IF auth.uid() IS NOT NULL AND <user_param> <> auth.uid()
--              THEN RAISE EXCEPTION ... USING ERRCODE = '42501';
--          Non-auth callers (service_role / pg_cron, auth.uid() IS NULL)
--          remain unrestricted so internal cleanup + auto-placement keep
--          working. Per supabase-rules §12, every historical overload is
--          DROPped first before recreating at the latest signature.
--
--   Q2-73: Add `private_challenge_chat` to the `supabase_realtime`
--          publication. `private_challenges_migration.sql` set
--          REPLICA IDENTITY FULL on the table, and
--          `fix_private_realtime_publication.sql` added the siblings
--          (members, daily_progress, invites, private_challenges), but NOT
--          chat — so moderation UPDATEs are currently silently dropped at
--          the client. Idempotent via `EXCEPTION WHEN duplicate_object`.
--
-- Rollout notes
--   - Safe to re-run (every DDL is idempotent).
--   - The client always calls these RPCs with its own UserManager-provided
--     UUID, so the additional guard only fires if a client bug / malicious
--     caller tries to pass someone else's id. Expected blast radius in prod
--     is zero; the function now 42501s instead of returning other users'
--     data.
-- =============================================================================

BEGIN;

-- =============================================================================
-- Q2-72.1: get_daily_quests — IDOR guard on p_user_id (TEXT → compare against
--          auth.uid()::text). Drops every historical overload first.
-- =============================================================================

-- Sweep historical overloads (2-arg through 19-arg variants seen across
-- daily_quests_migration.sql, daily_quests_v2_migration.sql, 20260324, 20260325
-- quest_challenge_sync / fix_quest_streak_record, 20260420, 20260421, 20260422,
-- 20260423 smart hierarchy).
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT);
DROP FUNCTION IF EXISTS get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT
);
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
    v_slot3_category         TEXT;
    v_category_ladder        TEXT[];
    v_swap_candidate         TEXT;
    v_i                      INT;
    v_distinct_cats          INT;
BEGIN
    -- IDOR guard: authenticated callers must ask for their own quests only.
    -- service_role / pg_cron contexts (auth.uid() IS NULL) remain unrestricted.
    IF auth.uid() IS NOT NULL AND v_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot read another user''s quests'
            USING ERRCODE = '42501';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

    -- Slot 1 preferred key
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
        ELSE
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed   % array_length(v_pool_easy,   1))],
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed   % array_length(v_pool_hard,   1))]
            ];
        END IF;

        IF v_preferred_workout_key IS NOT NULL
           AND EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_preferred_workout_key AND is_active)
           AND v_preferred_workout_key <> ALL(v_quest_keys) THEN
            v_quest_keys[1] := v_preferred_workout_key;
        END IF;

        v_slot1_is_steps := v_quest_keys[1] IN ('hit_step_goal', 'walk_10k_steps');

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

        IF NOT p_is_subscriber
           AND array_length(v_challenge_quest_keys, 1) IS NULL
           AND EXISTS (SELECT 1 FROM _eligible_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

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

COMMENT ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[]
) IS
  'Returns today''s daily quests for the caller. IDOR-guarded 2026-04-26: authenticated callers must pass their own user id.';

GRANT EXECUTE ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[]
) TO authenticated;

-- =============================================================================
-- Q2-72.2: get_or_join_weekly_league — IDOR guard on p_user_id (UUID).
--          Preserves Monday-only placement (20260331_league_auto_placement.sql)
--          and all privacy / Bronze reshuffle / friend-overlap / block / hidden
--          user / verified / gold_verified behavior.
-- =============================================================================

DROP FUNCTION IF EXISTS get_or_join_weekly_league(UUID);

CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_start DATE;
    v_user_tier INTEGER;
    v_group_id UUID;
    v_membership_id UUID;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
    v_best_group_id UUID;
    v_best_overlap INTEGER := -1;
    v_candidate RECORD;
    v_overlap INTEGER;
    v_prev_group_id UUID;
    v_least_stale_overlap INTEGER := 999;
    v_stale_count INTEGER;
    v_hide_league BOOLEAN;
    v_is_monday BOOLEAN;
    v_new_member_id UUID;
BEGIN
    -- IDOR guard: authenticated callers must ask for their own league only.
    -- pg_cron / service_role bypass (they run auto_place_all_league_members).
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot join or read another user''s league'
            USING ERRCODE = '42501';
    END IF;

    SELECT COALESCE(up.privacy_hide_league, FALSE) INTO v_hide_league
    FROM user_profiles up WHERE up.id = p_user_id;

    IF COALESCE(v_hide_league, FALSE) THEN
        RETURN json_build_object('hidden', true);
    END IF;

    PERFORM process_past_league_weeks();

    v_week_start := get_current_week_monday();
    v_days_remaining := 6 - (CURRENT_DATE - v_week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    v_is_monday := (EXTRACT(ISODOW FROM CURRENT_DATE) = 1);

    INSERT INTO user_league_tier (user_id, current_tier)
    VALUES (p_user_id, 1)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT current_tier INTO v_user_tier
    FROM user_league_tier WHERE user_id = p_user_id;

    SELECT lm.id, lm.group_id
    INTO v_membership_id, v_group_id
    FROM league_members lm
    JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id
      AND lg.week_start = v_week_start;

    IF v_membership_id IS NULL AND NOT v_is_monday THEN
        SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;
        RETURN json_build_object(
            'not_placed', true,
            'tier_rank', v_user_tier,
            'tier_name', v_tier_info.name,
            'tier_emoji', v_tier_info.emoji,
            'tier_color', v_tier_info.color_hex,
            'week_start', v_week_start,
            'days_remaining', v_days_remaining,
            'next_week_start', v_week_start + 7
        );
    END IF;

    IF v_membership_id IS NULL THEN

        IF v_user_tier = 1 THEN
            SELECT lm.group_id INTO v_prev_group_id
            FROM league_members lm
            JOIN league_groups lg ON lg.id = lm.group_id
            WHERE lm.user_id = p_user_id
              AND lg.week_start = v_week_start - INTERVAL '7 days'
            LIMIT 1;

            IF v_prev_group_id IS NOT NULL THEN
                FOR v_candidate IN
                    SELECT lg.id, lg.member_count
                    FROM league_groups lg
                    WHERE lg.tier_rank = 1
                      AND lg.week_start = v_week_start
                      AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = 1)
                      AND NOT lg.is_processed
                      AND NOT EXISTS (
                          SELECT 1 FROM league_members lm_blk
                          JOIN user_blocks ub ON (
                              (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                              OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                          )
                          WHERE lm_blk.group_id = lg.id
                      )
                    ORDER BY random()
                LOOP
                    SELECT COUNT(*)::INT INTO v_stale_count
                    FROM league_members lm_cur
                    JOIN league_members lm_prev ON lm_prev.user_id = lm_cur.user_id
                    WHERE lm_cur.group_id = v_candidate.id
                      AND lm_prev.group_id = v_prev_group_id;

                    IF v_stale_count < v_least_stale_overlap THEN
                        v_least_stale_overlap := v_stale_count;
                        v_best_group_id := v_candidate.id;
                    END IF;

                    IF v_stale_count = 0 THEN EXIT; END IF;
                END LOOP;

                v_group_id := v_best_group_id;
            ELSE
                SELECT lg.id INTO v_group_id
                FROM league_groups lg
                WHERE lg.tier_rank = 1
                  AND lg.week_start = v_week_start
                  AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = 1)
                  AND NOT lg.is_processed
                  AND NOT EXISTS (
                      SELECT 1 FROM league_members lm_blk
                      JOIN user_blocks ub ON (
                          (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY random()
                LIMIT 1;
            END IF;

        ELSE
            FOR v_candidate IN
                SELECT lg.id, lg.member_count
                FROM league_groups lg
                WHERE lg.tier_rank = v_user_tier
                  AND lg.week_start = v_week_start
                  AND lg.member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
                  AND NOT lg.is_processed
                  AND NOT EXISTS (
                      SELECT 1 FROM league_members lm_blk
                      JOIN user_blocks ub ON (
                          (ub.blocker_id = p_user_id AND ub.blocked_id = lm_blk.user_id)
                          OR (ub.blocker_id = lm_blk.user_id AND ub.blocked_id = p_user_id)
                      )
                      WHERE lm_blk.group_id = lg.id
                  )
                ORDER BY lg.member_count DESC
            LOOP
                SELECT COUNT(*)::INT INTO v_overlap
                FROM league_members lm2
                JOIN friendships f ON (
                    (f.requester_id = p_user_id AND f.addressee_id = lm2.user_id)
                    OR (f.addressee_id = p_user_id AND f.requester_id = lm2.user_id)
                )
                WHERE lm2.group_id = v_candidate.id
                  AND f.status = 'accepted';

                IF v_overlap > v_best_overlap THEN
                    v_best_overlap := v_overlap;
                    v_best_group_id := v_candidate.id;
                END IF;
            END LOOP;

            v_group_id := v_best_group_id;
        END IF;

        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        INSERT INTO league_members (user_id, group_id, points)
        VALUES (p_user_id, v_group_id, 0)
        ON CONFLICT (user_id, group_id) DO NOTHING
        RETURNING id INTO v_new_member_id;

        IF v_new_member_id IS NOT NULL THEN
            UPDATE league_groups SET member_count = member_count + 1
            WHERE id = v_group_id;
        END IF;
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;

    WITH my_friends AS (
        SELECT CASE WHEN requester_id = p_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships
        WHERE (requester_id = p_user_id OR addressee_id = p_user_id) AND status = 'accepted'
    )
    SELECT json_build_object(
        'group_id', v_group_id,
        'tier_rank', v_user_tier,
        'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji,
        'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count,
        'relegation_count', v_tier_info.relegation_count,
        'week_start', v_week_start,
        'days_remaining', v_days_remaining,
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (
            SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members lm2 LEFT JOIN user_profiles up2 ON up2.id = lm2.user_id
            WHERE lm2.group_id = v_group_id AND NOT COALESCE(up2.privacy_hide_league, FALSE)
        ) sub WHERE user_id = p_user_id), 1),
        'group_size', (SELECT member_count FROM league_groups WHERE id = v_group_id),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username,
                CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END AS profile_photo_url,
                lm.points, lm.workouts_completed,
                ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                (lm.user_id = p_user_id) AS is_current_user,
                (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                CASE
                    WHEN lm.user_id = p_user_id THEN NULL
                    WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                    ELSE (SELECT COUNT(DISTINCT mf.fid)::INT FROM my_friends mf
                        JOIN friendships f3 ON ((f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                            OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id))
                        WHERE f3.status = 'accepted')
                END AS mutual_friend_count,
                (COALESCE(up.is_verified, FALSE)
                 OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7
                ) AS is_verified,
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified
            FROM league_members lm
            LEFT JOIN user_profiles up ON up.id = lm.user_id
            WHERE lm.group_id = v_group_id
              AND NOT COALESCE(up.privacy_hide_league, FALSE)
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub
                  WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id)
                     OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu
                  WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_or_join_weekly_league(UUID) IS
  'Returns / joins the caller''s weekly league group. IDOR-guarded 2026-04-26: authenticated callers must pass their own user id. pg_cron bypass preserved.';

GRANT EXECUTE ON FUNCTION get_or_join_weekly_league(UUID) TO authenticated;

-- =============================================================================
-- Q2-72.3: get_league_leaderboard — IDOR guard on p_user_id (UUID).
-- =============================================================================

DROP FUNCTION IF EXISTS get_league_leaderboard(UUID, UUID);

CREATE OR REPLACE FUNCTION get_league_leaderboard(p_user_id UUID, p_group_id UUID)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public
AS $$
DECLARE
    v_group RECORD;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    -- IDOR guard: authenticated callers must ask for their own leaderboard context.
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot read another user''s league context'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_group FROM league_groups WHERE id = p_group_id;
    IF v_group IS NULL THEN RETURN json_build_object('error', 'group_not_found'); END IF;
    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_group.tier_rank;
    v_days_remaining := 6 - (CURRENT_DATE - v_group.week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    WITH my_friends AS (
        SELECT CASE WHEN requester_id = p_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships WHERE (requester_id = p_user_id OR addressee_id = p_user_id) AND status = 'accepted'
    )
    SELECT json_build_object(
        'group_id', v_group.id, 'tier_rank', v_group.tier_rank, 'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji, 'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count, 'relegation_count', v_tier_info.relegation_count,
        'week_start', v_group.week_start, 'days_remaining', v_days_remaining,
        'group_size', v_group.member_count,
        'my_points', COALESCE((SELECT points FROM league_members WHERE user_id = p_user_id AND group_id = p_group_id), 0),
        'my_rank', COALESCE((SELECT rk FROM (SELECT user_id, ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
            FROM league_members lm2 LEFT JOIN user_profiles up2 ON up2.id = lm2.user_id
            WHERE lm2.group_id = p_group_id AND NOT COALESCE(up2.privacy_hide_league, FALSE)
        ) sub WHERE user_id = p_user_id), 1),
        'leaderboard', COALESCE((SELECT json_agg(row_to_json(sub) ORDER BY sub.rank) FROM (
            SELECT lm.user_id, up.name, up.username,
                CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END AS profile_photo_url,
                lm.points, lm.workouts_completed,
                ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                (lm.user_id = p_user_id) AS is_current_user,
                (lm.user_id IN (SELECT fid FROM my_friends)) AS is_friend,
                CASE WHEN lm.user_id = p_user_id THEN NULL WHEN lm.user_id IN (SELECT fid FROM my_friends) THEN NULL
                    ELSE (SELECT COUNT(DISTINCT mf.fid)::INT FROM my_friends mf
                        JOIN friendships f3 ON ((f3.requester_id = mf.fid AND f3.addressee_id = lm.user_id)
                            OR (f3.addressee_id = mf.fid AND f3.requester_id = lm.user_id)) WHERE f3.status = 'accepted')
                END AS mutual_friend_count,
                (COALESCE(up.is_verified, FALSE) OR COALESCE((SELECT ult.current_tier FROM user_league_tier ult WHERE ult.user_id = lm.user_id), 1) = 7) AS is_verified,
                COALESCE(up.is_gold_verified, FALSE) AS is_gold_verified
            FROM league_members lm LEFT JOIN user_profiles up ON up.id = lm.user_id
            WHERE lm.group_id = p_group_id
              AND NOT COALESCE(up.privacy_hide_league, FALSE)
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE (ub.blocker_id = p_user_id AND ub.blocked_id = lm.user_id) OR (ub.blocker_id = lm.user_id AND ub.blocked_id = p_user_id))
              AND NOT EXISTS (SELECT 1 FROM league_hidden_users lhu WHERE lhu.user_id = p_user_id AND lhu.hidden_user_id = lm.user_id)
        ) sub), '[]'::json)
    ) INTO v_result;
    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_league_leaderboard(UUID, UUID) IS
  'Returns the caller''s weekly league leaderboard. IDOR-guarded 2026-04-26: authenticated callers must pass their own user id.';

GRANT EXECUTE ON FUNCTION get_league_leaderboard(UUID, UUID) TO authenticated;

-- =============================================================================
-- Q2-73: Add private_challenge_chat to the supabase_realtime publication.
--        REPLICA IDENTITY FULL is already set by private_challenges_migration
--        (line 1439); fix_private_realtime_publication.sql added the sibling
--        tables but missed chat. Without this, the client-side moderation
--        UPDATE subscription in RealtimeService silently drops events.
-- =============================================================================

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_chat;
EXCEPTION
    WHEN duplicate_object THEN
        NULL;
END $$;

-- Defensive: make sure REPLICA IDENTITY FULL is set (matches migration).
ALTER TABLE private_challenge_chat REPLICA IDENTITY FULL;

COMMIT;
