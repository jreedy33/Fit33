-- ============================================================================
-- NUCLEAR FIX FOR LEVER NAMES - GUARANTEED TO WORK
-- ============================================================================
-- This uses the simplest possible SQL that works in ANY PostgreSQL version
-- No fancy REGEXP, no complex logic - just basic string operations
-- ============================================================================

-- STEP 1: Show what we're about to change (run this first to verify)
-- SELECT name, equipment FROM exercises WHERE name LIKE 'Lever %' LIMIT 20;

-- STEP 2: Fix the names using SUBSTRING (character position)
-- "Lever " is 6 characters, so we start from position 7

UPDATE exercises
SET name = SUBSTRING(name, 7) || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%';

UPDATE exercises
SET name = SUBSTRING(name, 7)
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%';

-- STEP 3: Double-check with simple REPLACE
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE 'Lever %';

-- STEP 4: Add (Machine) to any that lost it
UPDATE exercises
SET name = name || ' (Machine)'
WHERE name NOT LIKE '%(%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%'
  AND LENGTH(name) > 3;

-- STEP 5: Fix equipment labels for cables
UPDATE exercises
SET equipment = 'Cables'
WHERE equipment LIKE '%Cable%';

-- STEP 6: Verify (should return 0)
SELECT COUNT(*) as lever_count FROM exercises WHERE name LIKE 'Lever %';

-- STEP 7: Show results
SELECT name, equipment FROM exercises 
WHERE equipment LIKE '%Machine%' 
  AND equipment NOT LIKE '%Cable%'
ORDER BY name 
LIMIT 30;
