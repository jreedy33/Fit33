-- Migration: Friend activity feed + emoji reactions
-- Date: 2026-03-07
-- Reason: Social engagement — friends see each other's workouts, react with emojis

BEGIN;

-- ============================================================================
-- 1. FRIEND ACTIVITY FEED TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS friend_activity_feed (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL CHECK (activity_type IN (
        'workout_completed', 'streak_milestone', 'level_up',
        'achievement_unlocked', 'challenge_won'
    )),
    workout_id TEXT,
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE friend_activity_feed ENABLE ROW LEVEL SECURITY;

-- Users can see activities from accepted friends only
CREATE POLICY "users_see_friend_activities" ON friend_activity_feed
    FOR SELECT USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM friendships
            WHERE status = 'accepted'
              AND ((requester_id = auth.uid() AND addressee_id = friend_activity_feed.user_id)
                OR (requester_id = friend_activity_feed.user_id AND addressee_id = auth.uid()))
        )
    );

-- Users can insert their own activities
CREATE POLICY "users_insert_own_activities" ON friend_activity_feed
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- Users can delete their own activities
CREATE POLICY "users_delete_own_activities" ON friend_activity_feed
    FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_activity_feed_user ON friend_activity_feed(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_feed_created ON friend_activity_feed(created_at DESC);

-- ============================================================================
-- 2. ACTIVITY REACTIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS activity_reactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    activity_id UUID NOT NULL REFERENCES friend_activity_feed(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    emoji TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(activity_id, sender_id)
);

ALTER TABLE activity_reactions ENABLE ROW LEVEL SECURITY;

-- Activity owner and sender can see reactions
CREATE POLICY "users_see_reactions" ON activity_reactions
    FOR SELECT USING (
        sender_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM friend_activity_feed faf
            WHERE faf.id = activity_reactions.activity_id
              AND faf.user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM friend_activity_feed faf
            JOIN friendships f ON f.status = 'accepted'
              AND ((f.requester_id = auth.uid() AND f.addressee_id = faf.user_id)
                OR (f.requester_id = faf.user_id AND f.addressee_id = auth.uid()))
            WHERE faf.id = activity_reactions.activity_id
        )
    );

-- Users can insert reactions to friends' activities
CREATE POLICY "users_insert_reactions" ON activity_reactions
    FOR INSERT WITH CHECK (sender_id = auth.uid());

-- Users can delete their own reactions
CREATE POLICY "users_delete_own_reactions" ON activity_reactions
    FOR DELETE USING (sender_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_reactions_activity ON activity_reactions(activity_id);
CREATE INDEX IF NOT EXISTS idx_reactions_sender ON activity_reactions(sender_id);

-- ============================================================================
-- 3. GET FRIEND ACTIVITY FEED RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION get_friend_activity_feed(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    activity_id UUID,
    user_id UUID,
    user_name TEXT,
    user_username TEXT,
    user_profile_photo_url TEXT,
    user_level INT,
    activity_type TEXT,
    workout_id TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    reactions JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    RETURN QUERY
    SELECT
        faf.id AS activity_id,
        faf.user_id,
        up.name AS user_name,
        up.username AS user_username,
        up.profile_photo_url AS user_profile_photo_url,
        COALESCE((up.xp / 100) + 1, 1) AS user_level,
        faf.activity_type,
        faf.workout_id,
        faf.metadata,
        faf.created_at,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'sender_id', ar.sender_id,
                'sender_name', sp.name,
                'emoji', ar.emoji
            ))
            FROM activity_reactions ar
            JOIN user_profiles sp ON sp.id = ar.sender_id
            WHERE ar.activity_id = faf.id),
            '[]'::JSONB
        ) AS reactions
    FROM friend_activity_feed faf
    JOIN user_profiles up ON up.id = faf.user_id
    WHERE faf.user_id IN (
        SELECT CASE
            WHEN f.requester_id = current_user_uuid THEN f.addressee_id
            ELSE f.requester_id
        END
        FROM friendships f
        WHERE f.status = 'accepted'
          AND (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid)
    )
    ORDER BY faf.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_friend_activity_feed(INT, INT) TO authenticated;

-- ============================================================================
-- 4. POST ACTIVITY RPC (called after workout completion)
-- ============================================================================

CREATE OR REPLACE FUNCTION post_workout_activity(
    p_workout_id TEXT,
    p_workout_name TEXT,
    p_duration_seconds INT,
    p_exercise_count INT,
    p_total_sets INT,
    p_xp_earned INT,
    p_muscle_groups TEXT[] DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
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
        'workout_completed',
        p_workout_id,
        jsonb_build_object(
            'workout_name', p_workout_name,
            'duration_seconds', p_duration_seconds,
            'exercise_count', p_exercise_count,
            'total_sets', p_total_sets,
            'xp_earned', p_xp_earned,
            'muscle_groups', p_muscle_groups
        )
    )
    RETURNING id INTO new_activity_id;
    
    RETURN new_activity_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[]) TO authenticated;

-- ============================================================================
-- 5. SEND REACTION RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION send_activity_reaction(p_activity_id UUID, p_emoji TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_activity RECORD;
    sender_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Verify the activity exists and belongs to a friend
    SELECT * INTO v_activity FROM friend_activity_feed WHERE id = p_activity_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activity not found';
    END IF;
    
    -- Upsert reaction (one per user per activity)
    INSERT INTO activity_reactions (activity_id, sender_id, emoji)
    VALUES (p_activity_id, current_user_uuid, p_emoji)
    ON CONFLICT (activity_id, sender_id)
    DO UPDATE SET emoji = p_emoji, created_at = NOW();
    
    -- Get sender name for notification
    SELECT COALESCE(name, username, 'Someone') INTO sender_name
    FROM user_profiles WHERE id = current_user_uuid;
    
    -- Queue push notification to the activity owner
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            v_activity.user_id,
            'activity_reaction',
            sender_name || ' reacted ' || p_emoji,
            sender_name || ' sent you ' || p_emoji || ' on your workout!',
            jsonb_build_object(
                'type', 'activity_reaction',
                'activity_id', p_activity_id::TEXT,
                'sender_id', current_user_uuid::TEXT,
                'emoji', p_emoji
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue reaction notification: %', SQLERRM;
    END;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION send_activity_reaction(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 6. GET REACTIONS FOR USER'S OWN ACTIVITIES (for home tab sticker display)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_my_activity_reactions(p_limit INT DEFAULT 10)
RETURNS TABLE (
    activity_id UUID,
    workout_id TEXT,
    sender_id UUID,
    sender_name TEXT,
    emoji TEXT,
    reacted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.activity_id,
        faf.workout_id,
        ar.sender_id,
        COALESCE(up.name, up.username, 'Friend') AS sender_name,
        ar.emoji,
        ar.created_at AS reacted_at
    FROM activity_reactions ar
    JOIN friend_activity_feed faf ON faf.id = ar.activity_id
    JOIN user_profiles up ON up.id = ar.sender_id
    WHERE faf.user_id = auth.uid()
    ORDER BY ar.created_at DESC
    LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_activity_reactions(INT) TO authenticated;

COMMIT;
