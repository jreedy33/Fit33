-- Migration: Friend system bug fixes — unfriend RPC, blocking system, search_users, indexes
-- Date: 2026-03-07
-- Reason: Fixes critical bugs from FRIEND_SYSTEM_AUDIT.md (Bugs #4, #5, #6)

BEGIN;

-- ============================================================================
-- 1. UNFRIEND RPC — proper server-side unfriend with validation
-- ============================================================================

CREATE OR REPLACE FUNCTION unfriend(p_friend_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    deleted_count INT;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    IF p_friend_user_id = current_user_uuid THEN
        RAISE EXCEPTION 'Cannot unfriend yourself';
    END IF;
    
    DELETE FROM friendships
    WHERE status = 'accepted'
      AND (
        (requester_id = current_user_uuid AND addressee_id = p_friend_user_id)
        OR (requester_id = p_friend_user_id AND addressee_id = current_user_uuid)
      );
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    IF deleted_count = 0 THEN
        RAISE EXCEPTION 'Friendship not found';
    END IF;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION unfriend(UUID) TO authenticated;

-- ============================================================================
-- 2. USER BLOCKING SYSTEM
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_blocks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;

-- Users can only see their own blocks
CREATE POLICY "users_select_own_blocks" ON user_blocks
    FOR SELECT USING (blocker_id = auth.uid());

CREATE POLICY "users_insert_own_blocks" ON user_blocks
    FOR INSERT WITH CHECK (blocker_id = auth.uid());

CREATE POLICY "users_delete_own_blocks" ON user_blocks
    FOR DELETE USING (blocker_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

-- Block a user: creates block record, removes any existing friendship
CREATE OR REPLACE FUNCTION block_user(p_target_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    IF p_target_user_id = current_user_uuid THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;
    
    -- Insert block (ignore if already blocked)
    INSERT INTO user_blocks (blocker_id, blocked_id)
    VALUES (current_user_uuid, p_target_user_id)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;
    
    -- Remove any existing friendship in either direction
    DELETE FROM friendships
    WHERE (requester_id = current_user_uuid AND addressee_id = p_target_user_id)
       OR (requester_id = p_target_user_id AND addressee_id = current_user_uuid);
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION block_user(UUID) TO authenticated;

-- Unblock a user
CREATE OR REPLACE FUNCTION unblock_user(p_target_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    DELETE FROM user_blocks
    WHERE blocker_id = current_user_uuid AND blocked_id = p_target_user_id;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION unblock_user(UUID) TO authenticated;

-- Check if a user is blocked (either direction)
CREATE OR REPLACE FUNCTION is_blocked(p_user_a UUID, p_user_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1 FROM user_blocks
        WHERE (blocker_id = p_user_a AND blocked_id = p_user_b)
           OR (blocker_id = p_user_b AND blocked_id = p_user_a)
    );
$$;

-- Update send_friend_request to check blocks
CREATE OR REPLACE FUNCTION send_friend_request(target_user_id UUID, request_message TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    new_request_id UUID;
    existing_friendship RECORD;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    IF target_user_id = current_user_uuid THEN
        RAISE EXCEPTION 'Cannot send friend request to yourself';
    END IF;
    
    -- Check if either user has blocked the other
    IF is_blocked(current_user_uuid, target_user_id) THEN
        RAISE EXCEPTION 'Unable to send friend request';
    END IF;
    
    -- Check for existing friendship/request
    SELECT * INTO existing_friendship
    FROM friendships
    WHERE (requester_id = current_user_uuid AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_uuid);
    
    IF FOUND THEN
        IF existing_friendship.status = 'accepted' THEN
            RAISE EXCEPTION 'Already friends';
        ELSE
            RETURN existing_friendship.id;
        END IF;
    END IF;
    
    INSERT INTO friendships (requester_id, addressee_id, status, message)
    VALUES (current_user_uuid, target_user_id, 'pending', request_message)
    RETURNING id INTO new_request_id;
    
    -- Queue push notification to target user
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            target_user_id,
            'friend_request',
            'New Friend Request 👋',
            (SELECT COALESCE(name, username, 'Someone') FROM user_profiles WHERE id = current_user_uuid)
                || ' wants to be your friend!',
            jsonb_build_object(
                'type', 'friend_request',
                'friendship_id', new_request_id::TEXT,
                'sender_id', current_user_uuid::TEXT
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue friend request notification: %', SQLERRM;
    END;
    
    RETURN new_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION send_friend_request(UUID, TEXT) TO authenticated;

-- ============================================================================
-- 3. SEARCH_USERS RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INT DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    profile_photo_url TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN,
    has_outgoing_request BOOLEAN,
    has_incoming_request BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    search_pattern TEXT;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    search_pattern := '%' || LOWER(TRIM(search_query)) || '%';
    
    RETURN QUERY
    SELECT
        up.id AS user_id,
        up.name,
        up.email,
        up.username,
        up.fitness_goal,
        up.experience_level,
        up.profile_photo_url,
        -- is_friend: accepted friendship exists
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
              AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))
        ) AS is_friend,
        -- has_pending_request: any pending in either direction
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))
        ) AS has_pending_request,
        -- has_outgoing_request: I sent them a request
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND f.requester_id = current_user_uuid
              AND f.addressee_id = up.id
        ) AS has_outgoing_request,
        -- has_incoming_request: they sent me a request
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
              AND f.requester_id = up.id
              AND f.addressee_id = current_user_uuid
        ) AS has_incoming_request
    FROM user_profiles up
    WHERE up.id != current_user_uuid
      -- Exclude blocked users (either direction)
      AND NOT EXISTS (
          SELECT 1 FROM user_blocks ub
          WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = up.id)
             OR (ub.blocker_id = up.id AND ub.blocked_id = current_user_uuid)
      )
      AND (
          LOWER(up.name) LIKE search_pattern
          OR LOWER(up.email) LIKE search_pattern
          OR LOWER(up.username) LIKE search_pattern
      )
    ORDER BY
        -- Friends first, then pending, then others
        CASE
            WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
                AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                  OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 0
            WHEN EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'pending'
                AND ((f.requester_id = current_user_uuid AND f.addressee_id = up.id)
                  OR (f.requester_id = up.id AND f.addressee_id = current_user_uuid))) THEN 1
            ELSE 2
        END,
        up.name ASC NULLS LAST
    LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- ============================================================================
-- 4. MISSING DATABASE INDEXES
-- ============================================================================

-- Leaderboard queries
CREATE INDEX IF NOT EXISTS idx_challenge_participants_leaderboard
    ON challenge_participants (challenge_id, status) WHERE status = 'accepted';

-- Daily progress lookups
CREATE INDEX IF NOT EXISTS idx_daily_progress_user_date
    ON challenge_daily_progress (user_id, progress_date DESC);

-- Pending friend requests
CREATE INDEX IF NOT EXISTS idx_friendships_pending
    ON friendships (addressee_id, status) WHERE status = 'pending';

-- Accepted friendships (used by activity feed, friend list)
CREATE INDEX IF NOT EXISTS idx_friendships_accepted_requester
    ON friendships (requester_id) WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_friendships_accepted_addressee
    ON friendships (addressee_id) WHERE status = 'accepted';

-- Unread shared workouts
CREATE INDEX IF NOT EXISTS idx_shared_workouts_unread
    ON shared_workouts (recipient_id, created_at DESC) WHERE viewed_at IS NULL;

-- ============================================================================
-- 5. RLS DELETE POLICIES for challenge tables (if missing)
-- ============================================================================

DO $$
BEGIN
    -- group_challenges: creator can delete
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'group_challenges' AND cmd = 'DELETE'
    ) THEN
        CREATE POLICY "creator_delete_challenge" ON group_challenges
            FOR DELETE USING (creator_id = auth.uid());
    END IF;

    -- challenge_participants: user can remove themselves
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'challenge_participants' AND cmd = 'DELETE'
    ) THEN
        CREATE POLICY "user_delete_own_participation" ON challenge_participants
            FOR DELETE USING (user_id = auth.uid());
    END IF;

    -- challenge_daily_progress: user can delete own progress
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'challenge_daily_progress' AND cmd = 'DELETE'
    ) THEN
        CREATE POLICY "user_delete_own_progress" ON challenge_daily_progress
            FOR DELETE USING (user_id = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- 6. REPLICA IDENTITY for realtime-subscribed tables
-- ============================================================================

ALTER TABLE challenge_daily_progress REPLICA IDENTITY FULL;
ALTER TABLE challenge_participants REPLICA IDENTITY FULL;
ALTER TABLE group_challenges REPLICA IDENTITY FULL;
ALTER TABLE friendships REPLICA IDENTITY FULL;
ALTER TABLE shared_workouts REPLICA IDENTITY FULL;

COMMIT;

-- ROLLBACK:
-- DROP FUNCTION IF EXISTS unfriend(UUID);
-- DROP FUNCTION IF EXISTS block_user(UUID);
-- DROP FUNCTION IF EXISTS unblock_user(UUID);
-- DROP FUNCTION IF EXISTS is_blocked(UUID, UUID);
-- DROP FUNCTION IF EXISTS search_users(TEXT, INT);
-- DROP TABLE IF EXISTS user_blocks;
-- DROP INDEX IF EXISTS idx_challenge_participants_leaderboard;
-- DROP INDEX IF EXISTS idx_daily_progress_user_date;
-- DROP INDEX IF EXISTS idx_friendships_pending;
-- DROP INDEX IF EXISTS idx_friendships_accepted_requester;
-- DROP INDEX IF EXISTS idx_friendships_accepted_addressee;
-- DROP INDEX IF EXISTS idx_shared_workouts_unread;
