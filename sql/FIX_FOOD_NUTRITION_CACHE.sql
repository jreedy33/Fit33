-- ============================================================================
-- FIX FOOD NUTRITION CACHE
-- ============================================================================
-- This script clears the cached search results so that fresh, accurate
-- nutrition data is fetched from the USDA API on the next search.
--
-- Problem: Cached foods may have incorrect nutrition data due to decoder issues
-- Solution: Clear search cache to force fresh API calls with correct parsing
-- ============================================================================

-- Step 1: Check current cache stats
SELECT 
    'food_items' as table_name,
    count(*) as total_records,
    count(*) FILTER (WHERE data_type = 'Foundation') as foundation_foods,
    count(*) FILTER (WHERE data_type = 'SR Legacy') as sr_legacy_foods,
    count(*) FILTER (WHERE data_type = 'Survey (FNDDS)') as survey_foods,
    count(*) FILTER (WHERE data_type = 'Branded') as branded_foods,
    count(*) FILTER (WHERE calories > 0) as with_calories
FROM food_items;

SELECT 
    'food_search_cache' as table_name,
    count(*) as total_cached_searches
FROM food_search_cache;

-- Step 2: View some sample broccoli data before cleanup
SELECT 
    fdc_id,
    name,
    data_type,
    serving_size,
    serving_unit,
    calories,
    protein,
    carbohydrates,
    total_fat,
    portions
FROM food_items 
WHERE name ILIKE '%broccoli%' 
ORDER BY 
    CASE 
        WHEN data_type = 'Foundation' THEN 1
        WHEN data_type = 'SR Legacy' THEN 2
        ELSE 3
    END
LIMIT 10;

-- Step 3: Clear the search cache (forces fresh API calls on next search)
-- This is SAFE - it just means the next search will go to USDA API
DELETE FROM food_search_cache;

-- Step 4: Option A - Clear ALL cached food items (recommended for full refresh)
-- Uncomment if you want to completely refresh all food data
-- WARNING: This will clear user favorites and history references
-- DELETE FROM food_items;

-- Step 4: Option B - Clear only foods with suspicious nutrition data
-- This keeps the structure but refreshes nutrition by re-querying USDA
-- Foods with calories = 0 are likely incorrectly cached
DELETE FROM food_items WHERE calories = 0 AND protein = 0 AND carbohydrates = 0 AND total_fat = 0;

-- Step 5: Update any broccoli entries that show incorrect data
-- According to USDA, raw broccoli per 100g should be:
-- - Calories: ~34 kcal
-- - Protein: ~2.8g
-- - Carbs: ~7g
-- - Fat: ~0.4g

-- Check if broccoli has wrong values and fix them
UPDATE food_items
SET 
    calories = 34,
    protein = 2.8,
    carbohydrates = 7,
    total_fat = 0.4,
    saturated_fat = 0,
    fiber = 2.6,
    sugar = 1.7,
    sodium = 33,
    cholesterol = 0,
    calcium = 47,
    iron = 0.7,
    vitamin_c = 89.2,
    serving_size = 100,
    serving_unit = 'g'
WHERE name ILIKE '%broccoli%raw%' 
  AND data_type IN ('Foundation', 'SR Legacy')
  AND (calories > 100 OR protein > 50);  -- These are clearly wrong values

-- Step 6: Verify the fix
SELECT 
    fdc_id,
    name,
    data_type,
    serving_size,
    serving_unit,
    calories,
    protein,
    carbohydrates,
    total_fat,
    fiber,
    vitamin_c
FROM food_items 
WHERE name ILIKE '%broccoli%' 
ORDER BY 
    CASE 
        WHEN data_type = 'Foundation' THEN 1
        WHEN data_type = 'SR Legacy' THEN 2
        ELSE 3
    END
LIMIT 10;

-- Step 7: Summary
SELECT 
    'Cache cleared! Next search will fetch fresh data from USDA API.' as status,
    (SELECT count(*) FROM food_items) as remaining_food_items,
    (SELECT count(*) FROM food_search_cache) as remaining_search_cache;
