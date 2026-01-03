-- ============================================================================
-- MACHINE & CABLE EXERCISE NAMING STANDARDIZATION V2
-- ============================================================================
-- 
-- NEW APPROACH:
--   ✅ Keep specific machine labels: "Hack Squat Machine", "Leg Press Machine"
--   ✅ Use "Lever Machine" only for generic/unknown machines
--   ✅ Exercise names: "[Exercise] (Machine)" or "[Exercise] (Plate Loaded)"
--   ✅ Cables completely separate: "Cables" equipment, never mixed with machines
--
-- EXAMPLES:
--   ✅ "Linear Hack Squat (Machine)" [Hack Squat Machine]
--   ✅ "Leg Press (Machine)" [Leg Press Machine]
--   ✅ "Low Row (Plate Loaded)" [Lever Machine] - unknown machine type
--   ✅ "Lying Chest Press (Machine)" [Chest Press Machine]
--   ✅ "Cable Curl (Cable)" [Cables] - NOT "Cable Machine"
--
-- ============================================================================

-- ============================================================================
-- STEP 1: SEPARATE CABLES FROM MACHINES
-- ============================================================================

-- Fix equipment: "Cable Machine" → "Cables"
UPDATE exercises 
SET equipment = 'Cables'
WHERE equipment LIKE '%Cable%';

-- Fix names: "(Cable Machine)" → "(Cable)"
UPDATE exercises 
SET name = REPLACE(name, '(Cable Machine)', '(Cable)')
WHERE name LIKE '%(Cable Machine)%';

UPDATE exercises 
SET name = REPLACE(name, 'Cable Machine', 'Cable')
WHERE name LIKE '%Cable Machine%';

-- ============================================================================
-- STEP 2: SET SPECIFIC MACHINE EQUIPMENT LABELS (Most Specific First)
-- ============================================================================

-- Hack Squat Machines
UPDATE exercises 
SET equipment = 'Hack Squat Machine'
WHERE (name LIKE '%Hack Squat%' OR name LIKE '%Hack%Squat%')
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%';

-- Leg Press Machines
UPDATE exercises 
SET equipment = 'Leg Press Machine'
WHERE name LIKE '%Leg Press%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%';

-- Chest Press Machines
UPDATE exercises 
SET equipment = 'Chest Press Machine'
WHERE name LIKE '%Chest Press%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%';

-- Shoulder Press Machines
UPDATE exercises 
SET equipment = 'Shoulder Press Machine'
WHERE (name LIKE '%Shoulder Press%' OR name LIKE '%Military Press%')
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%';

-- Leg Curl Machines
UPDATE exercises 
SET equipment = 'Leg Curl Machine'
WHERE name LIKE '%Leg Curl%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Leg Extension Machines
UPDATE exercises 
SET equipment = 'Leg Extension Machine'
WHERE name LIKE '%Leg Extension%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Lat Pulldown Machines
UPDATE exercises 
SET equipment = 'Lat Pulldown Machine'
WHERE name LIKE '%Pulldown%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Row Machines
UPDATE exercises 
SET equipment = 'Row Machine'
WHERE name LIKE '%Row%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Smith%'
  AND equipment NOT LIKE '%Barbell%'
  AND equipment NOT LIKE '%Dumbbell%';

-- Calf Raise Machines
UPDATE exercises 
SET equipment = 'Calf Raise Machine'
WHERE name LIKE '%Calf%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Hip Abduction Machines
UPDATE exercises 
SET equipment = 'Hip Abduction Machine'
WHERE name LIKE '%Hip Abduction%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Hip Adduction Machines
UPDATE exercises 
SET equipment = 'Hip Adduction Machine'
WHERE name LIKE '%Hip Adduction%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Pec Deck Machines
UPDATE exercises 
SET equipment = 'Pec Deck Machine'
WHERE name LIKE '%Pec Deck%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Fly Machines (generic chest fly)
UPDATE exercises 
SET equipment = 'Fly Machine'
WHERE name LIKE '%Fly%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Pec Deck%';

-- Preacher Curl Machines
UPDATE exercises 
SET equipment = 'Preacher Curl Machine'
WHERE name LIKE '%Preacher%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Bicep Curl Machines (not preacher)
UPDATE exercises 
SET equipment = 'Bicep Curl Machine'
WHERE (name LIKE '%Bicep%' OR name LIKE '%Biceps%')
  AND name LIKE '%Curl%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%'
  AND equipment NOT LIKE '%Preacher%';

-- Tricep Extension/Dip Machines
UPDATE exercises 
SET equipment = 'Tricep Extension Machine'
WHERE (name LIKE '%Tricep Extension%' OR name LIKE '%Tricep Dip%')
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Ab/Core Machines
UPDATE exercises 
SET equipment = 'Ab Machine'
WHERE (name LIKE '%Ab %' OR name LIKE '%Crunch%' OR name LIKE '%Twist%')
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- Shrug Machines
UPDATE exercises 
SET equipment = 'Shrug Machine'
WHERE name LIKE '%Shrug%'
  AND (equipment LIKE '%Lever%' OR equipment LIKE '%Machine%')
  AND equipment NOT LIKE '%Cable%';

-- FALLBACK: Generic "Lever Machine" for remaining lever equipment
UPDATE exercises 
SET equipment = 'Lever Machine'
WHERE equipment LIKE '%Lever%' 
  AND equipment NOT IN (
    'Hack Squat Machine', 'Leg Press Machine', 'Chest Press Machine',
    'Leg Curl Machine', 'Leg Extension Machine', 'Shoulder Press Machine',
    'Lat Pulldown Machine', 'Row Machine', 'Calf Raise Machine',
    'Hip Abduction Machine', 'Hip Adduction Machine', 'Pec Deck Machine',
    'Fly Machine', 'Bicep Curl Machine', 'Tricep Extension Machine',
    'Preacher Curl Machine', 'Ab Machine', 'Shrug Machine', 'Lever Machine'
  )
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- STEP 3: UPDATE EXERCISE NAMES - Remove "Lever" prefix
-- ============================================================================

-- Generic REGEXP update (removes "Lever" and adds appropriate suffix)
UPDATE exercises
SET name = REGEXP_REPLACE(name, '^Lever\s+(.+)$', '\1 (Machine)', 'i')
WHERE LOWER(name) LIKE 'lever %'
  AND name NOT LIKE '%(Machine)%'
  AND name NOT LIKE '%(Plate%'
  AND equipment NOT LIKE '%Cable%';

-- ============================================================================
-- STEP 4: HANDLE PLATE LOADED VARIATIONS
-- ============================================================================

UPDATE exercises
SET name = REGEXP_REPLACE(name, '^Lever\s+(.+)\s*\(?Plate.*\)?$', '\1 (Plate Loaded)', 'i')
WHERE LOWER(name) LIKE 'lever %'
  AND (name LIKE '%Plate%' OR name LIKE '%plate%')
  AND equipment NOT LIKE '%Cable%';

-- Fallback for plate loaded
UPDATE exercises 
SET name = REPLACE(name, 'Lever ', '')
WHERE name LIKE 'Lever %Plate%';

-- ============================================================================
-- STEP 5: SPECIFIC EXERCISE CORRECTIONS (From User's Screenshot)
-- ============================================================================

-- Linear Hack Squat
UPDATE exercises 
SET name = 'Linear Hack Squat (Machine)'
WHERE name LIKE 'Lever Linear Hack Squat%' 
  AND name NOT LIKE '%(%';

-- Low Row with plate loaded
UPDATE exercises 
SET name = 'Low Row (Plate Loaded)'
WHERE name LIKE 'Lever Low Row%' 
  AND name LIKE '%Plate%';

UPDATE exercises 
SET name = 'Low Row (Machine)'
WHERE name LIKE 'Lever Low Row%' 
  AND name NOT LIKE '%(%' 
  AND name NOT LIKE '%Plate%';

-- Lying variations
UPDATE exercises SET name = 'Lying Chest Press (Machine)' WHERE name LIKE 'Lever Lying Chest Press%' AND name NOT LIKE '%(%';
UPDATE exercises SET name = 'Lying Crunch (Machine)' WHERE name LIKE 'Lever Lying Crunch%' AND name NOT LIKE '%(%';
UPDATE exercises SET name = 'Lying Decline Chest Press (Machine)' WHERE name LIKE 'Lever Lying Decline%Chest%' AND name NOT LIKE '%(%';
UPDATE exercises SET name = 'Lying Knee Flexion (Machine)' WHERE name LIKE 'Lever Lying Knee Flexion%' AND name NOT LIKE '%(%';

-- ============================================================================
-- STEP 6: FINAL CLEANUP - Ensure No Cable/Machine Mixing
-- ============================================================================

-- Safety: Remove "Machine" from cable equipment
UPDATE exercises 
SET equipment = 'Cables'
WHERE equipment LIKE '%Cable%';

-- ============================================================================
-- ✅ VERIFICATION QUERIES
-- ============================================================================

-- 1. Check no "Lever" prefixes remain (should be 0 rows)
-- SELECT name, equipment FROM exercises WHERE LOWER(name) LIKE 'lever %' ORDER BY name;

-- 2. Check no cable/machine mixing (should be 0 rows)
-- SELECT name, equipment FROM exercises WHERE equipment LIKE '%Cable%' AND equipment LIKE '%Machine%';

-- 3. See all distinct machine equipment labels
-- SELECT DISTINCT equipment, COUNT(*) as count 
-- FROM exercises 
-- WHERE equipment LIKE '%Machine%' OR equipment LIKE '%Lever%'
-- GROUP BY equipment 
-- ORDER BY count DESC;

-- 4. Sample of updated exercises
-- SELECT name, equipment, category FROM exercises WHERE equipment LIKE '%Machine%' ORDER BY name LIMIT 30;
