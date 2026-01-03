-- ============================================================================
-- REMOVE "LEVER" FROM ALL EXERCISE NAMES - AGGRESSIVE VERSION
-- ============================================================================
-- This script will remove "Lever " from ALL exercise names regardless of conditions
-- ============================================================================

-- ============================================================================
-- STEP 1: FIX CABLES FIRST (Keep completely separate)
-- ============================================================================

UPDATE exercises 
SET equipment = 'Cables'
WHERE equipment LIKE '%Cable%';

-- ============================================================================
-- STEP 2: REMOVE "LEVER" FROM ALL EXERCISE NAMES
-- ============================================================================

-- Case 1: Exercises that already have parentheses - just remove "Lever "
-- Example: "Lever Low Row (Plate Loaded)" → "Low Row (Plate Loaded)"
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%';

-- Case 2: Exercises WITHOUT parentheses - remove "Lever " and add "(Machine)"
-- Example: "Lever Angled Leg Press" → "Angled Leg Press (Machine)"
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '') || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%';

-- Case 3: Double-check - if any still have "Lever" at start, force remove it
UPDATE exercises
SET name = SUBSTRING(name FROM 7) || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND LENGTH(name) > 6;

-- Case 4: Ultra-aggressive - catch any remaining with "Lever " anywhere
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE '%Lever %';

-- ============================================================================
-- STEP 3: SET EQUIPMENT LABELS (Specific machine types)
-- ============================================================================

-- Specific machine types (keep descriptive labels)
UPDATE exercises SET equipment = 'Hack Squat Machine' WHERE name LIKE '%Hack Squat%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Leg Press Machine' WHERE name LIKE '%Leg Press%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Chest Press Machine' WHERE name LIKE '%Chest Press%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Shoulder Press Machine' WHERE name LIKE '%Shoulder Press%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Leg Curl Machine' WHERE name LIKE '%Leg Curl%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Leg Extension Machine' WHERE name LIKE '%Leg Extension%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Lat Pulldown Machine' WHERE name LIKE '%Pulldown%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Row Machine' WHERE name LIKE '%Row%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Calf Raise Machine' WHERE name LIKE '%Calf%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Ab Machine' WHERE (name LIKE '%Ab %' OR name LIKE '%Crunch%') AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Bicep Curl Machine' WHERE name LIKE '%Bicep%' AND name LIKE '%Curl%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Tricep Extension Machine' WHERE name LIKE '%Tricep%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Preacher Curl Machine' WHERE name LIKE '%Preacher%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Hip Abduction Machine' WHERE name LIKE '%Hip Abduction%' AND equipment LIKE '%Machine%';
UPDATE exercises SET equipment = 'Hip Adduction Machine' WHERE name LIKE '%Hip Adduction%' AND equipment LIKE '%Machine%';
UPDATE exercises SET equipment = 'Pec Deck Machine' WHERE name LIKE '%Pec Deck%' AND equipment LIKE '%Machine%';
UPDATE exercises SET equipment = 'Fly Machine' WHERE name LIKE '%Fly%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Shrug Machine' WHERE name LIKE '%Shrug%' AND equipment LIKE '%Machine%';

-- ============================================================================
-- VERIFICATION - Run these to check (uncomment one at a time)
-- ============================================================================

-- Should return 0 rows
-- SELECT name, equipment FROM exercises WHERE name LIKE 'Lever %';

-- Should return 0 rows
-- SELECT name, equipment FROM exercises WHERE name LIKE '%Lever %';

-- Check results
-- SELECT name, equipment FROM exercises WHERE equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%' ORDER BY name LIMIT 100;
