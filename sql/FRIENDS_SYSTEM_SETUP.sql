-- ============================================================================
-- FRIENDS & WORKOUT SHARING SYSTEM - COMPLETE DATABASE SETUP
-- ============================================================================
-- Run this in your Supabase SQL Editor to set up the friend system.
-- This includes: friendships, friend requests, shared workouts, and notifications.
-- ============================================================================

-- ============================================================================
-- TABLE 1: FRIENDSHIPS
-- ============================================================================
-- Stores accepted friend connections between users
-- Each friendship is stored ONCE (user_id_1 < user_id_2 to avoid duplicates)

CREATE TABLE IF NOT EXISTS friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_1 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure user_id_1 < user_id_2 to prevent duplicate friendships
    CONSTRAINT friendship_order CHECK (user_id_1 < user_id_2),
    CONSTRAINT unique_friendship UNIQUE (user_id_1, user_id_2)
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_friendships_user1 ON friendships(user_id_1);
CREATE INDEX IF NOT EXISTS idx_friendships_user2 ON friendships(user_id_2);

-- Row Level Security
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- Users can view friendships they're part of
DROP POLICY IF EXISTS "Users can view own friendships" ON friendships;
CREATE POLICY "Users can view own friendships" ON friendships 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

-- Users can delete friendships they're part of (unfriend)
DROP POLICY IF EXISTS "Users can delete own friendships" ON friendships;
CREATE POLICY "Users can delete own friendships" ON friendships 
    FOR DELETE TO authenticated 
    USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

-- Only system/triggers can insert friendships (via accepting requests)
DROP POLICY IF EXISTS "System can insert friendships" ON friendships;
CREATE POLICY "System can insert friendships" ON friendships 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id_1 OR auth.uid() = user_id_2);


-- ============================================================================
-- TABLE 2: FRIEND REQUESTS
-- ============================================================================
-- Stores pending friend requests between users

CREATE TABLE IF NOT EXISTS friend_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    message TEXT, -- Optional message with request
    created_at TIMESTAMPTZ DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    
    -- Prevent duplicate pending requests
    CONSTRAINT unique_pending_request UNIQUE (from_user_id, to_user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_friend_requests_from ON friend_requests(from_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_to ON friend_requests(to_user_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_status ON friend_requests(status);

-- Row Level Security
ALTER TABLE friend_requests ENABLE ROW LEVEL SECURITY;

-- Users can view requests they sent or received
DROP POLICY IF EXISTS "Users can view own friend requests" ON friend_requests;
CREATE POLICY "Users can view own friend requests" ON friend_requests 
    FOR SELECT TO authenticated 
    USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

-- Users can send friend requests
DROP POLICY IF EXISTS "Users can send friend requests" ON friend_requests;
CREATE POLICY "Users can send friend requests" ON friend_requests 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = from_user_id);

-- Users can update requests they received (accept/decline) or sent (cancel)
DROP POLICY IF EXISTS "Users can update own friend requests" ON friend_requests;
CREATE POLICY "Users can update own friend requests" ON friend_requests 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

-- Users can delete their own requests
DROP POLICY IF EXISTS "Users can delete own friend requests" ON friend_requests;
CREATE POLICY "Users can delete own friend requests" ON friend_requests 
    FOR DELETE TO authenticated 
    USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);


-- ============================================================================
-- TABLE 3: SHARED WORKOUTS
-- ============================================================================
-- Stores workouts shared between friends (trainer -> client, friend -> friend)

CREATE TABLE IF NOT EXISTS shared_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Who sent and who receives
    from_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Workout details
    workout_name TEXT NOT NULL,
    workout_description TEXT,
    estimated_duration_minutes INTEGER,
    difficulty_level TEXT CHECK (difficulty_level IN ('Beginner', 'Intermediate', 'Advanced', 'Custom')),
    
    -- Exercises stored as JSONB for flexibility
    -- Format: [{"name": "Bench Press", "sets": 3, "reps": "8-12", "rest_seconds": 90, "notes": "Focus on form"}, ...]
    exercises JSONB NOT NULL DEFAULT '[]'::jsonb,
    
    -- Personal message from sender
    message TEXT,
    
    -- Status tracking
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'started', 'completed')),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    viewed_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    
    -- If recipient saved to favorites
    saved_to_favorites BOOLEAN DEFAULT FALSE,
    
    -- If recipient edited before starting
    was_edited BOOLEAN DEFAULT FALSE
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_shared_workouts_from ON shared_workouts(from_user_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_to ON shared_workouts(to_user_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_status ON shared_workouts(status);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_created ON shared_workouts(created_at DESC);

-- Row Level Security
ALTER TABLE shared_workouts ENABLE ROW LEVEL SECURITY;

-- Users can view workouts they sent or received
DROP POLICY IF EXISTS "Users can view own shared workouts" ON shared_workouts;
CREATE POLICY "Users can view own shared workouts" ON shared_workouts 
    FOR SELECT TO authenticated 
    USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

-- Users can create shared workouts (send to friends)
DROP POLICY IF EXISTS "Users can create shared workouts" ON shared_workouts;
CREATE POLICY "Users can create shared workouts" ON shared_workouts 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = from_user_id);

-- Users can update workouts they received (accept/decline/start/complete)
DROP POLICY IF EXISTS "Users can update received shared workouts" ON shared_workouts;
CREATE POLICY "Users can update received shared workouts" ON shared_workouts 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = to_user_id OR auth.uid() = from_user_id);

-- Users can delete workouts they sent or received
DROP POLICY IF EXISTS "Users can delete own shared workouts" ON shared_workouts;
CREATE POLICY "Users can delete own shared workouts" ON shared_workouts 
    FOR DELETE TO authenticated 
    USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);


-- ============================================================================
-- TABLE 4: IN-APP NOTIFICATIONS
-- ============================================================================
-- Stores notifications for friend requests, shared workouts, etc.

CREATE TABLE IF NOT EXISTS app_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Notification type
    notification_type TEXT NOT NULL CHECK (notification_type IN (
        'friend_request_received',
        'friend_request_accepted',
        'workout_received',
        'workout_started',
        'workout_completed'
    )),
    
    -- Reference to related entity
    reference_id UUID, -- Can be friend_request.id or shared_workout.id
    reference_type TEXT CHECK (reference_type IN ('friend_request', 'shared_workout')),
    
    -- Who triggered this notification
    from_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    from_user_name TEXT,
    
    -- Notification content
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    
    -- Status
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user ON app_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON app_notifications(user_id, is_read) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_created ON app_notifications(created_at DESC);

-- Row Level Security
ALTER TABLE app_notifications ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notifications
DROP POLICY IF EXISTS "Users can view own notifications" ON app_notifications;
CREATE POLICY "Users can view own notifications" ON app_notifications 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

-- System can create notifications (via triggers)
DROP POLICY IF EXISTS "System can create notifications" ON app_notifications;
CREATE POLICY "System can create notifications" ON app_notifications 
    FOR INSERT TO authenticated 
    WITH CHECK (true);

-- Users can update their own notifications (mark as read)
DROP POLICY IF EXISTS "Users can update own notifications" ON app_notifications;
CREATE POLICY "Users can update own notifications" ON app_notifications 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = user_id);

-- Users can delete their own notifications
DROP POLICY IF EXISTS "Users can delete own notifications" ON app_notifications;
CREATE POLICY "Users can delete own notifications" ON app_notifications 
    FOR DELETE TO authenticated 
    USING (auth.uid() = user_id);


-- ============================================================================
-- HELPER FUNCTION: Get user display name
-- ============================================================================
CREATE OR REPLACE FUNCTION get_user_display_name(target_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    display_name TEXT;
BEGIN
    SELECT COALESCE(name, email, 'Unknown User')
    INTO display_name
    FROM user_profiles
    WHERE id = target_user_id;
    
    RETURN COALESCE(display_name, 'Unknown User');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Accept friend request and create friendship
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_friend_request(request_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    req RECORD;
    user1 UUID;
    user2 UUID;
BEGIN
    -- Get the request
    SELECT * INTO req FROM friend_requests WHERE id = request_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    -- Verify the current user is the recipient
    IF auth.uid() != req.to_user_id THEN
        RETURN FALSE;
    END IF;
    
    -- Determine order for friendship (user_id_1 < user_id_2)
    IF req.from_user_id < req.to_user_id THEN
        user1 := req.from_user_id;
        user2 := req.to_user_id;
    ELSE
        user1 := req.to_user_id;
        user2 := req.from_user_id;
    END IF;
    
    -- Update request status
    UPDATE friend_requests 
    SET status = 'accepted', responded_at = NOW()
    WHERE id = request_id;
    
    -- Create friendship
    INSERT INTO friendships (user_id_1, user_id_2)
    VALUES (user1, user2)
    ON CONFLICT (user_id_1, user_id_2) DO NOTHING;
    
    -- Create notification for the sender
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        reference_type,
        from_user_id,
        from_user_name,
        title,
        body
    ) VALUES (
        req.from_user_id,
        'friend_request_accepted',
        request_id,
        'friend_request',
        req.to_user_id,
        get_user_display_name(req.to_user_id),
        'Friend Request Accepted! 🎉',
        get_user_display_name(req.to_user_id) || ' accepted your friend request'
    );
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Send friend request with notification
-- ============================================================================
CREATE OR REPLACE FUNCTION send_friend_request(target_user_id UUID, request_message TEXT DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    new_request_id UUID;
    sender_name TEXT;
BEGIN
    -- Prevent self-requests
    IF auth.uid() = target_user_id THEN
        RAISE EXCEPTION 'Cannot send friend request to yourself';
    END IF;
    
    -- Check if already friends
    IF EXISTS (
        SELECT 1 FROM friendships 
        WHERE (user_id_1 = LEAST(auth.uid(), target_user_id) AND user_id_2 = GREATEST(auth.uid(), target_user_id))
    ) THEN
        RAISE EXCEPTION 'Already friends with this user';
    END IF;
    
    -- Check for existing pending request
    IF EXISTS (
        SELECT 1 FROM friend_requests 
        WHERE from_user_id = auth.uid() AND to_user_id = target_user_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'Friend request already pending';
    END IF;
    
    -- Get sender name
    sender_name := get_user_display_name(auth.uid());
    
    -- Create the request
    INSERT INTO friend_requests (from_user_id, to_user_id, message)
    VALUES (auth.uid(), target_user_id, request_message)
    RETURNING id INTO new_request_id;
    
    -- Create notification for recipient
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        reference_type,
        from_user_id,
        from_user_name,
        title,
        body
    ) VALUES (
        target_user_id,
        'friend_request_received',
        new_request_id,
        'friend_request',
        auth.uid(),
        sender_name,
        'New Friend Request! 👋',
        sender_name || ' wants to be your friend'
    );
    
    RETURN new_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Send workout to friend with notification
-- ============================================================================
CREATE OR REPLACE FUNCTION send_workout_to_friend(
    target_user_id UUID,
    p_workout_name TEXT,
    p_exercises JSONB,
    p_description TEXT DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_duration INTEGER DEFAULT NULL,
    p_difficulty TEXT DEFAULT 'Custom'
)
RETURNS UUID AS $$
DECLARE
    new_workout_id UUID;
    sender_name TEXT;
BEGIN
    -- Get sender name
    sender_name := get_user_display_name(auth.uid());
    
    -- Create the shared workout
    INSERT INTO shared_workouts (
        from_user_id,
        to_user_id,
        workout_name,
        workout_description,
        exercises,
        message,
        estimated_duration_minutes,
        difficulty_level
    ) VALUES (
        auth.uid(),
        target_user_id,
        p_workout_name,
        p_description,
        p_exercises,
        p_message,
        p_duration,
        p_difficulty
    )
    RETURNING id INTO new_workout_id;
    
    -- Create notification for recipient
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        reference_type,
        from_user_id,
        from_user_name,
        title,
        body
    ) VALUES (
        target_user_id,
        'workout_received',
        new_workout_id,
        'shared_workout',
        auth.uid(),
        sender_name,
        'New Workout! 💪',
        sender_name || ' sent you a workout: "' || p_workout_name || '"'
    );
    
    RETURN new_workout_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Search users by name or email (for adding friends)
-- ============================================================================
CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INTEGER DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        up.id as user_id,
        up.name,
        up.email,
        up.fitness_goal,
        up.experience_level,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE (f.user_id_1 = auth.uid() AND f.user_id_2 = up.id)
               OR (f.user_id_1 = up.id AND f.user_id_2 = auth.uid())
        ) as is_friend,
        EXISTS (
            SELECT 1 FROM friend_requests fr 
            WHERE ((fr.from_user_id = auth.uid() AND fr.to_user_id = up.id)
               OR (fr.from_user_id = up.id AND fr.to_user_id = auth.uid()))
               AND fr.status = 'pending'
        ) as has_pending_request
    FROM user_profiles up
    WHERE up.id != auth.uid()
      AND (
          up.name ILIKE '%' || search_query || '%'
          OR up.email ILIKE '%' || search_query || '%'
      )
    ORDER BY 
        -- Prioritize exact name matches, then partial matches
        CASE WHEN up.name ILIKE search_query THEN 0
             WHEN up.name ILIKE search_query || '%' THEN 1
             ELSE 2
        END,
        up.name
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Get user's friends with details
-- ============================================================================
CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID,
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    friends_since TIMESTAMPTZ,
    total_workouts_shared INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id as friendship_id,
        CASE 
            WHEN f.user_id_1 = auth.uid() THEN f.user_id_2 
            ELSE f.user_id_1 
        END as friend_id,
        up.name as friend_name,
        up.email as friend_email,
        up.fitness_goal,
        up.experience_level,
        f.created_at as friends_since,
        (
            SELECT COUNT(*)::INTEGER 
            FROM shared_workouts sw 
            WHERE (sw.from_user_id = auth.uid() AND sw.to_user_id = 
                CASE WHEN f.user_id_1 = auth.uid() THEN f.user_id_2 ELSE f.user_id_1 END)
               OR (sw.to_user_id = auth.uid() AND sw.from_user_id = 
                CASE WHEN f.user_id_1 = auth.uid() THEN f.user_id_2 ELSE f.user_id_1 END)
        ) as total_workouts_shared
    FROM friendships f
    JOIN user_profiles up ON up.id = CASE 
        WHEN f.user_id_1 = auth.uid() THEN f.user_id_2 
        ELSE f.user_id_1 
    END
    WHERE f.user_id_1 = auth.uid() OR f.user_id_2 = auth.uid()
    ORDER BY up.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Get pending friend requests (received)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_pending_friend_requests()
RETURNS TABLE (
    request_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    from_user_email TEXT,
    message TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fr.id as request_id,
        fr.from_user_id,
        up.name as from_user_name,
        up.email as from_user_email,
        fr.message,
        fr.created_at
    FROM friend_requests fr
    JOIN user_profiles up ON up.id = fr.from_user_id
    WHERE fr.to_user_id = auth.uid() AND fr.status = 'pending'
    ORDER BY fr.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Get received workouts (inbox)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    workout_id UUID,
    from_user_id UUID,
    from_user_name TEXT,
    workout_name TEXT,
    workout_description TEXT,
    exercises JSONB,
    message TEXT,
    status TEXT,
    estimated_duration INTEGER,
    difficulty_level TEXT,
    created_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.from_user_id,
        up.name as from_user_name,
        sw.workout_name,
        sw.workout_description,
        sw.exercises,
        sw.message,
        sw.status,
        sw.estimated_duration_minutes as estimated_duration,
        sw.difficulty_level,
        sw.created_at,
        sw.saved_to_favorites
    FROM shared_workouts sw
    JOIN user_profiles up ON up.id = sw.from_user_id
    WHERE sw.to_user_id = auth.uid()
    ORDER BY 
        CASE WHEN sw.status = 'pending' THEN 0 ELSE 1 END,
        sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Get sent workouts (outbox)
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
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sw.id as workout_id,
        sw.to_user_id,
        up.name as to_user_name,
        sw.workout_name,
        sw.status,
        sw.created_at,
        sw.started_at,
        sw.completed_at
    FROM shared_workouts sw
    JOIN user_profiles up ON up.id = sw.to_user_id
    WHERE sw.from_user_id = auth.uid()
    ORDER BY sw.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Get unread notification count
-- ============================================================================
CREATE OR REPLACE FUNCTION get_unread_notification_count()
RETURNS INTEGER AS $$
DECLARE
    count_result INTEGER;
BEGIN
    SELECT COUNT(*)::INTEGER INTO count_result
    FROM app_notifications
    WHERE user_id = auth.uid() AND is_read = FALSE;
    
    RETURN count_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Mark notification as read
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_notification_read(notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE app_notifications 
    SET is_read = TRUE, read_at = NOW()
    WHERE id = notification_id AND user_id = auth.uid();
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- FUNCTION: Mark all notifications as read
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE app_notifications 
    SET is_read = TRUE, read_at = NOW()
    WHERE user_id = auth.uid() AND is_read = FALSE;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================================
-- ✅ SETUP COMPLETE!
-- ============================================================================
-- Tables created:
--   1. friendships - Stores friend connections
--   2. friend_requests - Stores pending requests
--   3. shared_workouts - Stores workouts sent between friends
--   4. app_notifications - In-app notification system
--
-- Functions created:
--   - accept_friend_request(request_id)
--   - send_friend_request(target_user_id, message)
--   - send_workout_to_friend(...)
--   - search_users(query)
--   - get_friends()
--   - get_pending_friend_requests()
--   - get_received_workouts()
--   - get_sent_workouts()
--   - get_unread_notification_count()
--   - mark_notification_read(notification_id)
--   - mark_all_notifications_read()
-- ============================================================================
