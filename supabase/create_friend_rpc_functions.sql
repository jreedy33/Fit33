-- ============================================================================
-- MISSING RPC FUNCTIONS FOR FRIEND SYSTEM
-- ============================================================================
-- These functions are called by the iOS app but were missing from the database
-- causing 100+ second timeouts on the Profile screen
--
-- DEPLOY THIS IMMEDIATELY to fix Abigail's Strava sync issue and profile loading
-- ============================================================================

-- ============================================================================
-- DROP EXISTING FUNCTIONS (if they exist with wrong signatures)
-- ============================================================================
DROP FUNCTION IF EXISTS get_friends();
DROP FUNCTION IF EXISTS get_received_workouts();
DROP FUNCTION IF EXISTS get_sent_workouts();

-- ============================================================================
-- FUNCTION: get_friends
-- Returns all accepted friendships for the current user
-- ============================================================================
CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID,
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    friend_username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    profile_photo_url TEXT,
    friends_since TIMESTAMPTZ,
    total_workouts_shared INT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return all accepted friendships (bidirectional)
    -- Return friends where current user is either requester or addressee
    RETURN QUERY
    SELECT 
        f.id as friendship_id,
        CASE 
            WHEN f.requester_id = current_user_uuid THEN f.addressee_id
            ELSE f.requester_id
        END as friend_id,
        up.name as friend_name,
        up.email as friend_email,
        up.username as friend_username,
        up.fitness_goal,
        up.experience_level,
        up.profile_photo_url,
        f.created_at as friends_since,
        COALESCE((
            SELECT COUNT(*)::INT
            FROM shared_workouts sw
            WHERE (sw.sender_id = current_user_uuid AND sw.recipient_id = up.id)
               OR (sw.sender_id = up.id AND sw.recipient_id = current_user_uuid)
        ), 0) as total_workouts_shared
    FROM friendships f
    JOIN user_profiles up ON up.id = CASE 
        WHEN f.requester_id = current_user_uuid THEN f.addressee_id
        ELSE f.requester_id
    END
    WHERE (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid)
      AND f.status = 'accepted'
    ORDER BY f.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_friends() IS 
  'Returns all accepted friendships for the current user. Called when loading friends list.';

GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;

-- ============================================================================
-- FUNCTION: get_received_workouts
-- Returns workouts shared with the current user from friends
-- ============================================================================
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
    exercise_names TEXT[],
    message TEXT,
    status TEXT,
    estimated_duration INT,
    difficulty_level TEXT,
    created_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return workouts shared with current user
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.sender_id,
        up.name as sender_name,
        up.username as sender_username,
        up.profile_photo_url as sender_profile_photo_url,
        sw.workout_name,
        sw.workout_description,
        sw.exercises::JSONB,
        sw.exercise_names,
        sw.message,
        sw.status::TEXT,
        sw.estimated_duration,
        sw.difficulty_level,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites
    FROM shared_workouts sw
    JOIN user_profiles up ON up.id = sw.sender_id
    WHERE sw.recipient_id = current_user_uuid
      AND sw.status != 'deleted'
    ORDER BY sw.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_received_workouts() IS 
  'Returns all workouts shared with the current user by friends. Called when loading received workouts.';

GRANT EXECUTE ON FUNCTION get_received_workouts() TO authenticated;

-- ============================================================================
-- FUNCTION: get_sent_workouts
-- Returns workouts the current user has shared with friends
-- ============================================================================
CREATE OR REPLACE FUNCTION get_sent_workouts()
RETURNS TABLE (
    workout_id UUID,
    to_user_id UUID,
    to_user_name TEXT,
    workout_name TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    -- Get the current authenticated user's ID
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Return workouts sent by current user
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.recipient_id as to_user_id,
        up.name as to_user_name,
        sw.workout_name,
        sw.status::TEXT,
        sw.created_at,
        sw.started_at,
        sw.completed_at
    FROM shared_workouts sw
    JOIN user_profiles up ON up.id = sw.recipient_id
    WHERE sw.sender_id = current_user_uuid
      AND sw.status != 'deleted'
    ORDER BY sw.created_at DESC;
END;
$$;

COMMENT ON FUNCTION get_sent_workouts() IS 
  'Returns all workouts sent by the current user to friends. Simplified structure matching SentWorkout DTO.';

GRANT EXECUTE ON FUNCTION get_sent_workouts() TO authenticated;

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Create indexes on shared_workouts table if they don't exist
CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient_id 
  ON shared_workouts(recipient_id) 
  WHERE status != 'deleted';

CREATE INDEX IF NOT EXISTS idx_shared_workouts_sender_id 
  ON shared_workouts(sender_id) 
  WHERE status != 'deleted';

CREATE INDEX IF NOT EXISTS idx_shared_workouts_created_at 
  ON shared_workouts(created_at DESC);

-- Create indexes on friendships table if they don't exist
CREATE INDEX IF NOT EXISTS idx_friendships_requester_accepted 
  ON friendships(requester_id) 
  WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_friendships_addressee_accepted 
  ON friendships(addressee_id) 
  WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_friendships_status 
  ON friendships(status);

-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ MISSING RPC FUNCTIONS CREATED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Created functions:';
  RAISE NOTICE '   - get_friends() - Returns accepted friendships';
  RAISE NOTICE '   - get_received_workouts() - Returns workouts from friends';
  RAISE NOTICE '   - get_sent_workouts() - Returns workouts sent to friends';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Performance indexes added:';
  RAISE NOTICE '   - shared_workouts: to_user_id, from_user_id, created_at';
  RAISE NOTICE '   - friendships: requester_id, addressee_id, status';
  RAISE NOTICE '';
  RAISE NOTICE '🐛 This fixes:';
  RAISE NOTICE '   - Profile screen hanging (119 second timeouts)';
  RAISE NOTICE '   - Strava sync errors (profile load blocking sync)';
  RAISE NOTICE '   - Friend/workout loading failures';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
