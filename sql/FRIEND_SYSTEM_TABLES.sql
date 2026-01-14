-- =====================================================
-- FRIEND SYSTEM TABLES
-- Fit33 Social Features - Friend & Workout Sharing
-- =====================================================

-- 1. FRIENDSHIPS TABLE
-- Stores friend relationships between users
-- =====================================================
CREATE TABLE IF NOT EXISTS friendships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- The user who initiated the friend request
    requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- The user who received the friend request
    addressee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Status: pending, accepted, declined, blocked
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure no duplicate relationships
    UNIQUE(requester_id, addressee_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_friendships_requester ON friendships(requester_id);
CREATE INDEX IF NOT EXISTS idx_friendships_addressee ON friendships(addressee_id);
CREATE INDEX IF NOT EXISTS idx_friendships_status ON friendships(status);

-- 2. SHARED WORKOUTS TABLE
-- Stores workouts shared between friends
-- =====================================================
CREATE TABLE IF NOT EXISTS shared_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Who sent the workout
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Who receives the workout
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Workout details
    workout_name TEXT NOT NULL,
    workout_description TEXT,
    exercise_names TEXT[] NOT NULL, -- Array of exercise names
    exercise_sets INT[] DEFAULT '{}', -- Recommended sets per exercise
    exercise_reps TEXT[] DEFAULT '{}', -- Recommended reps per exercise (text for "8-12" ranges)
    exercise_notes TEXT[] DEFAULT '{}', -- Per-exercise notes/instructions
    
    -- Status: pending, accepted, declined, completed
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'saved', 'completed')),
    
    -- Optional message from sender
    message TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    viewed_at TIMESTAMPTZ,
    accepted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_shared_workouts_sender ON shared_workouts(sender_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient ON shared_workouts(recipient_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_status ON shared_workouts(status);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_created ON shared_workouts(created_at DESC);

-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- =====================================================

-- Enable RLS
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_workouts ENABLE ROW LEVEL SECURITY;

-- Friendships: Users can see their own friendships
CREATE POLICY "Users can view their own friendships"
    ON friendships FOR SELECT
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Friendships: Users can create friend requests
CREATE POLICY "Users can create friend requests"
    ON friendships FOR INSERT
    WITH CHECK (auth.uid() = requester_id);

-- Friendships: Users can update friendships they're part of
CREATE POLICY "Users can update their friendships"
    ON friendships FOR UPDATE
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Friendships: Users can delete their own requests
CREATE POLICY "Users can delete their own friend requests"
    ON friendships FOR DELETE
    USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- Shared Workouts: Users can see workouts they sent or received
CREATE POLICY "Users can view their shared workouts"
    ON shared_workouts FOR SELECT
    USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

-- Shared Workouts: Users can send workouts
CREATE POLICY "Users can send workouts"
    ON shared_workouts FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

-- Shared Workouts: Recipients can update workout status
CREATE POLICY "Users can update received workouts"
    ON shared_workouts FOR UPDATE
    USING (auth.uid() = recipient_id);

-- 4. HELPER FUNCTIONS
-- =====================================================

-- Function to get friends list for a user
CREATE OR REPLACE FUNCTION get_friends(user_uuid UUID)
RETURNS TABLE (
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    friendship_since TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        CASE 
            WHEN f.requester_id = user_uuid THEN f.addressee_id
            ELSE f.requester_id
        END as friend_id,
        up.name as friend_name,
        up.email as friend_email,
        f.updated_at as friendship_since
    FROM friendships f
    JOIN user_profiles up ON up.id = CASE 
        WHEN f.requester_id = user_uuid THEN f.addressee_id::text
        ELSE f.requester_id::text
    END
    WHERE (f.requester_id = user_uuid OR f.addressee_id = user_uuid)
    AND f.status = 'accepted';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to search users by email (for adding friends)
CREATE OR REPLACE FUNCTION search_users_by_email(search_email TEXT, current_user_id UUID)
RETURNS TABLE (
    user_id TEXT,
    user_name TEXT,
    user_email TEXT,
    friendship_status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        up.id as user_id,
        up.name as user_name,
        up.email as user_email,
        COALESCE(
            (SELECT f.status FROM friendships f 
             WHERE (f.requester_id = current_user_id AND f.addressee_id::text = up.id)
                OR (f.addressee_id = current_user_id AND f.requester_id::text = up.id)
             LIMIT 1),
            'none'
        ) as friendship_status
    FROM user_profiles up
    WHERE LOWER(up.email) LIKE LOWER('%' || search_email || '%')
    AND up.id != current_user_id::text
    LIMIT 20;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get pending friend requests for a user
CREATE OR REPLACE FUNCTION get_pending_friend_requests(user_uuid UUID)
RETURNS TABLE (
    request_id UUID,
    requester_id UUID,
    requester_name TEXT,
    requester_email TEXT,
    requested_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id as request_id,
        f.requester_id,
        up.name as requester_name,
        up.email as requester_email,
        f.created_at as requested_at
    FROM friendships f
    JOIN user_profiles up ON up.id = f.requester_id::text
    WHERE f.addressee_id = user_uuid
    AND f.status = 'pending'
    ORDER BY f.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to count unread shared workouts
CREATE OR REPLACE FUNCTION count_unread_shared_workouts(user_uuid UUID)
RETURNS INT AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::int
        FROM shared_workouts
        WHERE recipient_id = user_uuid
        AND status = 'pending'
        AND viewed_at IS NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. TRIGGERS FOR AUTO-UPDATING TIMESTAMPS
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
-- USAGE NOTES:
-- 
-- To add a friend:
-- INSERT INTO friendships (requester_id, addressee_id) VALUES ('user1-uuid', 'user2-uuid');
--
-- To accept a friend request:
-- UPDATE friendships SET status = 'accepted' WHERE id = 'request-uuid';
--
-- To send a workout:
-- INSERT INTO shared_workouts (sender_id, recipient_id, workout_name, exercise_names, message)
-- VALUES ('sender-uuid', 'recipient-uuid', 'Chest Day', ARRAY['Bench Press', 'Incline Dumbbell Press'], 'Try this!');
--
-- To accept a workout:
-- UPDATE shared_workouts SET status = 'accepted', accepted_at = NOW() WHERE id = 'workout-uuid';
-- =====================================================
