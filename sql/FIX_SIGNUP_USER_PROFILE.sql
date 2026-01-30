-- =====================================================
-- FIX USER SIGNUP - Create Profile Function
-- =====================================================
-- This fixes the "database error saving new user" error
-- that occurs during signup when RLS blocks the insert.
--
-- The issue: During signup, the auth session may not be
-- fully established when trying to insert the profile,
-- causing RLS to block the insert.
--
-- The fix: Use a SECURITY DEFINER function that bypasses
-- RLS to create the initial profile.
-- =====================================================

-- Step 1: Create the secure profile creation function
DROP FUNCTION IF EXISTS create_user_profile(uuid, text, text);
DROP FUNCTION IF EXISTS create_user_profile(text, text, text);

CREATE OR REPLACE FUNCTION create_user_profile(
    user_id TEXT,
    user_name TEXT,
    user_email TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Insert or update the profile
    INSERT INTO user_profiles (id, name, email, has_completed_onboarding, created_at)
    VALUES (user_id, user_name, user_email, false, NOW())
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_user_profile(text, text, text) TO authenticated;
-- Also grant to anon for signup flow (before auth is fully established)
GRANT EXECUTE ON FUNCTION create_user_profile(text, text, text) TO anon;

-- Step 2: Also create a function for initial user progress
DROP FUNCTION IF EXISTS create_user_progress(text);

CREATE OR REPLACE FUNCTION create_user_progress(user_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO user_progress (user_id, total_workouts, current_streak, longest_streak, xp, created_at)
    VALUES (user_id, 0, 0, 0, 0, NOW())
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

-- Step 3: Verify the functions exist
SELECT 'Functions created:' AS status;
SELECT proname, prosecdef AS security_definer
FROM pg_proc 
WHERE proname IN ('create_user_profile', 'create_user_progress');

-- Step 4: Ensure user_profiles table has the right columns
-- (Run these only if columns are missing)
DO $$
BEGIN
    -- Add has_completed_onboarding if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'has_completed_onboarding'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN has_completed_onboarding BOOLEAN DEFAULT false;
    END IF;
    
    -- Add created_at if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'created_at'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
    END IF;
    
    -- Add updated_at if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
    END IF;
END $$;

SELECT 'Signup fix complete! Run this SQL in your Supabase SQL Editor.' AS status;
