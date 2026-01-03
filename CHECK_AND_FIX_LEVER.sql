-- ============================================================================
-- STEP 1: CHECK IF PREVIOUS UPDATES WERE ACTUALLY APPLIED
-- ============================================================================

-- Run this first to see if "Lever" names still exist in database
SELECT COUNT(*) as lever_count, 'Exercises with Lever prefix' as description
FROM exercises 
WHERE name LIKE 'Lever %';

-- If the above shows a count > 0, the previous SQL didn't apply. Continue below.

-- ============================================================================
-- STEP 2: FORCE UPDATE ALL LEVER NAMES (Multiple approaches)
-- ============================================================================

-- Approach 1: Simple REPLACE for exercises without parentheses
UPDATE exercises
SET name = TRIM(REPLACE(name, 'Lever', '')) || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%'
  AND name NOT LIKE '%Plate%';

-- Approach 2: For exercises already with parentheses, just remove "Lever "
UPDATE exercises
SET name = TRIM(REPLACE(name, 'Lever', ''))
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%';

-- Approach 3: For exercises with "Plate" but no parentheses
UPDATE exercises
SET name = TRIM(REPLACE(name, 'Lever', '')) || ' (Plate Loaded)'
WHERE name LIKE 'Lever %'
  AND name LIKE '%Plate%'
  AND name NOT LIKE '%(%';

-- Approach 4: Nuclear option - remove "Lever " from start of ANY exercise
UPDATE exercises
SET name = SUBSTRING(name, 7)
WHERE name LIKE 'Lever %'
  AND LENGTH(name) > 6;

-- Approach 5: Add (Machine) to any that don't have parentheses yet
UPDATE exercises
SET name = name || ' (Machine)'
WHERE equipment LIKE '%Machine%'
  AND name NOT LIKE '%(%'
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- STEP 3: VERIFY THE CHANGES
-- ============================================================================

-- This should now return 0
SELECT COUNT(*) as remaining_lever, 'Should be 0' as expected
FROM exercises 
WHERE name LIKE 'Lever %';

-- Show sample of updated names
SELECT name, equipment, category 
FROM exercises 
WHERE equipment LIKE '%Machine%' 
  AND equipment NOT LIKE '%Cable%'
ORDER BY name 
LIMIT 20;

-- ============================================================================
-- STEP 4: COMMIT THE TRANSACTION (If using transaction)
-- ============================================================================

-- If you're in a transaction, make sure to COMMIT:
COMMIT;
