-- ============================================================================
-- PHASE 2: DROP 13 DEAD TABLES
-- ============================================================================
-- These 13 tables have:
--   - ZERO rows of data
--   - ZERO references in Swift, TypeScript, or SQL application code
--   - Only mentioned in documentation files (not executable code)
--
-- Safety: Each DROP is guarded by a row-count check. If a table somehow
-- acquired data between audit and execution, it will be SKIPPED.
-- ============================================================================

DO $$
DECLARE
  v_count BIGINT;
  v_dropped INT := 0;
  v_skipped INT := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'PHASE 2: DROP DEAD TABLES';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';

  -- 1. community_benchmarks (16 cols, collaborative cross-user learning - never used)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='community_benchmarks') THEN
    SELECT count(*) INTO v_count FROM community_benchmarks;
    IF v_count = 0 THEN
      DROP TABLE community_benchmarks CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped community_benchmarks (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED community_benchmarks — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ community_benchmarks does not exist';
  END IF;

  -- 2. exercise_cooldown_log (8 cols, cooldown tracking - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='exercise_cooldown_log') THEN
    SELECT count(*) INTO v_count FROM exercise_cooldown_log;
    IF v_count = 0 THEN
      DROP TABLE exercise_cooldown_log CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped exercise_cooldown_log (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED exercise_cooldown_log — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ exercise_cooldown_log does not exist';
  END IF;

  -- 3. muscle_synergy_matrix (7 cols, muscle pairing data - never populated)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='muscle_synergy_matrix') THEN
    SELECT count(*) INTO v_count FROM muscle_synergy_matrix;
    IF v_count = 0 THEN
      DROP TABLE muscle_synergy_matrix CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped muscle_synergy_matrix (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED muscle_synergy_matrix — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ muscle_synergy_matrix does not exist';
  END IF;

  -- 4. program_ratings (7 cols, user program ratings - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='program_ratings') THEN
    SELECT count(*) INTO v_count FROM program_ratings;
    IF v_count = 0 THEN
      DROP TABLE program_ratings CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped program_ratings (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED program_ratings — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ program_ratings does not exist';
  END IF;

  -- 5. program_workout_history (8 cols, per-program workout tracking - never used)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='program_workout_history') THEN
    SELECT count(*) INTO v_count FROM program_workout_history;
    IF v_count = 0 THEN
      DROP TABLE program_workout_history CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped program_workout_history (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED program_workout_history — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ program_workout_history does not exist';
  END IF;

  -- 6. rest_time_analytics (15 cols, rest time between sets - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='rest_time_analytics') THEN
    SELECT count(*) INTO v_count FROM rest_time_analytics;
    IF v_count = 0 THEN
      DROP TABLE rest_time_analytics CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped rest_time_analytics (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED rest_time_analytics — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ rest_time_analytics does not exist';
  END IF;

  -- 7. set_scheme_analytics (13 cols, set scheme tracking - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='set_scheme_analytics') THEN
    SELECT count(*) INTO v_count FROM set_scheme_analytics;
    IF v_count = 0 THEN
      DROP TABLE set_scheme_analytics CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped set_scheme_analytics (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED set_scheme_analytics — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ set_scheme_analytics does not exist';
  END IF;

  -- 8. user_food_preferences (10 cols, food preferences - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_food_preferences') THEN
    SELECT count(*) INTO v_count FROM user_food_preferences;
    IF v_count = 0 THEN
      DROP TABLE user_food_preferences CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_food_preferences (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_food_preferences — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_food_preferences does not exist';
  END IF;

  -- 9. user_goal_metrics (30 cols, goal tracking metrics - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_goal_metrics') THEN
    SELECT count(*) INTO v_count FROM user_goal_metrics;
    IF v_count = 0 THEN
      DROP TABLE user_goal_metrics CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_goal_metrics (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_goal_metrics — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_goal_metrics does not exist';
  END IF;

  -- 10. user_recipe_carousel_state (7 cols, recipe UI state - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recipe_carousel_state') THEN
    SELECT count(*) INTO v_count FROM user_recipe_carousel_state;
    IF v_count = 0 THEN
      DROP TABLE user_recipe_carousel_state CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_recipe_carousel_state (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_recipe_carousel_state — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_recipe_carousel_state does not exist';
  END IF;

  -- 11. user_recipe_interactions (11 cols, recipe likes/saves - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recipe_interactions') THEN
    SELECT count(*) INTO v_count FROM user_recipe_interactions;
    IF v_count = 0 THEN
      DROP TABLE user_recipe_interactions CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_recipe_interactions (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_recipe_interactions — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_recipe_interactions does not exist';
  END IF;

  -- 12. user_recommended_recipes (14 cols, recipe recs - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_recommended_recipes') THEN
    SELECT count(*) INTO v_count FROM user_recommended_recipes;
    IF v_count = 0 THEN
      DROP TABLE user_recommended_recipes CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_recommended_recipes (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_recommended_recipes — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_recommended_recipes does not exist';
  END IF;

  -- 13. user_taste_profile (19 cols, taste preferences - never implemented)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='user_taste_profile') THEN
    SELECT count(*) INTO v_count FROM user_taste_profile;
    IF v_count = 0 THEN
      DROP TABLE user_taste_profile CASCADE;
      v_dropped := v_dropped + 1;
      RAISE NOTICE '  ✅ Dropped user_taste_profile (0 rows)';
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE '  ⚠️ SKIPPED user_taste_profile — has % rows!', v_count;
    END IF;
  ELSE
    RAISE NOTICE '  ⏭️ user_taste_profile does not exist';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'RESULT: Dropped % tables, Skipped %', v_dropped, v_skipped;
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
