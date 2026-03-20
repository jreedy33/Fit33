-- Exercise Data Replace: Final Step - Merge and cleanup
-- Run this AFTER all data files have been executed

BEGIN;

-- Verify staging table has expected row count
DO $$
DECLARE
    staging_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO staging_count FROM _exercise_staging;
    RAISE NOTICE 'Staging table has % exercises', staging_count;
    IF staging_count < 100 THEN
        RAISE EXCEPTION 'Staging table has too few rows (%). Did you run all data files?', staging_count;
    END IF;
END $$;

-- Step 1: Update existing exercises with new data
-- (bench_angle cast to INTEGER to match actual DB column type)
UPDATE exercises e SET
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
    bench_angle = s.bench_angle::INTEGER,
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
    practicality_score = s.practicality_score,
    fat_loss_rating = s.fat_loss_rating,
    general_fitness_rating = s.general_fitness_rating,
    is_compound = s.is_compound,
    supersetable = s.supersetable,
    exercise_family = s.exercise_family,
    base_exercise_name = s.base_exercise_name,
    complementary_families = s.complementary_families,
    is_equipment_primary = s.is_equipment_primary,
    equipment_category = s.equipment_category,
    duration_based = s.duration_based,
    recommended_sets = s.recommended_sets,
    rest_seconds = s.rest_seconds,
    muscles_worked_count = s.muscles_worked_count,
    priority_build_muscle = s.priority_build_muscle,
    priority_get_lean = s.priority_get_lean,
    priority_home = s.priority_home,
    priority_gym = s.priority_gym
FROM _exercise_staging s
WHERE e.id = s.id;

-- Step 2: Insert exercises that are new (exist in staging but not in exercises)
-- (bench_angle cast to INTEGER to match actual DB column type)
INSERT INTO exercises (id, name, category, equipment, primary_muscles, secondary_muscles, description, video_code, video_filename, gender, is_custom, created_at, steps_to_perform, movement_pattern, force_type, movement_type, laterality, plane_of_motion, difficulty_level, complexity_score, strength_rating, hypertrophy_rating, power_rating, endurance_rating, body_position, bench_angle, grip_type, grip_width, optimal_rep_range_min, optimal_rep_range_max, placement_in_workout, fatigability, popularity_score, home_gym_friendly, instructions, workout_type, practicality_score, fat_loss_rating, general_fitness_rating, is_compound, supersetable, exercise_family, base_exercise_name, complementary_families, is_equipment_primary, equipment_category, duration_based, recommended_sets, rest_seconds, muscles_worked_count, priority_build_muscle, priority_get_lean, priority_home, priority_gym)
SELECT id, name, category, equipment, primary_muscles, secondary_muscles, description, video_code, video_filename, gender, is_custom, created_at, steps_to_perform, movement_pattern, force_type, movement_type, laterality, plane_of_motion, difficulty_level, complexity_score, strength_rating, hypertrophy_rating, power_rating, endurance_rating, body_position, bench_angle::INTEGER, grip_type, grip_width, optimal_rep_range_min, optimal_rep_range_max, placement_in_workout, fatigability, popularity_score, home_gym_friendly, instructions, workout_type, practicality_score, fat_loss_rating, general_fitness_rating, is_compound, supersetable, exercise_family, base_exercise_name, complementary_families, is_equipment_primary, equipment_category, duration_based, recommended_sets, rest_seconds, muscles_worked_count, priority_build_muscle, priority_get_lean, priority_home, priority_gym
FROM _exercise_staging s
WHERE NOT EXISTS (SELECT 1 FROM exercises e WHERE e.id = s.id);

-- Step 3: Delete exercises that were removed (exist in DB but not in new data)
-- Only deletes non-custom exercises to preserve user-created ones
DELETE FROM exercises
WHERE is_custom = FALSE
  AND id NOT IN (SELECT id FROM _exercise_staging);

-- Report results
DO $$
DECLARE
    final_count INTEGER;
    custom_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO final_count FROM exercises WHERE is_custom = FALSE;
    SELECT COUNT(*) INTO custom_count FROM exercises WHERE is_custom = TRUE;
    RAISE NOTICE '✅ Exercise replace complete!';
    RAISE NOTICE '   Standard exercises: %', final_count;
    RAISE NOTICE '   Custom (user) exercises preserved: %', custom_count;
END $$;

COMMIT;

-- Step 4: Refresh materialized view if it exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises'
    ) THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_public_exercises;
        RAISE NOTICE '✅ Materialized view mv_public_exercises refreshed';
    ELSE
        RAISE NOTICE 'ℹ️ No materialized view to refresh';
    END IF;
END $$;

-- Step 5: Drop staging table
DROP TABLE IF EXISTS _exercise_staging;
