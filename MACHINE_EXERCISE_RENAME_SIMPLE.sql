-- ============================================================================
-- MACHINE EXERCISE NAME CLEANUP - SIMPLE VERSION
-- ============================================================================
-- Removes "Lever " prefix from all exercise names
-- Adds "(Machine)" or "(Plate Loaded)" suffix
-- Uses simple string replacement (no REGEXP needed)
-- ============================================================================

-- ============================================================================
-- STEP 1: SEPARATE CABLES FROM MACHINES
-- ============================================================================

-- Ensure all cable exercises have "Cables" equipment (not "Cable Machine")
UPDATE exercises 
SET equipment = 'Cables'
WHERE equipment LIKE '%Cable%';

-- ============================================================================
-- STEP 2: UPDATE EXERCISE NAMES - Simple String Replacement
-- ============================================================================

-- For exercises without parentheses, add "(Machine)" suffix
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '') || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%'
  AND name NOT LIKE '%Plate%'
  AND equipment NOT LIKE '%Cable%';

-- For exercises with "Plate" in name but no parentheses, add "(Plate Loaded)"
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '') || ' (Plate Loaded)'
WHERE name LIKE 'Lever %'
  AND name LIKE '%Plate%'
  AND name NOT LIKE '%(%'
  AND equipment NOT LIKE '%Cable%';

-- For exercises that already have parentheses but start with "Lever", just remove "Lever "
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%'
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- STEP 3: SET SPECIFIC MACHINE EQUIPMENT LABELS
-- ============================================================================

-- Hack Squat Machines
UPDATE exercises 
SET equipment = 'Hack Squat Machine'
WHERE name LIKE '%Hack Squat%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Leg Press Machines
UPDATE exercises 
SET equipment = 'Leg Press Machine'
WHERE name LIKE '%Leg Press%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Chest Press Machines
UPDATE exercises 
SET equipment = 'Chest Press Machine'
WHERE name LIKE '%Chest Press%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Shoulder Press Machines
UPDATE exercises 
SET equipment = 'Shoulder Press Machine'
WHERE (name LIKE '%Shoulder Press%' OR name LIKE '%Military Press%')
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Leg Curl Machines
UPDATE exercises 
SET equipment = 'Leg Curl Machine'
WHERE name LIKE '%Leg Curl%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Leg Extension Machines
UPDATE exercises 
SET equipment = 'Leg Extension Machine'
WHERE name LIKE '%Leg Extension%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Lat Pulldown Machines
UPDATE exercises 
SET equipment = 'Lat Pulldown Machine'
WHERE name LIKE '%Pulldown%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Row Machines
UPDATE exercises 
SET equipment = 'Row Machine'
WHERE name LIKE '%Row%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%';

-- Calf Raise Machines
UPDATE exercises 
SET equipment = 'Calf Raise Machine'
WHERE name LIKE '%Calf%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Hip Abduction Machines
UPDATE exercises 
SET equipment = 'Hip Abduction Machine'
WHERE name LIKE '%Hip Abduction%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Hip Adduction Machines
UPDATE exercises 
SET equipment = 'Hip Adduction Machine'
WHERE name LIKE '%Hip Adduction%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Pec Deck Machines
UPDATE exercises 
SET equipment = 'Pec Deck Machine'
WHERE name LIKE '%Pec Deck%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Fly Machines (not Pec Deck)
UPDATE exercises 
SET equipment = 'Fly Machine'
WHERE name LIKE '%Fly%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Pec Deck%';

-- Preacher Curl Machines
UPDATE exercises 
SET equipment = 'Preacher Curl Machine'
WHERE name LIKE '%Preacher%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Bicep Curl Machines (not Preacher)
UPDATE exercises 
SET equipment = 'Bicep Curl Machine'
WHERE (name LIKE '%Bicep%' OR name LIKE '%Biceps%')
  AND name LIKE '%Curl%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Preacher%';

-- Tricep Extension/Dip Machines
UPDATE exercises 
SET equipment = 'Tricep Extension Machine'
WHERE (name LIKE '%Tricep Extension%' OR name LIKE '%Tricep Dip%')
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Ab/Core Machines
UPDATE exercises 
SET equipment = 'Ab Machine'
WHERE (name LIKE '%Ab %' OR name LIKE '%Crunch%' OR name LIKE '%Twist%')
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- Shrug Machines
UPDATE exercises 
SET equipment = 'Shrug Machine'
WHERE name LIKE '%Shrug%'
  AND equipment LIKE '%Machine%'
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- VERIFICATION QUERIES (Uncomment to check results)
-- ============================================================================

-- 1. Check no "Lever" prefixes remain in names (should be 0)
-- SELECT name, equipment FROM exercises WHERE name LIKE 'Lever %' ORDER BY name LIMIT 50;

-- 2. Check all machine exercises have proper formatting
-- SELECT name, equipment FROM exercises WHERE equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%' ORDER BY name LIMIT 50;

-- 3. Verify equipment label distribution
-- SELECT equipment, COUNT(*) as count FROM exercises WHERE equipment LIKE '%Machine%' GROUP BY equipment ORDER BY count DESC;

-- 4. Verify cables are separate (should show only "Cables")
-- SELECT DISTINCT equipment FROM exercises WHERE name LIKE '%Cable%' OR equipment LIKE '%Cable%';
