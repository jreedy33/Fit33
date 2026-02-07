-- Fix RLS policies to enable contact matching during onboarding
-- This allows authenticated users to read other users' profiles for friend discovery

-- Drop existing restrictive policy if it exists
DROP POLICY IF EXISTS "Users can only view their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can view completed profiles" ON user_profiles;

-- Create new policy that allows authenticated users to read public profile fields
-- This is necessary for contact matching to work during onboarding
CREATE POLICY "Users can view other profiles for contact matching"
ON user_profiles FOR SELECT
TO authenticated
USING (true);

-- Ensure users can still update their own profile
DROP POLICY IF EXISTS "Users can update own profile" ON user_profiles;
CREATE POLICY "Users can update own profile"
ON user_profiles FOR UPDATE
TO authenticated
USING (auth.uid() = id);

-- Ensure users can insert their own profile
DROP POLICY IF EXISTS "Users can insert own profile" ON user_profiles;
CREATE POLICY "Users can insert own profile"
ON user_profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Verify the policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'user_profiles'
ORDER BY policyname;

-- Expected result: You should see policies allowing:
-- 1. SELECT for all authenticated users (for contact matching)
-- 2. UPDATE for own profile only
-- 3. INSERT for own profile only
