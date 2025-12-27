-- ============================================================================
-- UPDATE EXERCISES FROM CSV
-- ============================================================================
-- This script updates the exercises table with improved data from CSV
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Step 1: Create a temporary staging table
DROP TABLE IF EXISTS exercises_staging;
CREATE TEMP TABLE exercises_staging (
    id UUID,
    name TEXT,
    category TEXT,
    equipment TEXT,
    primary_muscles JSONB,
    secondary_muscles JSONB,
    description TEXT,
    video_code TEXT,
    video_filename TEXT,
    gender TEXT,
    is_custom BOOLEAN,
    created_at TIMESTAMPTZ,
    steps_to_perform TEXT,
    movement_pattern TEXT,
    force_type TEXT,
    movement_type TEXT,
    laterality TEXT,
    plane_of_motion TEXT,
    difficulty_level INTEGER,
    complexity_score INTEGER,
    strength_rating INTEGER,
    hypertrophy_rating INTEGER,
    power_rating INTEGER,
    endurance_rating INTEGER,
    body_position TEXT,
    bench_angle TEXT,
    grip_type TEXT,
    grip_width TEXT,
    optimal_rep_range_min INTEGER,
    optimal_rep_range_max INTEGER,
    placement_in_workout TEXT,
    fatigability INTEGER,
    popularity_score INTEGER,
    home_gym_friendly BOOLEAN,
    instructions TEXT,
    workout_type TEXT
);

-- Step 2: You'll need to use Supabase's UI to import the CSV into exercises_staging
-- OR paste the data here manually
-- 
-- In Supabase Dashboard:
-- 1. Go to Table Editor → exercises_staging
-- 2. Click "Insert" → "Import data from CSV"
-- 3. Upload your CSV file
-- 
-- OR use the Data API to bulk insert

-- Step 3: Update existing exercises from staging table
UPDATE exercises e
SET 
    name = s.name,
    category = s.category,
    equipment = s.equipment,
    primary_muscles = s.primary_muscles,
    secondary_muscles = s.secondary_muscles,
    description = s.description,
    video_code = s.video_code,
    video_filename = s.video_filename,
    gender = s.gender,
    is_custom = s.is_custom,
    steps_to_perform = s.steps_to_perform,
    movement_pattern = s.movement_pattern,
    force_type = s.force_type,
    movement_type = s.movement_type,
    laterality = s.laterality,
    plane_of_motion = s.plane_of_motion,
    difficulty_level = s.difficulty_level,
    complexity_score = s.complexity_score,
    strength_rating = s.strength_rating,
    hypertrophy_rating = s.hypertrophy_rating,
    power_rating = s.power_rating,
    endurance_rating = s.endurance_rating,
    body_position = s.body_position,
    bench_angle = s.bench_angle,
    grip_type = s.grip_type,
    grip_width = s.grip_width,
    optimal_rep_range_min = s.optimal_rep_range_min,
    optimal_rep_range_max = s.optimal_rep_range_max,
    placement_in_workout = s.placement_in_workout,
    fatigability = s.fatigability,
    popularity_score = s.popularity_score,
    home_gym_friendly = s.home_gym_friendly,
    instructions = s.instructions,
    workout_type = s.workout_type,
    updated_at = NOW()
FROM exercises_staging s
WHERE e.id = s.id;

-- Step 4: Report what was updated
SELECT 'Updated exercises: ' || COUNT(*) as result
FROM exercises_staging;

-- Step 5: Clean up
DROP TABLE IF EXISTS exercises_staging;

-- ============================================================================
-- DONE! Your exercises table now has all the improved data
-- ============================================================================

