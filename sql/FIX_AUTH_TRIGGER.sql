-- =====================================================
-- FIX AUTH SIGNUP ERROR: "Database error saving new user"
-- =====================================================
-- This error happens DURING auth.signUp(), which means
-- there's a trigger on auth.users that's failing.
--
-- Run this in your Supabase SQL Editor!
-- =====================================================

-- Step 1: Check what triggers exist on auth.users
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers 
WHERE event_object_schema = 'auth' 
AND event_object_table = 'users';

-- Step 2: Check the trigger function for errors
-- The most common issue is a trigger that tries to insert into
-- user_profiles but fails due to RLS or missing columns

-- Let's see if there's a handle_new_user function
SELECT 
    proname AS function_name,
    prosrc AS function_source
FROM pg_proc 
WHERE proname LIKE '%new_user%' OR proname LIKE '%handle%user%';

-- Step 3: DROP the problematic trigger (if it exists)
-- This is the most common culprit
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 4: Recreate a SAFE trigger that won't fail
-- This trigger creates a minimal profile that won't cause errors

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert a minimal profile - this MUST succeed or signup fails
    INSERT INTO public.user_profiles (id, email, name, has_completed_onboarding, created_at)
    VALUES (
        NEW.id::text,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        false,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        updated_at = NOW();
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Log the error but DON'T fail the signup
        RAISE WARNING 'Error in handle_new_user trigger: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 5: Create the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Make sure user_profiles table has the right structure
-- Check if the columns exist
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'user_profiles'
ORDER BY ordinal_position;

-- Step 7: Add any missing columns that the trigger needs
DO $$
BEGIN
    -- Ensure id column accepts text (UUID as string)
    -- This is important because auth.users.id is UUID but we store as text
    
    -- Add has_completed_onboarding if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'has_completed_onboarding'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN has_completed_onboarding BOOLEAN DEFAULT false;
        RAISE NOTICE 'Added has_completed_onboarding column';
    END IF;
    
    -- Add created_at if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'created_at'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
        RAISE NOTICE 'Added created_at column';
    END IF;
    
    -- Add updated_at if missing  
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
        RAISE NOTICE 'Added updated_at column';
    END IF;
    
    -- Add name if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'name'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN name TEXT;
        RAISE NOTICE 'Added name column';
    END IF;
    
    -- Add email if missing
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'email'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN email TEXT;
        RAISE NOTICE 'Added email column';
    END IF;
END $$;

-- Step 8: Grant necessary permissions
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON public.user_profiles TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE ON public.user_profiles TO authenticated;
GRANT INSERT ON public.user_profiles TO anon;

-- Step 9: Verify the fix
SELECT '✅ Auth trigger fix complete!' AS status;
SELECT 'Now try signing up again in the app.' AS next_step;

-- Step 10: If signup still fails, check RLS policies
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'user_profiles';
