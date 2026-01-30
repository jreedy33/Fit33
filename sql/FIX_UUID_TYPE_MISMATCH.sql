-- =====================================================
-- FIX UUID TYPE MISMATCH IN USER PROFILES
-- =====================================================
-- This fixes the "column id is of type uuid but expression is of type text" error
-- that prevents username and profile_photo_url from being saved.
--
-- Root cause: The user_profiles.id column is UUID type, but functions 
-- were passing TEXT values without proper casting.
-- =====================================================

-- Step 1: Check the current column type (for debugging)
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'user_profiles' AND column_name = 'id';

-- Step 2: Drop and recreate create_user_profile with proper UUID handling
DROP FUNCTION IF EXISTS create_user_profile(uuid, text, text);
DROP FUNCTION IF EXISTS create_user_profile(text, text, text);

CREATE OR REPLACE FUNCTION create_user_profile(
    p_user_id TEXT,
    p_user_name TEXT,
    p_user_email TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_uuid UUID;
BEGIN
    -- Convert TEXT to UUID
    v_user_uuid := p_user_id::UUID;
    
    -- Insert or update the profile using proper UUID
    INSERT INTO user_profiles (id, name, email, has_completed_onboarding, created_at)
    VALUES (v_user_uuid, p_user_name, p_user_email, false, NOW())
    ON CONFLICT (id) DO UPDATE SET
        name = COALESCE(EXCLUDED.name, user_profiles.name),
        email = COALESCE(EXCLUDED.email, user_profiles.email),
        updated_at = NOW();
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating user profile: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_user_profile(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_user_profile(text, text, text) TO anon;

-- Step 3: Drop and recreate create_user_progress with proper UUID handling
DROP FUNCTION IF EXISTS create_user_progress(uuid);
DROP FUNCTION IF EXISTS create_user_progress(text);

CREATE OR REPLACE FUNCTION create_user_progress(p_user_id TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_uuid UUID;
BEGIN
    v_user_uuid := p_user_id::UUID;
    
    INSERT INTO user_progress (user_id, total_workouts, current_streak, longest_streak, xp, created_at)
    VALUES (v_user_uuid, 0, 0, 0, 0, NOW())
    ON CONFLICT (user_id) DO NOTHING;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating user progress: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_user_progress(text) TO authenticated;
GRANT EXECUTE ON FUNCTION create_user_progress(text) TO anon;

-- Step 4: Fix set_username function with proper UUID handling
DROP FUNCTION IF EXISTS set_username(text, text);
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
    -- Use proper UUID comparison
    IF EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE LOWER(username) = LOWER(new_username)
        AND id != current_user_id
    ) THEN
        RAISE EXCEPTION 'Username is already taken';
    END IF;
    
    -- Check if profile exists using proper UUID comparison
    SELECT EXISTS (
        SELECT 1 FROM user_profiles WHERE id = current_user_id
    ) INTO profile_exists;
    
    IF profile_exists THEN
        -- Update existing profile
        UPDATE user_profiles 
        SET username = new_username, updated_at = NOW()
        WHERE id = current_user_id;
    ELSE
        -- Create profile with username (fallback)
        INSERT INTO user_profiles (id, username, created_at)
        VALUES (current_user_id, new_username, NOW())
        ON CONFLICT (id) DO UPDATE SET username = new_username, updated_at = NOW();
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION set_username(text) TO authenticated;

-- Step 5: Create/fix function to update profile photo URL
DROP FUNCTION IF EXISTS set_profile_photo(text);

CREATE OR REPLACE FUNCTION set_profile_photo(photo_url TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    IF current_user_id IS NULL THEN
        RAISE EXCEPTION 'User must be authenticated';
    END IF;
    
    UPDATE user_profiles 
    SET profile_photo_url = photo_url, updated_at = NOW()
    WHERE id = current_user_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION set_profile_photo(text) TO authenticated;

-- Step 6: Also ensure there's a function to set username WITH user_id parameter
-- (for use during onboarding when we have the user_id available)
DROP FUNCTION IF EXISTS set_username_for_user(text, text);

CREATE OR REPLACE FUNCTION set_username_for_user(
    p_user_id TEXT,
    p_username TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_uuid UUID;
BEGIN
    v_user_uuid := p_user_id::UUID;
    
    -- Validate username format
    IF LENGTH(p_username) < 3 THEN
        RAISE EXCEPTION 'Username must be at least 3 characters';
    END IF;
    
    IF LENGTH(p_username) > 30 THEN
        RAISE EXCEPTION 'Username must be 30 characters or less';
    END IF;
    
    IF p_username !~ '^[a-zA-Z0-9_]+$' THEN
        RAISE EXCEPTION 'Username can only contain letters, numbers, and underscores';
    END IF;
    
    -- Check availability (case-insensitive, exclude current user)
    IF EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE LOWER(username) = LOWER(p_username)
        AND id != v_user_uuid
    ) THEN
        RAISE EXCEPTION 'Username is already taken';
    END IF;
    
    -- Update or insert
    INSERT INTO user_profiles (id, username, created_at)
    VALUES (v_user_uuid, p_username, NOW())
    ON CONFLICT (id) DO UPDATE SET username = p_username, updated_at = NOW();
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error setting username: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION set_username_for_user(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION set_username_for_user(text, text) TO anon;

-- Step 7: Create function to update profile photo with user_id parameter
DROP FUNCTION IF EXISTS set_profile_photo_for_user(text, text);

CREATE OR REPLACE FUNCTION set_profile_photo_for_user(
    p_user_id TEXT,
    p_photo_url TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_uuid UUID;
BEGIN
    v_user_uuid := p_user_id::UUID;
    
    UPDATE user_profiles 
    SET profile_photo_url = p_photo_url, updated_at = NOW()
    WHERE id = v_user_uuid;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error setting profile photo: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION set_profile_photo_for_user(text, text) TO authenticated;

-- Step 8: Verify all functions are created
SELECT 'Functions created successfully:' AS status;
SELECT proname, prosecdef AS is_security_definer
FROM pg_proc 
WHERE proname IN (
    'create_user_profile', 
    'create_user_progress',
    'set_username',
    'set_username_for_user',
    'set_profile_photo',
    'set_profile_photo_for_user'
);

SELECT '✅ UUID TYPE MISMATCH FIX COMPLETE!' AS status;
SELECT 'Now update the Swift code to use set_username_for_user and set_profile_photo_for_user' AS next_step;
