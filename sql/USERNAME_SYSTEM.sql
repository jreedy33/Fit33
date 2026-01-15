-- =====================================================
-- USERNAME SYSTEM - FIXED VERSION
-- Adds unique usernames to user profiles
-- Run this in your Supabase SQL Editor
-- =====================================================

-- 1. Add username column to user_profiles
-- =====================================================
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS username TEXT UNIQUE;

-- Create index for fast username lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(username);

-- Make username case-insensitive unique (lowercase)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_profiles_username_lower 
ON user_profiles(LOWER(username));

-- =====================================================
-- 2. USERNAME VALIDATION FUNCTIONS
-- =====================================================

-- Check if a username is available (case-insensitive)
-- Excludes the current user so they can keep their own username
DROP FUNCTION IF EXISTS is_username_available(text);
CREATE OR REPLACE FUNCTION is_username_available(check_username TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    -- Username must be at least 3 characters
    IF LENGTH(check_username) < 3 THEN
        RETURN FALSE;
    END IF;
    
    -- Username must be alphanumeric with underscores only
    IF check_username !~ '^[a-zA-Z0-9_]+$' THEN
        RETURN FALSE;
    END IF;
    
    -- Check if username exists (case-insensitive), excluding current user
    -- Handle both UUID and TEXT id columns
    RETURN NOT EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE LOWER(username) = LOWER(check_username)
        AND (current_user_id IS NULL OR id::text != current_user_id::text)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Set username for current user
DROP FUNCTION IF EXISTS set_username(text);
CREATE OR REPLACE FUNCTION set_username(new_username TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
    profile_exists BOOLEAN;
BEGIN
    -- Must be authenticated
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;

    -- Validate username format
    IF LENGTH(new_username) < 3 THEN
        RAISE EXCEPTION 'Username must be at least 3 characters';
    END IF;
    
    IF LENGTH(new_username) > 30 THEN
        RAISE EXCEPTION 'Username must be 30 characters or less';
    END IF;
    
    IF new_username !~ '^[a-zA-Z0-9_]+$' THEN
        RAISE EXCEPTION 'Username can only contain letters, numbers, and underscores';
    END IF;
    
    -- Check availability (case-insensitive, exclude current user)
    -- Cast both sides to text for safe comparison
    IF EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE LOWER(username) = LOWER(new_username)
        AND id::text != current_user_id::text
    ) THEN
        RAISE EXCEPTION 'Username is already taken';
    END IF;
    
    -- Check if profile exists (cast to text for comparison)
    SELECT EXISTS (
        SELECT 1 FROM user_profiles WHERE id::text = current_user_id::text
    ) INTO profile_exists;
    
    IF profile_exists THEN
        -- Update existing profile
        UPDATE user_profiles 
        SET username = new_username
        WHERE id::text = current_user_id::text;
        
        RAISE NOTICE 'Updated username to % for user %', new_username, current_user_id;
    ELSE
        -- Create profile with username (fallback)
        -- Note: id column might be TEXT or UUID, so we use text for insert
        INSERT INTO user_profiles (id, username)
        VALUES (current_user_id::text, new_username)
        ON CONFLICT (id) DO UPDATE SET username = new_username;
        
        RAISE NOTICE 'Created profile with username % for user %', new_username, current_user_id;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 3. UPDATED SEARCH FUNCTION - SEARCH BY USERNAME
-- =====================================================

-- Drop existing function first (signature changed to include username)
DROP FUNCTION IF EXISTS search_users(text, integer);

-- Search users by username (primary) or name (fallback)
CREATE OR REPLACE FUNCTION search_users(search_query TEXT, result_limit INT DEFAULT 20)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    is_friend BOOLEAN,
    has_pending_request BOOLEAN
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
    clean_query TEXT;
BEGIN
    -- Remove @ if user typed it
    clean_query := LTRIM(search_query, '@');
    
    RETURN QUERY
    SELECT 
        u.id as user_id,
        up.name,
        u.email::text,  -- Cast varchar to text
        up.username,
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
    LEFT JOIN user_profiles up ON up.id::text = u.id::text
    WHERE u.id != current_user_id
    AND (
        -- Primary: search by username (case-insensitive)
        LOWER(COALESCE(up.username, '')) LIKE LOWER('%' || clean_query || '%')
        -- Fallback: search by name
        OR LOWER(COALESCE(up.name, '')) LIKE LOWER('%' || clean_query || '%')
    )
    -- Only return users who have a username set
    AND up.username IS NOT NULL
    ORDER BY 
        -- Exact username match first
        CASE WHEN LOWER(up.username) = LOWER(clean_query) THEN 0 ELSE 1 END,
        -- Then username starts with query
        CASE WHEN LOWER(up.username) LIKE LOWER(clean_query || '%') THEN 0 ELSE 1 END,
        up.username
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 4. UPDATED GET_FRIENDS TO INCLUDE USERNAME
-- =====================================================

-- Drop existing function first (signature changed to include friend_username)
DROP FUNCTION IF EXISTS get_friends();

CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendship_id UUID,
    friend_id UUID,
    friend_name TEXT,
    friend_email TEXT,
    friend_username TEXT,
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
        u.email::text as friend_email,  -- Cast varchar to text
        up.username as friend_username,
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
    LEFT JOIN user_profiles up ON up.id::text = (
        CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END
    )::text
    LEFT JOIN auth.users u ON u.id = CASE WHEN f.requester_id = current_user_id THEN f.addressee_id ELSE f.requester_id END
    WHERE (f.requester_id = current_user_id OR f.addressee_id = current_user_id)
    AND f.status = 'accepted'
    ORDER BY f.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- USAGE NOTES:
-- 
-- To check if username is available:
-- SELECT is_username_available('desired_username');
--
-- To set username for current user:
-- SELECT set_username('myusername');
--
-- To search for users by username:
-- SELECT * FROM search_users('john');
-- SELECT * FROM search_users('@john'); -- @ is stripped automatically
-- =====================================================
