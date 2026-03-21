-- ============================================================================
-- AFTER-AUDIT VERIFICATION
-- Run this AFTER executing all cleanup migrations.
-- Compare results with audit_before.sql to verify improvements.
-- ============================================================================
-- Safe to run: ALL queries are SELECT-only (read-only).
-- ============================================================================

-- ============================================================================
-- TEST 1: Dead Tables Should NOT Exist
-- Expected: All 13 return 'DROPPED (PASS)'
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 1: DEAD TABLES REMOVED ━━━'; END $$;

SELECT table_name,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t.table_name)
            THEN '❌ STILL EXISTS (FAIL)'
            ELSE '✅ DROPPED (PASS)' END AS status
FROM (VALUES
  ('community_benchmarks'), ('exercise_cooldown_log'), ('muscle_synergy_matrix'),
  ('program_ratings'), ('program_workout_history'), ('rest_time_analytics'),
  ('set_scheme_analytics'), ('user_food_preferences'), ('user_goal_metrics'),
  ('user_recipe_carousel_state'), ('user_recipe_interactions'),
  ('user_recommended_recipes'), ('user_taste_profile')
) AS t(table_name)
ORDER BY table_name;

-- ============================================================================
-- TEST 2: FK Constraints Should Exist on All 11 Tables
-- Expected: All 11 return 'HAS FK (PASS)'
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 2: FK CONSTRAINTS ADDED ━━━'; END $$;

SELECT t.table_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.table_constraints tc
         WHERE tc.table_name = t.table_name
           AND tc.constraint_type = 'FOREIGN KEY'
           AND tc.table_schema = 'public'
       ) THEN '✅ HAS FK (PASS)'
         ELSE '❌ NO FK (FAIL)' END AS status
FROM (VALUES
  ('activity_recovery_correlation'), ('exercise_user_effectiveness'),
  ('set_completion_patterns'), ('user_performance_trends'),
  ('weekly_volume_trends'), ('nutrition_performance_link'),
  ('user_strength_ratios'), ('user_learning_profiles'),
  ('workout_time_performance'), ('exercise_swap_analytics'),
  ('equipment_proficiency')
) AS t(table_name)
ORDER BY t.table_name;

-- Bonus: Check exercise_videos FK
SELECT 'exercise_videos' AS table_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.table_constraints tc
         WHERE tc.table_name = 'exercise_videos'
           AND tc.constraint_type = 'FOREIGN KEY'
           AND tc.table_schema = 'public'
       ) THEN '✅ HAS FK (PASS)'
         ELSE '❌ NO FK (FAIL)' END AS status;

-- ============================================================================
-- TEST 3: Zero Orphaned Rows (all FK-constrained tables)
-- Expected: All orphan counts = 0
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 3: ZERO ORPHANED ROWS ━━━'; END $$;

SELECT table_name, orphan_count,
       CASE WHEN orphan_count = 0 THEN '✅ PASS' ELSE '❌ FAIL' END AS status
FROM (
  SELECT 'activity_recovery_correlation' AS table_name,
         (SELECT count(*) FROM activity_recovery_correlation a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id)) AS orphan_count
  UNION ALL
  SELECT 'exercise_user_effectiveness',
         (SELECT count(*) FROM exercise_user_effectiveness a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'set_completion_patterns',
         (SELECT count(*) FROM set_completion_patterns a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'user_performance_trends',
         (SELECT count(*) FROM user_performance_trends a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'weekly_volume_trends',
         (SELECT count(*) FROM weekly_volume_trends a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'nutrition_performance_link',
         (SELECT count(*) FROM nutrition_performance_link a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'user_strength_ratios',
         (SELECT count(*) FROM user_strength_ratios a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'user_learning_profiles',
         (SELECT count(*) FROM user_learning_profiles a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'workout_time_performance',
         (SELECT count(*) FROM workout_time_performance a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'exercise_swap_analytics',
         (SELECT count(*) FROM exercise_swap_analytics a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
  UNION ALL
  SELECT 'equipment_proficiency',
         (SELECT count(*) FROM equipment_proficiency a
          WHERE NOT EXISTS (SELECT 1 FROM user_profiles u WHERE u.id = a.user_id))
) sub
ORDER BY table_name;

-- ============================================================================
-- TEST 4: Sync Trigger Installed
-- Expected: Both triggers exist
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 4: SYNC TRIGGERS INSTALLED ━━━'; END $$;

SELECT trigger_name, event_object_table, action_timing, event_manipulation,
       '✅ EXISTS (PASS)' AS status
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name IN ('trg_sync_profiles_to_progress', 'trg_sync_progress_to_profiles')
ORDER BY trigger_name;

-- Check if expected triggers are missing
SELECT t.trigger_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM information_schema.triggers
         WHERE trigger_name = t.trigger_name AND trigger_schema = 'public'
       ) THEN '✅ INSTALLED (PASS)'
         ELSE '❌ MISSING (FAIL)' END AS status
FROM (VALUES
  ('trg_sync_profiles_to_progress'),
  ('trg_sync_progress_to_profiles')
) AS t(trigger_name);

-- ============================================================================
-- TEST 5: Profile/Progress Data In Sync
-- Expected: Zero drift rows
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 5: PROFILE/PROGRESS SYNC CHECK ━━━'; END $$;

SELECT
  count(*) AS users_with_drift,
  CASE WHEN count(*) = 0 THEN '✅ ALL SYNCED (PASS)' ELSE '❌ DRIFT DETECTED (FAIL)' END AS status
FROM user_profiles p
JOIN user_progress pr ON p.id = pr.user_id
WHERE p.current_streak IS DISTINCT FROM pr.current_streak
   OR p.longest_streak IS DISTINCT FROM pr.longest_streak
   OR p.total_workouts IS DISTINCT FROM pr.total_workouts
   OR p.last_workout_date IS DISTINCT FROM pr.last_workout_date;

-- ============================================================================
-- TEST 6: Food History View Exists
-- Expected: View exists and returns data
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 6: FOOD HISTORY VIEW ━━━'; END $$;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema='public' AND table_name='user_food_history_v'
  ) THEN '✅ VIEW EXISTS (PASS)'
    ELSE '❌ VIEW MISSING (FAIL)' END AS view_status;

SELECT count(*) AS view_row_count FROM user_food_history_v;

-- ============================================================================
-- TEST 7: Indexes Created for FK Columns
-- Expected: All 12 indexes exist
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ TEST 7: INDEXES ON FK COLUMNS ━━━'; END $$;

SELECT idx.indexname,
       '✅ EXISTS' AS status
FROM pg_indexes idx
WHERE idx.schemaname = 'public'
  AND idx.indexname IN (
    'idx_activity_recovery_correlation_user_id',
    'idx_exercise_user_effectiveness_user_id',
    'idx_set_completion_patterns_user_id',
    'idx_user_performance_trends_user_id',
    'idx_weekly_volume_trends_user_id',
    'idx_nutrition_performance_link_user_id',
    'idx_user_strength_ratios_user_id',
    'idx_user_learning_profiles_user_id',
    'idx_workout_time_performance_user_id',
    'idx_exercise_swap_analytics_user_id',
    'idx_equipment_proficiency_user_id',
    'idx_exercise_videos_exercise_id'
  )
ORDER BY idx.indexname;

-- ============================================================================
-- SUMMARY: Database Health After Remediation
-- ============================================================================

DO $$ BEGIN RAISE NOTICE ''; RAISE NOTICE '━━━ SUMMARY: DATABASE HEALTH ━━━'; END $$;

SELECT
  (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') AS total_tables,
  (SELECT count(*) FROM information_schema.views WHERE table_schema = 'public') AS total_views,
  (SELECT count(*) FROM information_schema.routines WHERE routine_schema = 'public') AS total_functions;

-- Table count should be 13 less than before (146 - 13 = 133)
-- View count should be 1 more than before (20 + 1 = 21)
-- Function count should remain ~280
