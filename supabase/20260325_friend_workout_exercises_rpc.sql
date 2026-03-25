-- RPC: get_friend_workout_exercises
-- Returns workout exercises for a given workout_history row,
-- gated behind a friendship check so only friends can view each other's workouts.
-- Also pulls top-set data from exercise_performance_history when available.

CREATE OR REPLACE FUNCTION public.get_friend_workout_exercises(
    p_workout_id text
)
RETURNS TABLE (
    id              text,
    exercise_name   text,
    "order"         int,
    sets_completed  int,
    max_weight      double precision,
    max_reps        int,
    total_volume    double precision
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_owner_id uuid;
    v_caller   uuid := auth.uid();
BEGIN
    -- Resolve workout owner
    SELECT user_id INTO v_owner_id
    FROM workout_history
    WHERE workout_history.id = p_workout_id;

    IF v_owner_id IS NULL THEN
        RETURN;
    END IF;

    -- Allow if caller owns the workout OR is friends with the owner
    IF v_owner_id <> v_caller THEN
        IF NOT EXISTS (
            SELECT 1 FROM friendships
            WHERE status = 'accepted'
              AND (
                  (friendships.user_id = v_caller AND friendships.friend_id = v_owner_id)
               OR (friendships.user_id = v_owner_id AND friendships.friend_id = v_caller)
              )
        ) THEN
            RETURN;
        END IF;
    END IF;

    RETURN QUERY
    SELECT
        e.id::text,
        e.exercise_name,
        COALESCE(e."order", 0),
        COALESCE(e.sets_completed, 0),
        p.max_weight,
        p.max_reps,
        p.total_volume
    FROM workout_exercises e
    LEFT JOIN exercise_performance_history p
        ON p.exercise_name = e.exercise_name
       AND p.workout_id = p_workout_id
    WHERE e.workout_id = p_workout_id
    ORDER BY COALESCE(e."order", 0);
END;
$$;
