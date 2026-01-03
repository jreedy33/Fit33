-- ============================================================================
-- VERIFY AND FIX LEVER NAMES - FINAL VERSION
-- ============================================================================

-- 1️⃣ First, check if Lever names still exist in YOUR database
SELECT COUNT(*) FROM exercises WHERE name LIKE 'Lever %';
-- If this returns > 0, the previous updates didn't apply or didn't commit

-- 2️⃣ Show sample of exercises with Lever (to see what we're dealing with)
SELECT name, equipment FROM exercises WHERE name LIKE 'Lever %' ORDER BY name LIMIT 20;

-- ============================================================================
-- 3️⃣ FIX: Remove "Lever " from ALL exercises (works in ALL SQL environments)
-- ============================================================================

-- Method A: For exercises without parentheses
UPDATE exercises
SET name = SUBSTRING(name FROM 7) || ' (Machine)'
WHERE name LIKE 'Lever %'
  AND name NOT LIKE '%(%'
  AND equipment NOT LIKE '%Cable%';

-- Method B: For exercises with parentheses already
UPDATE exercises
SET name = SUBSTRING(name FROM 7)
WHERE name LIKE 'Lever %'
  AND name LIKE '%(%';

-- Method C: Brute force - replace "Lever " with empty string
UPDATE exercises
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE 'Lever %';

-- Method D: Add (Machine) suffix if missing after removal
UPDATE exercises
SET name = name || ' (Machine)'
WHERE equipment LIKE '%Machine%'
  AND name NOT LIKE '%(%'
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- 4️⃣ VERIFY: Check if "Lever" is gone (should return 0)
-- ============================================================================
SELECT COUNT(*) as lever_remaining FROM exercises WHERE name LIKE 'Lever %';
SELECT COUNT(*) as lever_anywhere FROM exercises WHERE name LIKE '%Lever %';

-- ============================================================================
-- 5️⃣ EQUIPMENT FIXES
-- ============================================================================

-- Fix cables (must be separate from machines)
UPDATE exercises SET equipment = 'Cables' WHERE equipment LIKE '%Cable%';

-- Set specific machine labels
UPDATE exercises SET equipment = 'Hack Squat Machine' WHERE name LIKE '%Hack Squat%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Leg Press Machine' WHERE name LIKE '%Leg Press%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Chest Press Machine' WHERE name LIKE '%Chest Press%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Leg Curl Machine' WHERE name LIKE '%Leg Curl%' AND equipment LIKE '%Machine%';
UPDATE exercises SET equipment = 'Leg Extension Machine' WHERE name LIKE '%Leg Extension%' AND equipment LIKE '%Machine%';
UPDATE exercises SET equipment = 'Row Machine' WHERE name LIKE '%Row%' AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';
UPDATE exercises SET equipment = 'Ab Machine' WHERE (name LIKE '%Ab %' OR name LIKE '%Crunch%') AND equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- 6️⃣ COMMIT (Important!)
-- ============================================================================
COMMIT;

-- ============================================================================
-- 7️⃣ FINAL VERIFICATION
-- ============================================================================
-- Run these after the COMMIT to verify everything worked:

-- Should return 0
-- SELECT COUNT(*) FROM exercises WHERE name LIKE 'Lever %';

-- Show updated exercises
-- SELECT name, equipment FROM exercises WHERE equipment LIKE '%Machine%' AND equipment NOT LIKE '%Cable%' ORDER BY name LIMIT 30;
