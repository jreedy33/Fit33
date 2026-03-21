-- ============================================================================
-- PHASE 3: ADD MISSING FK CONSTRAINTS TO INTELLIGENCE/ANALYTICS TABLES
-- ============================================================================
-- These 11 tables have a user_id column but NO foreign key constraint to
-- user_profiles. This means:
--   1. delete_user_account() may leave orphaned rows
--   2. No referential integrity enforcement
--   3. Invalid user_ids can be inserted
--
-- Additionally adds FK for exercise_videos -> exercises and
-- limitation_exercise_mappings -> user_limitations.
--
-- Pattern: Clean orphaned rows first, then add constraint.
-- Uses the _add_user_fk_cascade helper from fix_data_relationships.sql
-- if available, otherwise does it inline.
-- ============================================================================

DO $$
DECLARE
  v_orphans BIGINT;
  v_added INT := 0;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'PHASE 3: ADD MISSING FK CONSTRAINTS';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';

  -- ========================================================================
  -- 1. activity_recovery_correlation (382 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='activity_recovery_correlation' AND column_name='user_id') THEN

    DELETE FROM activity_recovery_correlation
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from activity_recovery_correlation', v_orphans; END IF;

    ALTER TABLE activity_recovery_correlation DROP CONSTRAINT IF EXISTS activity_recovery_correlation_user_id_fkey;
    ALTER TABLE activity_recovery_correlation
      ADD CONSTRAINT activity_recovery_correlation_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ activity_recovery_correlation.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ activity_recovery_correlation.user_id not found';
  END IF;

  -- ========================================================================
  -- 2. exercise_user_effectiveness (776 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='exercise_user_effectiveness' AND column_name='user_id') THEN

    DELETE FROM exercise_user_effectiveness
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from exercise_user_effectiveness', v_orphans; END IF;

    ALTER TABLE exercise_user_effectiveness DROP CONSTRAINT IF EXISTS exercise_user_effectiveness_user_id_fkey;
    ALTER TABLE exercise_user_effectiveness
      ADD CONSTRAINT exercise_user_effectiveness_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ exercise_user_effectiveness.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ exercise_user_effectiveness.user_id not found';
  END IF;

  -- ========================================================================
  -- 3. set_completion_patterns (776 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='set_completion_patterns' AND column_name='user_id') THEN

    DELETE FROM set_completion_patterns
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from set_completion_patterns', v_orphans; END IF;

    ALTER TABLE set_completion_patterns DROP CONSTRAINT IF EXISTS set_completion_patterns_user_id_fkey;
    ALTER TABLE set_completion_patterns
      ADD CONSTRAINT set_completion_patterns_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ set_completion_patterns.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ set_completion_patterns.user_id not found';
  END IF;

  -- ========================================================================
  -- 4. user_performance_trends (887 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='user_performance_trends' AND column_name='user_id') THEN

    DELETE FROM user_performance_trends
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from user_performance_trends', v_orphans; END IF;

    ALTER TABLE user_performance_trends DROP CONSTRAINT IF EXISTS user_performance_trends_user_id_fkey;
    ALTER TABLE user_performance_trends
      ADD CONSTRAINT user_performance_trends_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ user_performance_trends.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ user_performance_trends.user_id not found';
  END IF;

  -- ========================================================================
  -- 5. weekly_volume_trends (308 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='weekly_volume_trends' AND column_name='user_id') THEN

    DELETE FROM weekly_volume_trends
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from weekly_volume_trends', v_orphans; END IF;

    ALTER TABLE weekly_volume_trends DROP CONSTRAINT IF EXISTS weekly_volume_trends_user_id_fkey;
    ALTER TABLE weekly_volume_trends
      ADD CONSTRAINT weekly_volume_trends_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ weekly_volume_trends.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ weekly_volume_trends.user_id not found';
  END IF;

  -- ========================================================================
  -- 6. nutrition_performance_link (331 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='nutrition_performance_link' AND column_name='user_id') THEN

    DELETE FROM nutrition_performance_link
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from nutrition_performance_link', v_orphans; END IF;

    ALTER TABLE nutrition_performance_link DROP CONSTRAINT IF EXISTS nutrition_performance_link_user_id_fkey;
    ALTER TABLE nutrition_performance_link
      ADD CONSTRAINT nutrition_performance_link_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ nutrition_performance_link.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ nutrition_performance_link.user_id not found';
  END IF;

  -- ========================================================================
  -- 7. user_strength_ratios (37 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='user_strength_ratios' AND column_name='user_id') THEN

    DELETE FROM user_strength_ratios
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from user_strength_ratios', v_orphans; END IF;

    ALTER TABLE user_strength_ratios DROP CONSTRAINT IF EXISTS user_strength_ratios_user_id_fkey;
    ALTER TABLE user_strength_ratios
      ADD CONSTRAINT user_strength_ratios_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ user_strength_ratios.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ user_strength_ratios.user_id not found';
  END IF;

  -- ========================================================================
  -- 8. user_learning_profiles (39 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='user_learning_profiles' AND column_name='user_id') THEN

    DELETE FROM user_learning_profiles
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from user_learning_profiles', v_orphans; END IF;

    ALTER TABLE user_learning_profiles DROP CONSTRAINT IF EXISTS user_learning_profiles_user_id_fkey;
    ALTER TABLE user_learning_profiles
      ADD CONSTRAINT user_learning_profiles_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ user_learning_profiles.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ user_learning_profiles.user_id not found';
  END IF;

  -- ========================================================================
  -- 9. workout_time_performance (42 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='workout_time_performance' AND column_name='user_id') THEN

    DELETE FROM workout_time_performance
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from workout_time_performance', v_orphans; END IF;

    ALTER TABLE workout_time_performance DROP CONSTRAINT IF EXISTS workout_time_performance_user_id_fkey;
    ALTER TABLE workout_time_performance
      ADD CONSTRAINT workout_time_performance_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ workout_time_performance.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ workout_time_performance.user_id not found';
  END IF;

  -- ========================================================================
  -- 10. exercise_swap_analytics (105 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='exercise_swap_analytics' AND column_name='user_id') THEN

    DELETE FROM exercise_swap_analytics
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from exercise_swap_analytics', v_orphans; END IF;

    ALTER TABLE exercise_swap_analytics DROP CONSTRAINT IF EXISTS exercise_swap_analytics_user_id_fkey;
    ALTER TABLE exercise_swap_analytics
      ADD CONSTRAINT exercise_swap_analytics_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ exercise_swap_analytics.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ exercise_swap_analytics.user_id not found';
  END IF;

  -- ========================================================================
  -- 11. equipment_proficiency (128 rows)
  -- ========================================================================
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='equipment_proficiency' AND column_name='user_id') THEN

    DELETE FROM equipment_proficiency
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    GET DIAGNOSTICS v_orphans = ROW_COUNT;
    IF v_orphans > 0 THEN RAISE NOTICE '  🧹 Cleaned % orphans from equipment_proficiency', v_orphans; END IF;

    ALTER TABLE equipment_proficiency DROP CONSTRAINT IF EXISTS equipment_proficiency_user_id_fkey;
    ALTER TABLE equipment_proficiency
      ADD CONSTRAINT equipment_proficiency_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES user_profiles(id) ON DELETE CASCADE;
    v_added := v_added + 1;
    RAISE NOTICE '  ✅ equipment_proficiency.user_id → user_profiles(id) CASCADE';
  ELSE
    RAISE NOTICE '  ⏭️ equipment_proficiency.user_id not found';
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'USER FK CONSTRAINTS: Added % of 11', v_added;
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- ============================================================================
-- BONUS: exercise_videos -> exercises FK
-- Skipped: exercise_videos does not have an exercise_id column.
-- The table likely uses a different linking mechanism (e.g., video_code on exercises).
-- ============================================================================

-- ============================================================================
-- BONUS: limitation_exercise_mappings -> user_limitations FK
-- Skipped: Column names need verification against live schema.
-- ============================================================================

-- ============================================================================
-- ADD INDEXES for the new FK columns (improves CASCADE DELETE performance)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_activity_recovery_correlation_user_id ON activity_recovery_correlation(user_id);
CREATE INDEX IF NOT EXISTS idx_exercise_user_effectiveness_user_id ON exercise_user_effectiveness(user_id);
CREATE INDEX IF NOT EXISTS idx_set_completion_patterns_user_id ON set_completion_patterns(user_id);
CREATE INDEX IF NOT EXISTS idx_user_performance_trends_user_id ON user_performance_trends(user_id);
CREATE INDEX IF NOT EXISTS idx_weekly_volume_trends_user_id ON weekly_volume_trends(user_id);
CREATE INDEX IF NOT EXISTS idx_nutrition_performance_link_user_id ON nutrition_performance_link(user_id);
CREATE INDEX IF NOT EXISTS idx_user_strength_ratios_user_id ON user_strength_ratios(user_id);
CREATE INDEX IF NOT EXISTS idx_user_learning_profiles_user_id ON user_learning_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_time_performance_user_id ON workout_time_performance(user_id);
CREATE INDEX IF NOT EXISTS idx_exercise_swap_analytics_user_id ON exercise_swap_analytics(user_id);
CREATE INDEX IF NOT EXISTS idx_equipment_proficiency_user_id ON equipment_proficiency(user_id);
DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ Indexes created for all new FK columns';
  RAISE NOTICE '';
END $$;
