-- ============================================================================
-- CHECK WHAT'S ACTUALLY IN THE DATABASE RIGHT NOW
-- ============================================================================

-- 1. Show me ALL exercises that start with "Lever" (actual data)
SELECT id, name, equipment, category 
FROM exercises 
WHERE name LIKE 'Lever %'
ORDER BY name
LIMIT 50;

-- 2. Count them
SELECT COUNT(*) as total_with_lever
FROM exercises 
WHERE name LIKE 'Lever %';

-- 3. Show me a few examples from what you're seeing in the app
SELECT id, name, equipment 
FROM exercises 
WHERE name IN (
  'Lever Angled Leg Press',
  'Lever Alternate Biceps',
  'Lever Banded Abdominal Crunch',
  'Lever Belt Romanian Deadlift',
  'Lever Belt Squat',
  'Lever Belt Sumo Squat',
  'Lever Bench Leg Press',
  'Lever Bent Over Low Row'
);
