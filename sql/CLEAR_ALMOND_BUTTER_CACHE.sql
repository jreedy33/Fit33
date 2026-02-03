-- Clear cached search results for almond butter queries
-- This forces the app to fetch fresh results from USDA with proper dataType

-- Clear the search cache
DELETE FROM food_search_cache 
WHERE normalized_query LIKE '%almond%butter%';

-- Optional: Also clear the food_items cache for almond butter to get fresh dataType
-- UPDATE food_items 
-- SET data_type = NULL
-- WHERE LOWER(name) LIKE '%almond%butter%' AND data_type IS NULL;

-- Check current state of Foundation almond butter
SELECT 
    fdc_id,
    name,
    data_type,
    serving_size,
    serving_unit
FROM food_items
WHERE fdc_id = 2262074  -- This is the Foundation "Almond butter, creamy"
   OR LOWER(name) = 'almond butter, creamy';
