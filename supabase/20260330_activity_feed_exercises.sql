-- Migration: Embed exercise details in friend activity feed metadata
-- The workout_id stored in friend_activity_feed is a Core Data object ID (not a UUID),
-- so the get_friend_workout_exercises RPC always fails to find exercises.
-- Fix: include exercise details (name, sets, max_weight, max_reps) directly in the
-- metadata JSONB when posting, so friends can view the actual workout.

CREATE OR REPLACE FUNCTION post_workout_activity(
    p_workout_id TEXT,
    p_workout_name TEXT,
    p_duration_seconds INT,
    p_exercise_count INT,
    p_total_sets INT,
    p_xp_earned INT,
    p_muscle_groups TEXT[] DEFAULT '{}',
    p_exercises_json TEXT DEFAULT '[]'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    new_activity_id UUID;
    v_exercises JSONB;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    BEGIN
        v_exercises := p_exercises_json::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_exercises := '[]'::jsonb;
    END;

    INSERT INTO friend_activity_feed (user_id, activity_type, workout_id, metadata)
    VALUES (
        current_user_uuid,
        'workout_completed',
        p_workout_id,
        jsonb_build_object(
            'workout_name', p_workout_name,
            'duration_seconds', p_duration_seconds,
            'exercise_count', p_exercise_count,
            'total_sets', p_total_sets,
            'xp_earned', p_xp_earned,
            'muscle_groups', p_muscle_groups,
            'exercises', v_exercises
        )
    )
    RETURNING id INTO new_activity_id;

    RETURN new_activity_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[], TEXT) TO authenticated;
