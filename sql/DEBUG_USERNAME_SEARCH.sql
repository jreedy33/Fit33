-- =====================================================
-- DEBUG USERNAME SEARCH
-- Run this in Supabase SQL Editor to diagnose why jreedy36 isn't found
-- =====================================================

-- 1. Check if the user_profiles table has username column
SELECT 
    column_name, 
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'user_profiles'
ORDER BY ordinal_position;

-- 2. Find all users with username like 'jreedy'
SELECT 
    id,
    name,
    email,
    username,
    created_at
FROM user_profiles
WHERE LOWER(username) LIKE '%jreedy%';

-- 3. Check EXACT match for 'jreedy36' (this is what the search function does)
SELECT 
    id,
    name,
    email,
    username
FROM user_profiles
WHERE LOWER(username) = LOWER('jreedy36');

-- 4. Check if the auth.users id matches user_profiles id
-- This is critical - the JOIN might be failing
SELECT 
    up.id as profile_id,
    u.id as auth_id,
    up.username,
    up.email as profile_email,
    u.email as auth_email,
    up.id::TEXT = u.id::TEXT as ids_match
FROM user_profiles up
LEFT JOIN auth.users u ON up.id::TEXT = u.id::TEXT
WHERE up.username IS NOT NULL
ORDER BY up.created_at DESC
LIMIT 10;

-- 5. Check if the search_users function exists and its definition
SELECT 
    routine_name,
    routine_type,
    routine_definition
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'search_users';

-- 6. Test the search function directly (replace YOUR_USER_ID with your actual user UUID)
-- You can find your user ID in auth.users table
-- SELECT * FROM search_users('jreedy36', 20);

-- 7. List ALL usernames in the system
SELECT username, id, email, name FROM user_profiles WHERE username IS NOT NULL ORDER BY username;

-- 8. Check if there's a type mismatch issue
-- Show the exact type of user_profiles.id
SELECT 
    pg_typeof(id) as id_type,
    id,
    username
FROM user_profiles
WHERE username IS NOT NULL
LIMIT 5;
