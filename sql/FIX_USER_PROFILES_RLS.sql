-- =====================================================
-- FIX USER_PROFILES RLS POLICIES
-- Run this in Supabase SQL Editor if users can't
-- update their username or profile photo
-- =====================================================

-- Step 1: Check if RLS is enabled (it should be)
-- This will show current RLS status
SELECT relname, relrowsecurity 
FROM pg_class 
WHERE relname = 'user_profiles';

-- Step 2: Enable RLS if not already enabled
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Step 3: Drop existing policies (if any) to recreate them correctly
DROP POLICY IF EXISTS "Users can view own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Enable read access for authenticated users" ON user_profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON user_profiles;
DROP POLICY IF EXISTS "Enable update for users based on id" ON user_profiles;

-- Step 4: Create correct policies

-- Policy: Users can read their own profile
CREATE POLICY "Users can view own profile" ON user_profiles
    FOR SELECT
    TO authenticated
    USING (id::text = auth.uid()::text);

-- Policy: Users can insert their own profile (during signup)
CREATE POLICY "Users can insert own profile" ON user_profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (id::text = auth.uid()::text);

-- Policy: Users can update their own profile (username, photo, etc.)
CREATE POLICY "Users can update own profile" ON user_profiles
    FOR UPDATE
    TO authenticated
    USING (id::text = auth.uid()::text)
    WITH CHECK (id::text = auth.uid()::text);

-- Policy: Allow users to view other profiles (for friend search, etc.)
-- This is needed so users can search for and see other users
CREATE POLICY "Users can view all profiles" ON user_profiles
    FOR SELECT
    TO authenticated
    USING (true);

-- Step 5: Grant permissions
GRANT SELECT, INSERT, UPDATE ON user_profiles TO authenticated;

-- Step 6: Verify the RPC function exists and has correct permissions
-- The set_username function should be SECURITY DEFINER to bypass RLS
-- Let's check if it exists:
SELECT proname, prosecdef 
FROM pg_proc 
WHERE proname = 'set_username';

-- Step 7: If the function doesn't exist or needs recreation, here it is:
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
    IF EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE LOWER(username) = LOWER(new_username)
        AND id::text != current_user_id::text
    ) THEN
        RAISE EXCEPTION 'Username is already taken';
    END IF;
    
    -- Check if profile exists
    SELECT EXISTS (
        SELECT 1 FROM user_profiles WHERE id::text = current_user_id::text
    ) INTO profile_exists;
    
    IF profile_exists THEN
        -- Update existing profile
        UPDATE user_profiles 
        SET username = new_username
        WHERE id::text = current_user_id::text;
    ELSE
        -- Create profile with username (fallback)
        INSERT INTO user_profiles (id, username)
        VALUES (current_user_id::text, new_username)
        ON CONFLICT (id) DO UPDATE SET username = new_username;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION set_username(text) TO authenticated;

-- Step 8: Verify everything is set up correctly
SELECT 'RLS Policies for user_profiles:' AS info;
SELECT policyname, cmd, roles, qual, with_check 
FROM pg_policies 
WHERE tablename = 'user_profiles';

-- Step 9: Test query - should work for authenticated user
-- SELECT * FROM user_profiles WHERE id = auth.uid()::text;

SELECT 'User profiles RLS fix complete!' AS status;
