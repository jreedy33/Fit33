-- Server-side filtered query for stretch exercises
-- Replaces client-side fetchAllExercisesRaw() + filter pattern
-- Used by StretchModeView to fetch only relevant stretches

CREATE OR REPLACE FUNCTION fetch_stretches_for_area(
    p_area text,
    p_gender text DEFAULT NULL,
    p_limit int DEFAULT 8
) RETURNS SETOF exercises AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM exercises
    WHERE (
        workout_type ILIKE '%stretch%'
        OR category ILIKE '%stretch%'
        OR name ILIKE '%stretch%'
    )
    AND video_filename IS NOT NULL
    AND video_filename != ''
    AND (
        p_area = 'Full Body'
        OR exercise_family ILIKE '%stretch_' || LOWER(
            CASE p_area
                WHEN 'Upper Body' THEN 'chest%'
                WHEN 'Lower Body' THEN 'leg%'
                ELSE REPLACE(LOWER(p_area), ' ', '_')
            END
        ) || '%'
        OR exercise_family ILIKE '%' || REPLACE(LOWER(p_area), ' ', '_') || '_stretch%'
        OR (p_area = 'Upper Body' AND (
            primary_muscles::text ILIKE '%chest%'
            OR primary_muscles::text ILIKE '%bicep%'
            OR primary_muscles::text ILIKE '%tricep%'
            OR primary_muscles::text ILIKE '%pectoralis%'
        ))
        OR (p_area = 'Lower Body' AND (
            primary_muscles::text ILIKE '%quad%'
            OR primary_muscles::text ILIKE '%hamstring%'
            OR primary_muscles::text ILIKE '%calf%'
            OR primary_muscles::text ILIKE '%glute%'
        ))
        OR (p_area = 'Back' AND (
            primary_muscles::text ILIKE '%lat%'
            OR primary_muscles::text ILIKE '%erector%'
            OR primary_muscles::text ILIKE '%rhomboid%'
            OR primary_muscles::text ILIKE '%trapezius%'
        ))
        OR (p_area = 'Hips' AND (
            primary_muscles::text ILIKE '%hip%'
            OR primary_muscles::text ILIKE '%psoas%'
            OR primary_muscles::text ILIKE '%piriformis%'
            OR primary_muscles::text ILIKE '%adductor%'
        ))
        OR (p_area = 'Shoulders' AND (
            primary_muscles::text ILIKE '%deltoid%'
            OR primary_muscles::text ILIKE '%rotator%'
            OR primary_muscles::text ILIKE '%shoulder%'
        ))
        OR (p_area = 'Legs' AND (
            primary_muscles::text ILIKE '%quadriceps%'
            OR primary_muscles::text ILIKE '%hamstrings%'
            OR primary_muscles::text ILIKE '%calves%'
            OR primary_muscles::text ILIKE '%gastrocnemius%'
        ))
        OR (p_area = 'Neck' AND (
            primary_muscles::text ILIKE '%neck%'
            OR primary_muscles::text ILIKE '%sternocleidomastoid%'
            OR primary_muscles::text ILIKE '%levator%'
            OR primary_muscles::text ILIKE '%scalene%'
        ))
    )
    AND (p_gender IS NULL OR video_filename ILIKE '%' || p_gender || '%')
    ORDER BY RANDOM()
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Index to speed up stretch queries
CREATE INDEX IF NOT EXISTS idx_exercises_stretch_lookup
    ON exercises (workout_type, video_filename)
    WHERE video_filename IS NOT NULL AND video_filename != '';
