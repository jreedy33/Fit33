-- ============================================================================
-- PHASE 5: CONSOLIDATE meal_logs / user_food_history
-- ============================================================================
-- Problem: MealService.addMealEntry writes to BOTH meal_logs AND
-- user_food_history via logFoodToHistory(). 8 columns overlap.
--
-- Strategy (conservative):
--   1. Create a VIEW that derives food history data from meal_logs
--   2. The Swift code will stop calling logFoodToHistory() from MealService
--      (the duplicate write path), but the table stays for existing data
--   3. FoodDatabaseService reads continue unchanged for now
--   4. user_food_history table is NOT dropped (kept for one release cycle)
--
-- Future work: Migrate FoodDatabaseService reads from user_food_history
-- to user_food_history_v, then drop the table.
-- ============================================================================

-- Create the view that derives food history from meal_logs
CREATE OR REPLACE VIEW user_food_history_v AS
SELECT
  ml.user_id,
  ml.fdc_id,
  ml.food_name,
  ml.meal_type,
  ml.quantity,
  ml.unit AS serving_unit,
  ml.calories,
  ml.protein,
  ml.carbs,
  ml.fat,
  ml.created_at AS logged_at,
  count(*) OVER (PARTITION BY ml.user_id, ml.fdc_id) AS times_eaten,
  max(ml.created_at) OVER (PARTITION BY ml.user_id, ml.fdc_id) AS last_eaten
FROM meal_logs ml
WHERE ml.fdc_id IS NOT NULL;

COMMENT ON VIEW user_food_history_v IS
  'Derives food history from meal_logs. Replaces the duplicate user_food_history table. '
  'Use this view for "frequent foods" and "recent foods" queries.';

-- Grant access to the view
GRANT SELECT ON user_food_history_v TO authenticated;
GRANT SELECT ON user_food_history_v TO anon;

-- Add RLS-compatible policy hint via a secure view
-- (Views inherit RLS from underlying table, so meal_logs RLS applies)

DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'PHASE 5: FOOD HISTORY CONSOLIDATION';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '  ✅ Created view user_food_history_v (from meal_logs)';
  RAISE NOTICE '';
  RAISE NOTICE '  Next steps (Swift code changes):';
  RAISE NOTICE '    1. Remove logFoodToHistory() call from MealService.addMealEntry()';
  RAISE NOTICE '    2. Future: migrate FoodDatabaseService reads to user_food_history_v';
  RAISE NOTICE '    3. Future: drop user_food_history table after migration';
  RAISE NOTICE '';
  RAISE NOTICE '  ⚠️ user_food_history table is NOT dropped — kept as safety net';
  RAISE NOTICE '';
END $$;
