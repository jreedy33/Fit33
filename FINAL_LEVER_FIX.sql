-- ============================================================================
-- FINAL LEVER FIX - SIMPLEST POSSIBLE SQL
-- ============================================================================
-- Run these ONE AT A TIME in Supabase SQL Editor
-- After EACH query, verify it worked before moving to next one
-- ============================================================================

-- QUERY 1: Check current state (RUN THIS FIRST)
SELECT COUNT(*) as exercises_with_lever 
FROM exercises 
WHERE name LIKE 'Lever %';
-- If this returns > 0, continue with the updates below

-- ============================================================================
-- QUERY 2: Remove "Lever " from names (NO parentheses version)
-- ============================================================================
BEGIN;

UPDATE exercises
SET name = SUBSTRING(name, 7) || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%';

COMMIT;

-- ============================================================================
-- QUERY 3: Remove "Lever " from names (WITH parentheses version)
-- ============================================================================
BEGIN;

UPDATE exercises
SET name = SUBSTRING(name, 7)
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%';

COMMIT;

-- ============================================================================
-- QUERY 4: Catch any remaining (simple REPLACE)
-- ============================================================================
BEGIN;

UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE '%Lever %';

COMMIT;

-- ============================================================================
-- QUERY 5: Verify it worked (should return 0)
-- ============================================================================
SELECT COUNT(*) as exercises_with_lever 
FROM exercises 
WHERE name LIKE '%Lever %';

-- ============================================================================
-- QUERY 6: See results
-- ============================================================================
SELECT name, equipment 
FROM exercises 
WHERE equipment LIKE '%Machine%' 
ORDER BY name 
LIMIT 30;
