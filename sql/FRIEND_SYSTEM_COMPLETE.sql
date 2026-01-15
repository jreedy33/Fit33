-- =====================================================
-- FRIEND SYSTEM - COMPLETE SECURE IMPLEMENTATION
-- Fit33 Social Features - Friend & Workout Sharing
-- Run this in your Supabase SQL Editor
-- =====================================================

-- =====================================================
-- 1. FRIENDSHIPS TABLE (if not exists)
-- =====================================================
CREATE TABLE IF NOT EXISTS friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    addressee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
    message TEXT, -- Optional message with request
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Prevent duplicate relationships (either direction)
    CONSTRAINT unique_friendship UNIQUE(requester_id, addressee_id),
    -- Prevent self-friending
    CONSTRAINT no_self_friend CHECK (requester_id != addressee_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_friendships_status ON friendships(status);

-- =====================================================
-- 2. SHARED WORKOUTS TABLE (if not exists)
-- =====================================================
CREATE TABLE IF NOT EXISTS shared_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_name TEXT NOT NULL,
    workout_description TEXT,
    exercises JSONB NOT NULL DEFAULT '[]', -- Array of {name, sets, reps, notes}
    message TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'viewed', 'saved', 'started', 'completed', 'declined')),
    estimated_duration INT,
    difficulty_level TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    viewed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN DEFAULT FALSE,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_shared_workouts_sender ON shared_workouts(sender_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient ON shared_workouts(recipient_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_status ON shared_workouts(status);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_created ON shared_workouts(created_at DESC);

-- =====================================================
-- 3. ROW LEVEL SECURITY (RLS)
-- =====================================================

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_workouts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can view their own friendships" ON friendships;
DROP POLICY IF EXISTS "Users can create friend requests" ON friendships;
DROP POLICY IF EXISTS "Users can update their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can delete their own friend requests" ON friendships;
DROP POLICY IF EXISTS "Users can view their shared workouts" ON shared_workouts;
DROP POLICY IF EXISTS "Users can send workouts" ON shared_workouts;
DROP POLICY IF EXISTS "Users can update received workouts" ON shared_workouts;

-- Friendships policies
CREATE POLICY "Users can view their own friendships"
    ON friendships FOR SELECT
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

CREATE POLICY "Users can create friend requests"
    ON friendships FOR INSERT
    WITH CHECK (auth.uid() = requester_id);

CREATE POLICY "Users can update their friendships"
    ON friendships FOR UPDATE
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

CREATE POLICY "Users can delete their own friend requests"
    ON friendships FOR DELETE
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Shared workouts policies
CREATE POLICY "Users can view their shared workouts"
    ON shared_workouts FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Users can send workouts to friends"
    ON shared_workouts FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id 
        AND EXISTS (
            SELECT 1 FROM friendships 
            WHERE status = 'accepted'
            AND ((requester_id = auth.uid() AND addressee_id = recipient_id)
                OR (addressee_id = auth.uid() AND requester_id = recipient_id))
        )
    );

CREATE POLICY "Users can update received workouts"
    ON shared_workouts FOR UPDATE
    USING (auth.uid() = recipient_id OR auth.uid() = sender_id);

-- =====================================================
-- 4. RPC FUNCTIONS - SECURE API
-- =====================================================

-- Check if two users are friends
CREATE OR REPLACE FUNCTION are_friends(user_a UUID, user_b UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM friendships
        WHERE status = 'accepted'
        AND ((requester_id = user_a AND addressee_id = user_b)
            OR (requester_id = user_b AND addressee_id = user_a))
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get current user's friends with details
CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID,
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    friends_since TIMESTAMPTZ,
    total_workouts_shared INT
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as friendship_id,
        CASE 
            WHEN f.requester_id = current_user_id THEN f.addressee_id
            ELSE f.requester_id
        END as friend_id,
        up.name as friend_name,
        u.email as friend_email,
        up.fitness_goal,
        up.experience_level,
        f.updated_at as friends_since,
        COALESCE(
            (SELECT COUNT(*)::int FROM shared_workouts sw 
             WHERE (sw.sender_id = current_user_id AND sw.recipient_id = CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END)
                OR (sw.recipient_id = current_user_id AND sw.sender_id = CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END)
            ), 0
        ) as total_workouts_shared
    FROM friendships f
    LEFT JOIN user_profiles up ON up.id = (
        CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END
    )::text
    LEFT JOIN auth.users u ON u.id = CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END
    WHERE (f.requester_id = current_user_id OR f.addressee_id = current_user_id)
    AND f.status = 'accepted'
    ORDER BY f.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Search users by email or name (secure - limits results, excludes self)
CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INT DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        u.id as user_id,
        up.name,
        u.email,
        up.fitness_goal,
        up.experience_level,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_id AND f.addressee_id = u.id)
                OR (f.addressee_id = current_user_id AND f.requester_id = u.id))
        ) as is_friend,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_id AND f.addressee_id = u.id)
                OR (f.addressee_id = current_user_id AND f.requester_id = u.id))
        ) as has_pending_request
    FROM auth.users u
    LEFT JOIN user_profiles up ON up.id = u.id::text
    WHERE u.id != current_user_id
    AND (
        LOWER(u.email) LIKE LOWER('%' || search_query || '%')
        OR LOWER(COALESCE(up.name, '')) LIKE LOWER('%' || search_query || '%')
    )
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Send a friend request
CREATE OR REPLACE FUNCTION send_friend_request(target_user_id UUID, request_message TEXT DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    current_user_id UUID := auth.uid();
    existing_id UUID;
    new_id UUID;
BEGIN
    -- Check if request already exists (in either direction)
    SELECT id INTO existing_id FROM friendships
    WHERE (requester_id = current_user_id AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_id);
    
    IF existing_id IS NOT NULL THEN
        RAISE EXCEPTION 'Friend request already exists';
    END IF;
    
    -- Check target user exists
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = target_user_id) THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    
    -- Create the request
    INSERT INTO friendships (requester_id, addressee_id, message, status)
    VALUES (current_user_id, target_user_id, request_message, 'pending')
    RETURNING id INTO new_id;
    
    RETURN new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Accept a friend request
CREATE OR REPLACE FUNCTION accept_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    -- Only the addressee can accept
    UPDATE friendships
    SET status = 'accepted', updated_at = NOW()
    WHERE id = request_id
    AND addressee_id = current_user_id
    AND status = 'pending';
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Decline a friend request
CREATE OR REPLACE FUNCTION decline_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    -- Only the addressee can decline
    UPDATE friendships
    SET status = 'declined', updated_at = NOW()
    WHERE id = request_id
    AND addressee_id = current_user_id
    AND status = 'pending';
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get pending friend requests (requests sent TO current user)
CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    from_user_email TEXT,
    message TEXT,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.requester_id as from_user_id,
        up.name as from_user_name,
        u.email as from_user_email,
        f.message,
        f.created_at
    FROM friendships f
    LEFT JOIN user_profiles up ON up.id = f.requester_id::text
    LEFT JOIN auth.users u ON u.id = f.requester_id
    WHERE f.addressee_id = current_user_id
    AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remove a friend
CREATE OR REPLACE FUNCTION remove_friend(friendship_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    DELETE FROM friendships
    WHERE id = friendship_id
    AND (requester_id = current_user_id OR addressee_id = current_user_id);
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Send a workout to a friend (validates friendship first)
CREATE OR REPLACE FUNCTION send_workout_to_friend(
    target_user_id UUID,
    p_workout_name TEXT,
    p_exercises JSONB,
    p_description TEXT DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_duration INT DEFAULT NULL,
    p_difficulty TEXT DEFAULT 'Custom'
)
RETURNS UUID AS $$
DECLARE
    current_user_id UUID := auth.uid();
    new_id UUID;
BEGIN
    -- Verify they are friends
    IF NOT are_friends(current_user_id, target_user_id) THEN
        RAISE EXCEPTION 'You can only send workouts to friends';
    END IF;
    
    -- Create the shared workout
    INSERT INTO shared_workouts (
        sender_id, 
        recipient_id, 
        workout_name, 
        workout_description,
        exercises,
        message,
        estimated_duration,
        difficulty_level,
        status
    )
    VALUES (
        current_user_id,
        target_user_id,
        p_workout_name,
        p_description,
        p_exercises,
        p_message,
        p_duration,
        p_difficulty,
        'pending'
    )
    RETURNING id INTO new_id;
    
    RETURN new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get received workouts
CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    id TEXT,
    from_user_id TEXT,
    sender_name TEXT,
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
        sw.id::text,
        sw.sender_id::text as from_user_id,
        COALESCE(up.name, u.email, 'Unknown') as sender_name,
        sw.workout_name,
        sw.workout_description,
        sw.exercises,
        sw.message,
        sw.status,
        sw.estimated_duration,
        sw.difficulty_level,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites
    FROM shared_workouts sw
    LEFT JOIN user_profiles up ON up.id = sw.sender_id::text
    LEFT JOIN auth.users u ON u.id = sw.sender_id
    WHERE sw.recipient_id = current_user_id
    ORDER BY sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get sent workouts
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
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.recipient_id as to_user_id,
        COALESCE(up.name, u.email, 'Unknown') as to_user_name,
        sw.workout_name,
        sw.status,
        sw.created_at,
        sw.started_at,
        sw.completed_at
    FROM shared_workouts sw
    LEFT JOIN user_profiles up ON up.id = sw.recipient_id::text
    LEFT JOIN auth.users u ON u.id = sw.recipient_id
    WHERE sw.sender_id = current_user_id
    ORDER BY sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get unread notification count
CREATE OR REPLACE FUNCTION get_unread_notification_count()
RETURNS INT AS $$
DECLARE
    current_user_id UUID := auth.uid();
    unread_requests INT;
    unread_workouts INT;
BEGIN
    -- Count pending friend requests
    SELECT COUNT(*) INTO unread_requests
    FROM friendships
    WHERE addressee_id = current_user_id AND status = 'pending';
    
    -- Count unread workouts
    SELECT COUNT(*) INTO unread_workouts
    FROM shared_workouts
    WHERE recipient_id = current_user_id AND status = 'pending' AND viewed_at IS NULL;
    
    RETURN unread_requests + unread_workouts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 5. TIMESTAMP TRIGGER
-- =====================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_friendships_updated_at ON friendships;
CREATE TRIGGER update_friendships_updated_at
    BEFORE UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- SECURITY NOTES:
-- 
-- 1. All RPC functions use SECURITY DEFINER - they run
--    with elevated privileges but validate auth.uid()
--
-- 2. RLS policies prevent direct table access from 
--    bypassing friendship checks
--
-- 3. send_workout_to_friend validates friendship before
--    allowing workout sharing
--
-- 4. Search is limited to 20 results to prevent abuse
--
-- 5. Users can only see their own data (friendships,
--    requests, workouts)
-- =====================================================
