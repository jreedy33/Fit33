-- Show me exactly what's in the database for the exercises you're seeing in the app
SELECT name, equipment, category 
FROM exercises 
WHERE name IN (
  'Lever Angled Leg Press',
  'Lever Alternate Biceps',
  'Lever Banded Abdominal Crunch',
  'Lever Belt Romanian Deadlift',
  'Lever Belt Squat',
  'Lever Belt Sumo Squat',
  'Lever Bench Leg Press',
  'Lever Bent Over Low Row',
  'Lever Bent Over Neutral Grip Row'
)
ORDER BY name;

-- If this returns rows, the database still has "Lever" names
-- If this returns 0 rows, your app is showing old cached data
