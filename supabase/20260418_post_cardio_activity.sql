-- ============================================================================
-- post_cardio_activity — friend_activity_feed row for a completed cardio
-- session (Sprint 2 Q2-5). Mirrors post_workout_activity but writes
-- activity_type = 'cardio_completed' with cardio-specific metadata.
-- ============================================================================

CREATE OR REPLACE FUNCTION post_cardio_activity(
    p_workout_id TEXT,
    p_activity_type TEXT,
    p_duration_seconds INT,
    p_distance_meters DOUBLE PRECISION DEFAULT 0,
    p_calories_burned INT DEFAULT 0,
    p_average_heart_rate INT DEFAULT NULL,
    p_xp_earned INT DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_activity_id UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    INSERT INTO friend_activity_feed (user_id, activity_type, workout_id, metadata)
    VALUES (
        current_user_uuid,
        'cardio_completed',
        p_workout_id,
        jsonb_build_object(
            'cardio_type', p_activity_type,
            'duration_seconds', p_duration_seconds,
            'distance_meters', p_distance_meters,
            'calories_burned', p_calories_burned,
            'average_heart_rate', p_average_heart_rate,
            'xp_earned', p_xp_earned
        )
    )
    RETURNING id INTO new_activity_id;

    RETURN new_activity_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_cardio_activity(TEXT, TEXT, INT, DOUBLE PRECISION, INT, INT, INT)
    TO authenticated;

COMMENT ON FUNCTION post_cardio_activity(TEXT, TEXT, INT, DOUBLE PRECISION, INT, INT, INT) IS
  'Sprint 2: write a cardio_completed row to friend_activity_feed. Mirrors '
  'post_workout_activity. Metadata carries cardio-type (run/walk/bike/...), '
  'distance, calories, avg HR, and earned XP.';
