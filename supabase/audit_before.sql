-- ============================================================================
-- BEFORE-AUDIT BASELINE
-- Run this BEFORE executing any cleanup migrations.
-- Save the output to compare with audit_after.sql results.
-- ============================================================================
-- Safe to run: ALL queries are SELECT-only (read-only).
-- ============================================================================

-- ============================================================================
-- SECTION 1: Dead Table Row Counts (expect all 0)
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 1: DEAD TABLE ROW COUNTS ━━━'; END $$;

SELECT 'community_benchmarks' AS table_name,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='community_benchmarks')
            THEN (SELECT count(*)::text FROM community_benchmarks)
            ELSE 'TABLE NOT FOUND' END AS row_count
UNION ALL
SELECT 'exercise_cooldown_log',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='exercise_cooldown_log')
            THEN (SELECT count(*)::text FROM exercise_cooldown_log)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'muscle_synergy_matrix',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='muscle_synergy_matrix')
            THEN (SELECT count(*)::text FROM muscle_synergy_matrix)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'program_ratings',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='program_ratings')
            THEN (SELECT count(*)::text FROM program_ratings)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'program_workout_history',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='program_workout_history')
            THEN (SELECT count(*)::text FROM program_workout_history)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'rest_time_analytics',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='rest_time_analytics')
            THEN (SELECT count(*)::text FROM rest_time_analytics)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'set_scheme_analytics',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='set_scheme_analytics')
            THEN (SELECT count(*)::text FROM set_scheme_analytics)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_food_preferences',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_food_preferences')
            THEN (SELECT count(*)::text FROM user_food_preferences)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_goal_metrics',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_goal_metrics')
            THEN (SELECT count(*)::text FROM user_goal_metrics)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_recipe_carousel_state',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recipe_carousel_state')
            THEN (SELECT count(*)::text FROM user_recipe_carousel_state)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_recipe_interactions',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recipe_interactions')
            THEN (SELECT count(*)::text FROM user_recipe_interactions)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_recommended_recipes',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recommended_recipes')
            THEN (SELECT count(*)::text FROM user_recommended_recipes)
            ELSE 'TABLE NOT FOUND' END
UNION ALL
SELECT 'user_taste_profile',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_taste_profile')
            THEN (SELECT count(*)::text FROM user_taste_profile)
            ELSE 'TABLE NOT FOUND' END;

-- ============================================================================
-- SECTION 2: FK-Less Tables - Verify They Exist and Count Rows
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 2: FK-LESS TABLES (ROWS + ORPHAN COUNTS) ━━━'; END $$;

SELECT 'activity_recovery_correlation' AS table_name,
       (SELECT count(*) FROM activity_recovery_correlation) AS total_rows,
       (SELECT count(*) FROM activity_recovery_correlation a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id)) AS orphan_rows
UNION ALL
SELECT 'exercise_user_effectiveness',
       (SELECT count(*) FROM exercise_user_effectiveness),
       (SELECT count(*) FROM exercise_user_effectiveness a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'set_completion_patterns',
       (SELECT count(*) FROM set_completion_patterns),
       (SELECT count(*) FROM set_completion_patterns a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'user_performance_trends',
       (SELECT count(*) FROM user_performance_trends),
       (SELECT count(*) FROM user_performance_trends a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'weekly_volume_trends',
       (SELECT count(*) FROM weekly_volume_trends),
       (SELECT count(*) FROM weekly_volume_trends a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'nutrition_performance_link',
       (SELECT count(*) FROM nutrition_performance_link),
       (SELECT count(*) FROM nutrition_performance_link a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'user_strength_ratios',
       (SELECT count(*) FROM user_strength_ratios),
       (SELECT count(*) FROM user_strength_ratios a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'user_learning_profiles',
       (SELECT count(*) FROM user_learning_profiles),
       (SELECT count(*) FROM user_learning_profiles a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'workout_time_performance',
       (SELECT count(*) FROM workout_time_performance),
       (SELECT count(*) FROM workout_time_performance a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'exercise_swap_analytics',
       (SELECT count(*) FROM exercise_swap_analytics),
       (SELECT count(*) FROM exercise_swap_analytics a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
UNION ALL
SELECT 'equipment_proficiency',
       (SELECT count(*) FROM equipment_proficiency),
       (SELECT count(*) FROM equipment_proficiency a
        WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id));

-- ============================================================================
-- SECTION 3: Check for Missing FK Constraints on These Tables
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 3: FK CONSTRAINT CHECK ━━━'; END $$;

SELECT tc.table_name,
       tc.constraint_name,
       kcu.column_name,
       ccu.table_name AS references_table
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name IN (
    'activity_recovery_correlation', 'exercise_user_effectiveness',
    'set_completion_patterns', 'user_performance_trends',
    'weekly_volume_trends', 'nutrition_performance_link',
    'user_strength_ratios', 'user_learning_profiles',
    'workout_time_performance', 'exercise_swap_analytics',
    'equipment_proficiency', 'exercise_videos',
    'limitation_exercise_mappings'
  )
ORDER BY tc.table_name;

-- ============================================================================
-- SECTION 4: user_profiles vs user_progress Drift Detection
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 4: PROFILE/PROGRESS DRIFT CHECK ━━━'; END $$;

SELECT
  p.id AS user_id,
  p.name,
  p.current_streak AS profile_streak,
  pr.current_streak AS progress_streak,
  CASE WHEN p.current_streak IS DISTINCT FROM pr.current_streak THEN 'DRIFT' ELSE 'ok' END AS streak_status,
  p.total_workouts AS profile_workouts,
  pr.total_workouts AS progress_workouts,
  CASE WHEN p.total_workouts IS DISTINCT FROM pr.total_workouts THEN 'DRIFT' ELSE 'ok' END AS workouts_status,
  p.longest_streak AS profile_longest,
  pr.longest_streak AS progress_longest,
  CASE WHEN p.longest_streak IS DISTINCT FROM pr.longest_streak THEN 'DRIFT' ELSE 'ok' END AS longest_status,
  p.xp AS profile_xp,
  pr.xp AS progress_xp,
  CASE WHEN p.xp IS DISTINCT FROM pr.xp THEN 'DRIFT' ELSE 'ok' END AS xp_status,
  p.weight_lbs AS profile_weight,
  pr.weight_lbs AS progress_weight,
  CASE WHEN p.weight_lbs IS DISTINCT FROM pr.weight_lbs THEN 'DRIFT' ELSE 'ok' END AS weight_status,
  p.last_workout_date AS profile_last_workout,
  pr.last_workout_date AS progress_last_workout,
  CASE WHEN p.last_workout_date IS DISTINCT FROM pr.last_workout_date THEN 'DRIFT' ELSE 'ok' END AS last_workout_status
FROM user_profiles p
LEFT JOIN user_progress pr ON p.id = pr.user_id
ORDER BY p.name;

-- ============================================================================
-- SECTION 5: meal_logs vs user_food_history Duplication Check
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 5: FOOD TABLE DUPLICATION ━━━'; END $$;

SELECT 'meal_logs' AS table_name, count(*) AS row_count FROM meal_logs
UNION ALL
SELECT 'user_food_history', count(*) FROM user_food_history;

-- ============================================================================
-- SECTION 6: Current delete_user_account() Function Definition
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 6: delete_user_account() DEFINITION ━━━'; END $$;

SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'delete_user_account';

-- ============================================================================
-- SECTION 7: Total Table Count
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SECTION 7: DATABASE SUMMARY ━━━'; END $$;

SELECT
  (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') AS total_tables,
  (SELECT count(*) FROM information_schema.views WHERE table_schema = 'public') AS total_views,
  (SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'public') AS total_functions;
