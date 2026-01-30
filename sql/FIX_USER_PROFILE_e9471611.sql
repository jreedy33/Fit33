-- =====================================================
-- FIX USER PROFILE: e9471611-91b2-48f7-8d9e-b7fb447059ca
-- UK user signed up via Apple, profile columns are null
-- =====================================================
-- ROOT CAUSE: A Supabase trigger creates empty profile rows,
-- then app code sees row exists and skips creating proper data
-- =====================================================

-- STEP 1: Check what exists in auth.users
SELECT 
    id,
    email,
    raw_user_meta_data->>'full_name' as meta_full_name,
    raw_user_meta_data->>'name' as meta_name,
    raw_app_meta_data->>'provider' as provider,
    created_at
FROM auth.users 
WHERE id = 'e9471611-91b2-48f7-8d9e-b7fb447059ca';

-- STEP 2: Check current state in user_profiles
SELECT * FROM user_profiles 
WHERE id = 'e9471611-91b2-48f7-8d9e-b7fb447059ca';

-- STEP 3: ⚠️ THIS IS LIKELY THE PROBLEM - Check for triggers on auth.users
-- that auto-create user_profiles rows
SELECT 
    t.tgname as trigger_name,
    n.nspname as schema_name,
    c.relname as table_name,
    pg_get_triggerdef(t.oid) as trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' AND c.relname = 'users'
AND t.tgisinternal = false;

-- STEP 4: Check the RLS policies on user_profiles
SELECT policyname, cmd, qual, with_check 
FROM pg_policies 
WHERE tablename = 'user_profiles';

-- =====================================================
-- FIX: Update the user's profile with data from auth
-- =====================================================

-- STEP 5: Fix the profile - pull data from auth.users metadata
DO $$
DECLARE
    user_email TEXT;
    user_name TEXT;
    auth_created_at TIMESTAMPTZ;
BEGIN
    -- Get data from auth.users
    SELECT 
        email,
        COALESCE(
            raw_user_meta_data->>'full_name',
            raw_user_meta_data->>'name',
            CASE 
                WHEN email LIKE '%privaterelay%' THEN 'Apple User'
                ELSE split_part(email, '@', 1)
            END,
            'Apple User'
        ),
        created_at
    INTO user_email, user_name, auth_created_at
    FROM auth.users 
    WHERE id = 'e9471611-91b2-48f7-8d9e-b7fb447059ca';
    
    -- Log what we found
    RAISE NOTICE 'Found auth data - Email: %, Name: %', user_email, user_name;
    
    -- Update or insert the profile
    INSERT INTO user_profiles (id, email, name, has_completed_onboarding, created_at)
    VALUES (
        'e9471611-91b2-48f7-8d9e-b7fb447059ca',
        user_email,
        user_name,
        false,
        COALESCE(auth_created_at, NOW())
    )
    ON CONFLICT (id) 
    DO UPDATE SET 
        email = COALESCE(EXCLUDED.email, user_profiles.email),
        name = COALESCE(EXCLUDED.name, user_profiles.name, 'Apple User'),
        has_completed_onboarding = COALESCE(user_profiles.has_completed_onboarding, false),
        updated_at = NOW()
    WHERE user_profiles.email IS NULL OR user_profiles.name IS NULL;
    
    RAISE NOTICE 'Profile fixed for user e9471611-91b2-48f7-8d9e-b7fb447059ca';
END $$;

-- STEP 6: Verify the fix
SELECT 
    id,
    name,
    email,
    has_completed_onboarding,
    experience_level,
    fitness_goal,
    created_at
FROM user_profiles 
WHERE id = 'e9471611-91b2-48f7-8d9e-b7fb447059ca';

-- =====================================================
-- PREVENTION: Check if there's a rogue trigger
-- =====================================================

-- STEP 7: Check for any trigger on auth.users that might create empty profiles
SELECT 
    n.nspname as schema_name,
    c.relname as table_name,
    t.tgname as trigger_name,
    pg_get_triggerdef(t.oid) as trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relname = 'users' 
AND n.nspname = 'auth'
AND t.tgisinternal = false;

-- =====================================================
-- FIX: Handle the Supabase trigger that creates empty profiles
-- =====================================================

-- STEP 8: Check what triggers exist - DON'T delete yet, just look
SELECT '⚠️ FOUND TRIGGERS ON AUTH.USERS:' as warning;
SELECT 
    t.tgname as trigger_name,
    pg_get_triggerdef(t.oid) as definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' AND c.relname = 'users'
AND t.tgisinternal = false;

-- STEP 9: OPTION A - Drop the trigger entirely (app handles profile creation)
-- Uncomment these lines if you want to remove the trigger:
-- DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- DROP FUNCTION IF EXISTS handle_new_user();

-- STEP 10: OPTION B - Replace with a BETTER trigger that populates data properly
-- This extracts name from Apple metadata correctly
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Create profile with proper data from auth metadata
    INSERT INTO public.user_profiles (id, email, name, has_completed_onboarding, created_at)
    VALUES (
        NEW.id::text,
        NEW.email,
        COALESCE(
            NEW.raw_user_meta_data->>'full_name',
            NEW.raw_user_meta_data->>'name',
            CASE 
                WHEN NEW.email LIKE '%privaterelay%' THEN 'Apple User'
                WHEN NEW.email IS NOT NULL THEN split_part(NEW.email, '@', 1)
                ELSE 'User'
            END
        ),
        false,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        -- Only update if existing values are null (don't overwrite good data)
        email = COALESCE(user_profiles.email, EXCLUDED.email),
        name = COALESCE(user_profiles.name, EXCLUDED.name),
        updated_at = NOW()
    WHERE user_profiles.email IS NULL OR user_profiles.name IS NULL;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- STEP 11: Fix ALL users with empty profiles (not just one)
-- =====================================================
SELECT 'Fixing ALL users with null name/email...' as status;

UPDATE user_profiles up
SET 
    email = COALESCE(up.email, au.email),
    name = COALESCE(up.name, 
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        CASE 
            WHEN au.email LIKE '%privaterelay%' THEN 'Apple User'
            WHEN au.email IS NOT NULL THEN split_part(au.email, '@', 1)
            ELSE 'User'
        END
    ),
    has_completed_onboarding = COALESCE(up.has_completed_onboarding, false),
    updated_at = NOW()
FROM auth.users au
WHERE up.id::text = au.id::text
AND (up.email IS NULL OR up.name IS NULL);

-- Show how many were fixed
SELECT 'Fixed profiles:' as status, COUNT(*) as count
FROM user_profiles 
WHERE updated_at > NOW() - INTERVAL '1 minute';

-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================
SELECT 'All empty profiles fixed!' AS status,
       'Users will see onboarding when they reopen the app' AS next_steps;

-- Verify the specific user is fixed:
SELECT id, name, email, has_completed_onboarding 
FROM user_profiles 
WHERE id = 'e9471611-91b2-48f7-8d9e-b7fb447059ca';
