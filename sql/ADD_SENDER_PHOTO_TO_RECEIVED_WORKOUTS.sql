-- =====================================================
-- ADD SENDER PROFILE PHOTO TO RECEIVED WORKOUTS
-- Updates get_received_workouts to include sender photo
-- =====================================================

-- Drop existing function first (return type changed)
DROP FUNCTION IF EXISTS get_received_workouts();

-- Recreate with sender's profile photo included
CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    workout_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_username TEXT,
    sender_profile_photo_url TEXT,
    workout_name TEXT,
    workout_description TEXT,
    exercises JSONB,
    message TEXT,
    status TEXT,
    estimated_duration INT,
    difficulty_level TEXT,
    created_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.sender_id,
        COALESCE(up.name, u.email, 'Unknown')::text as sender_name,
        up.username::text as sender_username,
        up.profile_photo_url::text as sender_profile_photo_url,
        sw.workout_name::text,
        sw.workout_description::text,
        sw.exercises,
        sw.message::text,
        sw.status::text,
        sw.estimated_duration,
        sw.difficulty_level::text,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites
    FROM shared_workouts sw
    LEFT JOIN user_profiles up ON up.id::text = sw.sender_id::text
    LEFT JOIN auth.users u ON u.id = sw.sender_id
    WHERE sw.recipient_id = current_user_id
    ORDER BY sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
