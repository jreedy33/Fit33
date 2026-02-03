-- ============================================================================
-- CLEAR FOOD CACHE FOR NUTRITION DATA FIX
-- ============================================================================
-- Run this after deploying the updated usda-food-search edge function
-- This ensures users get fresh data with correct nutrition values
--
-- The issue: Previous cached data may have incorrect nutrition values
-- that were being multiplied incorrectly (showing 100x the actual values)
-- ============================================================================

-- Step 1: Clear the search cache (forces fresh searches)
-- This table stores search query -> result IDs mappings
DELETE FROM food_search_cache;

-- Step 2: Optionally clear all cached food items to force fresh USDA fetches
-- CAUTION: This will require re-fetching all foods from USDA API
-- Only run this if you want to completely refresh the database
-- 
-- Uncomment the following line if you want a complete refresh:
-- DELETE FROM food_items;

-- Step 3: Verify the cache is cleared
SELECT 
    'food_search_cache' as table_name,
    COUNT(*) as row_count
FROM food_search_cache
UNION ALL
SELECT 
    'food_items' as table_name,
    COUNT(*) as row_count
FROM food_items;

-- ============================================================================
-- ALTERNATIVE: Selective clearing for specific foods
-- ============================================================================
-- If you only want to clear specific problematic foods:

-- Clear cache for "broccoli" searches
-- DELETE FROM food_search_cache WHERE normalized_query LIKE '%broccoli%';

-- Clear specific food items by name
-- DELETE FROM food_items WHERE name ILIKE '%broccoli%';

-- ============================================================================
-- NOTES
-- ============================================================================
-- After running this script:
-- 1. Deploy the updated edge function: supabase functions deploy usda-food-search
-- 2. Users searching for foods will get fresh data from USDA
-- 3. Foundation Foods will be prioritized in search results
-- 4. Nutrition values will be correct (per 100g as USDA provides)
-- ============================================================================
