-- ============================================================================
-- REFRESH THE MATERIALIZED VIEW - THIS IS THE ACTUAL PROBLEM!
-- ============================================================================
-- Your app fetches from mv_public_exercises (materialized view), not exercises table
-- Even though you fixed the exercises table, the view is STALE
-- ============================================================================

-- Check the materialized view (this is what your app sees)
SELECT COUNT(*) as lever_count_in_view
FROM mv_public_exercises 
WHERE name LIKE 'Lever %';

-- If the above shows > 0, run this to refresh it:
REFRESH MATERIALIZED VIEW mv_public_exercises;

-- Verify it's now fixed (should show 0)
SELECT COUNT(*) as lever_count_after_refresh
FROM mv_public_exercises 
WHERE name LIKE 'Lever %';

-- Show sample of what the app will now see
SELECT name, equipment 
FROM mv_public_exercises 
WHERE equipment LIKE '%Machine%' 
ORDER BY name 
LIMIT 30;
