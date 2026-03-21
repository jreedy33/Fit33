-- ============================================================================
-- SMART INSIGHTS ENHANCEMENT: Phase 2 Cross-Table Correlation Views
-- ============================================================================
-- These views JOIN existing tables to surface relationships that
-- intelligence engines can query. All read-only, no data changes.
-- ============================================================================

-- ============================================================================
-- 2.1 Nutrition → Workout Performance
-- Shows how yesterday's eating affected today's workout
-- ============================================================================

CREATE OR REPLACE VIEW v_nutrition_workout_correlation AS
SELECT
  wh.user_id,
  wh.date AS workout_date,
  wh.name AS workout_name,
  wh.duration,
  wh.completion_rate,
  wh.total_sets_completed,
  wh.total_sets_planned,
  ml_agg.total_calories AS pre_workout_calories,
  ml_agg.total_protein AS pre_workout_protein,
  ml_agg.total_carbs AS pre_workout_carbs,
  ml_agg.total_fat AS pre_workout_fat,
  ml_agg.meal_count AS pre_workout_meals
FROM workout_history wh
LEFT JOIN (
  SELECT user_id, date::date AS meal_date,
         SUM(calories) AS total_calories,
         SUM(protein) AS total_protein,
         SUM(carbs) AS total_carbs,
         SUM(fat) AS total_fat,
         COUNT(*) AS meal_count
  FROM meal_logs
  GROUP BY user_id, date::date
) ml_agg ON wh.user_id = ml_agg.user_id
  AND ml_agg.meal_date = wh.date::date - INTERVAL '1 day'
WHERE wh.is_completed = true;

GRANT SELECT ON v_nutrition_workout_correlation TO authenticated;

DO $$ BEGIN RAISE NOTICE '✅ 2.1 Created v_nutrition_workout_correlation'; END $$;

-- ============================================================================
-- 2.2 Hydration → Workout Quality
-- Correlates daily hydration with workout performance
-- ============================================================================

CREATE OR REPLACE VIEW v_hydration_workout_correlation AS
SELECT
  wh.user_id,
  wh.date AS workout_date,
  hds.total_ml AS hydration_ml,
  hds.goal_ml,
  CASE WHEN hds.goal_ml > 0
    THEN ROUND((hds.total_ml::numeric / hds.goal_ml) * 100)
    ELSE NULL END AS hydration_pct,
  wh.completion_rate,
  wh.duration,
  wh.total_sets_completed,
  wtp.avg_weight_multiplier,
  wtp.workout_count AS time_slot_workout_count
FROM workout_history wh
LEFT JOIN hydration_daily_summary hds
  ON wh.user_id = hds.user_id AND hds.date = wh.date::date
LEFT JOIN workout_time_performance wtp
  ON wh.user_id = wtp.user_id;

GRANT SELECT ON v_hydration_workout_correlation TO authenticated;

DO $$ BEGIN RAISE NOTICE '✅ 2.2 Created v_hydration_workout_correlation'; END $$;

-- ============================================================================
-- 2.3 Social → Retention
-- Proves that users with friends retain better
-- ============================================================================

CREATE OR REPLACE VIEW v_social_retention_correlation AS
SELECT
  up.id AS user_id,
  up.name,
  (SELECT count(*) FROM friendships f
   WHERE f.requester_id = up.id OR f.addressee_id = up.id) AS friend_count,
  up.current_streak,
  up.total_workouts,
  up.xp,
  (SELECT count(*) FROM challenge_participants cp WHERE cp.user_id = up.id) AS challenges_joined,
  CASE WHEN up.last_workout_date IS NOT NULL
    THEN EXTRACT(DAY FROM now() - up.last_workout_date::timestamptz)
    ELSE NULL END AS days_since_last_workout
FROM user_profiles up;

GRANT SELECT ON v_social_retention_correlation TO authenticated;

DO $$ BEGIN RAISE NOTICE '✅ 2.3 Created v_social_retention_correlation'; END $$;

-- ============================================================================
-- 2.4 Challenge → Progress Acceleration
-- Quantifies how challenges accelerate user progress
-- ============================================================================

CREATE OR REPLACE VIEW v_challenge_progress_correlation AS
SELECT
  up.id AS user_id,
  up.total_workouts,
  up.current_streak,
  (SELECT count(*) FROM challenge_participants cp WHERE cp.user_id = up.id) AS total_challenges,
  (SELECT count(*) FROM group_challenges gc
   JOIN challenge_participants cp2 ON gc.id = cp2.challenge_id
   WHERE cp2.user_id = up.id AND gc.status = 'completed') AS completed_challenges,
  (SELECT AVG(cdp.progress_value) FROM challenge_daily_progress cdp
   WHERE cdp.user_id = up.id) AS avg_daily_challenge_progress
FROM user_profiles up;

GRANT SELECT ON v_challenge_progress_correlation TO authenticated;

DO $$ BEGIN RAISE NOTICE '✅ 2.4 Created v_challenge_progress_correlation'; END $$;

-- ============================================================================
-- 2.5 Sleep → Recovery
-- Correlates sleep data with activity/recovery patterns
-- ============================================================================

CREATE OR REPLACE VIEW v_sleep_recovery_correlation AS
SELECT
  sl.user_id,
  sl.date_of_sleep AS sleep_date,
  sl.duration_ms,
  ROUND(sl.duration_ms / 3600000.0, 1) AS sleep_hours,
  sl.minutes_asleep,
  arc.activity_level,
  arc.steps
FROM sleep_logs sl
LEFT JOIN activity_recovery_correlation arc
  ON sl.user_id = arc.user_id
  AND arc.date = sl.date_of_sleep;

GRANT SELECT ON v_sleep_recovery_correlation TO authenticated;

DO $$ BEGIN RAISE NOTICE '✅ 2.5 Created v_sleep_recovery_correlation'; END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'SMART INSIGHTS VIEWS COMPLETE';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '  2.1 v_nutrition_workout_correlation';
  RAISE NOTICE '  2.2 v_hydration_workout_correlation';
  RAISE NOTICE '  2.3 v_social_retention_correlation';
  RAISE NOTICE '  2.4 v_challenge_progress_correlation';
  RAISE NOTICE '  2.5 v_sleep_recovery_correlation';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
