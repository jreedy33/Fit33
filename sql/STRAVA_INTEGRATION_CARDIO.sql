-- ============================================================================
-- STRAVA INTEGRATION WITH CARDIO WORKOUTS
-- ============================================================================
-- This migration adds source tracking to cardio_workouts so Strava activities
-- appear in the Recent Activity feed and count towards goals/insights
-- ============================================================================

-- ============================================================================
-- Step 1: Add source tracking columns to cardio_workouts
-- ============================================================================

-- Source of the workout (app, strava, apple_health, etc.)
ALTER TABLE cardio_workouts 
ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'app';

-- External ID for deduplication (e.g., Strava activity ID)
ALTER TABLE cardio_workouts 
ADD COLUMN IF NOT EXISTS external_id TEXT;

-- External source URL (link to Strava activity, etc.)
ALTER TABLE cardio_workouts 
ADD COLUMN IF NOT EXISTS external_url TEXT;

-- Total elevation gain (useful for Strava activities)
ALTER TABLE cardio_workouts 
ADD COLUMN IF NOT EXISTS total_elevation_gain DOUBLE PRECISION;

-- Add index for efficient external ID lookups
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_external 
ON cardio_workouts(user_id, source, external_id);

-- Add constraint to prevent duplicate external imports
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_workouts_external_unique 
ON cardio_workouts(user_id, source, external_id) 
WHERE external_id IS NOT NULL;

-- ============================================================================
-- Step 2: Update RLS policies (unchanged - existing policies work)
-- ============================================================================
-- Existing policies allow all cardio_workouts regardless of source

-- ============================================================================
-- Step 3: Create helper function to import Strava activities
-- ============================================================================
CREATE OR REPLACE FUNCTION import_strava_activity(
    p_user_id UUID,
    p_strava_id TEXT,
    p_name TEXT,
    p_activity_type TEXT,
    p_start_date TIMESTAMPTZ,
    p_duration_seconds INTEGER,
    p_distance_meters DOUBLE PRECISION,
    p_calories INTEGER,
    p_average_speed DOUBLE PRECISION,
    p_max_speed DOUBLE PRECISION,
    p_average_heartrate INTEGER,
    p_max_heartrate INTEGER,
    p_elevation_gain DOUBLE PRECISION
) RETURNS UUID AS $$
DECLARE
    v_workout_id UUID;
    v_activity_type TEXT;
BEGIN
    -- Map Strava activity type to app's activity type
    v_activity_type := CASE LOWER(p_activity_type)
        WHEN 'run' THEN 'outdoor_run'
        WHEN 'ride' THEN 'outdoor_cycle'
        WHEN 'walk' THEN 'walk'
        WHEN 'hike' THEN 'walk'
        WHEN 'swim' THEN 'swimming'
        WHEN 'virtualrun' THEN 'treadmill'
        WHEN 'virtualride' THEN 'indoor_cycle'
        WHEN 'rowing' THEN 'rowing'
        WHEN 'elliptical' THEN 'elliptical'
        WHEN 'stairstepper' THEN 'stair_climber'
        WHEN 'workout' THEN 'hiit'
        WHEN 'crossfit' THEN 'hiit'
        ELSE 'outdoor_run' -- Default to outdoor run
    END;

    -- Insert or update (upsert) the workout
    INSERT INTO cardio_workouts (
        user_id,
        activity_type,
        workout_name,
        goal_type,
        goal_achieved,
        duration_seconds,
        distance_meters,
        calories_burned,
        average_speed,
        max_speed,
        average_heart_rate,
        max_heart_rate,
        total_elevation_gain,
        started_at,
        completed_at,
        source,
        external_id,
        external_url
    ) VALUES (
        p_user_id,
        v_activity_type,
        p_name,
        'open_goal', -- Strava doesn't have goal info, use open_goal
        TRUE, -- Mark as achieved since it's already completed
        p_duration_seconds,
        COALESCE(p_distance_meters, 0),
        COALESCE(p_calories, 0),
        CASE WHEN p_average_speed > 0 THEN p_average_speed * 3.6 ELSE NULL END, -- m/s to km/h
        CASE WHEN p_max_speed > 0 THEN p_max_speed * 3.6 ELSE NULL END, -- m/s to km/h
        NULLIF(p_average_heartrate, 0),
        NULLIF(p_max_heartrate, 0),
        p_elevation_gain,
        p_start_date,
        p_start_date + (p_duration_seconds || ' seconds')::INTERVAL,
        'strava',
        p_strava_id,
        'https://www.strava.com/activities/' || p_strava_id
    )
    ON CONFLICT (user_id, source, external_id) 
    WHERE external_id IS NOT NULL
    DO UPDATE SET
        workout_name = EXCLUDED.workout_name,
        duration_seconds = EXCLUDED.duration_seconds,
        distance_meters = EXCLUDED.distance_meters,
        calories_burned = EXCLUDED.calories_burned,
        average_speed = EXCLUDED.average_speed,
        max_speed = EXCLUDED.max_speed,
        average_heart_rate = EXCLUDED.average_heart_rate,
        max_heart_rate = EXCLUDED.max_heart_rate,
        total_elevation_gain = EXCLUDED.total_elevation_gain,
        updated_at = NOW()
    RETURNING id INTO v_workout_id;

    RETURN v_workout_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Step 4: Grant execute permission
-- ============================================================================
GRANT EXECUTE ON FUNCTION import_strava_activity TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Strava integration migration complete!';
    RAISE NOTICE '   - Added source column to cardio_workouts';
    RAISE NOTICE '   - Added external_id for deduplication';
    RAISE NOTICE '   - Added external_url for linking';
    RAISE NOTICE '   - Created import_strava_activity function';
    RAISE NOTICE '';
    RAISE NOTICE 'Strava activities will now:';
    RAISE NOTICE '   ✓ Appear in Recent Activity feed';
    RAISE NOTICE '   ✓ Count towards cardio streaks';
    RAISE NOTICE '   ✓ Update weekly summaries';
    RAISE NOTICE '   ✓ Factor into insights and goals';
END $$;
