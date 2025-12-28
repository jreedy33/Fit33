-- ============================================================================
-- EXERCISE DATABASE FIXES
-- Generated from audit on 2024-12-27
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================================

-- 30. Smith Reverse Grip Press
-- Issue: CLASSIFICATION: Incorrectly labeled as Forearms primary (should be Chest/Triceps)
-- Reverse grip bench press primarily works chest and triceps, forearms are stabilizers
UPDATE exercises 
SET category = 'Chest', primary_muscles = ARRAY['Chest', 'Triceps'], secondary_muscles = ARRAY['Front Delts', 'Forearms']
WHERE id = '345916fc-03d1-4b50-b00f-f84e25c4bedd';

-- ============================================================================
-- COMBO RULE ENFORCEMENT DOCUMENTATION
-- ============================================================================
-- 
-- The following combo rules are now HARD-ENFORCED in the workout generator:
--
-- Back + Biceps MUST include:
--   1. vertical_pull (pulldown or pull-up)
--   2. horizontal_row (seated row, chest-supported row, or machine row)
--   3. bicep_curl (any curl variation)
--   4. rear_delt (balance slot - face pull or reverse fly)
--
-- Back + Biceps MUST NOT include:
--   - Press variations (unless Chest or Shoulders also selected)
--   - Dips (pressing movements)
--   - More than 2 curl variations (caps enforced)
--
-- Back + Biceps Slot Distribution (E=6):
--   - Back: 4 exercises (vertical pull, horizontal row, rear delt, lat accessory)
--   - Biceps: 1-2 exercises (max 2 curls)
--
-- 30. Smith Reverse Grip Press
-- Issue: MUSCLE: Incorrectly labeled as Forearms (should be Chest/Triceps)
-- Reverse grip bench press primarily targets chest and triceps, not forearms
UPDATE exercises 
SET category = 'Chest', primary_muscles = ARRAY['Chest', 'Triceps']
WHERE name = 'Smith Reverse Grip Press';

-- 31. Wide Grip Pull Up On Dip Cage
-- Issue: CLASSIFICATION: Incorrectly labeled as Chest (should be Back)
-- Pull-ups primarily work back/lats, not chest
UPDATE exercises 
SET 
    category = 'Back', 
    primary_muscles = ARRAY['Lats', 'Upper Back'],
    secondary_muscles = ARRAY['Biceps', 'Rear Delts'],
    exercise_family = 'pullup',
    complementary_families = 'row, lat_pulldown, bicep_curl'
WHERE id = '2411472d-70c9-4a32-aba1-685ccb2e7ee3';

-- ============================================================================
-- VERIFICATION QUERY - Run after applying fixes to confirm changes
-- ============================================================================
SELECT id, name, category, primary_muscles, secondary_muscles, exercise_family
FROM exercises 
WHERE id IN (
    '345916fc-03d1-4b50-b00f-f84e25c4bedd',
    '2411472d-70c9-4a32-aba1-685ccb2e7ee3'
)
ORDER BY name;
