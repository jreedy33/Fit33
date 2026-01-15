-- =====================================================
-- PROFILE PHOTO SETUP
-- Run this in Supabase SQL Editor
-- =====================================================

-- Step 1: Add profile_photo_url column to user_profiles if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'profile_photo_url'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN profile_photo_url TEXT;
    END IF;
END $$;

-- =====================================================
-- IMPORTANT: CREATE THE BUCKET MANUALLY FIRST!
-- =====================================================
-- Before running the rest of this script:
-- 1. Go to Storage in Supabase Dashboard
-- 2. Click "New bucket"
-- 3. Name: avatars
-- 4. Toggle "Public bucket" to ON
-- 5. Click "Create bucket"
-- Then come back and run the rest of this script.
-- =====================================================

-- Step 2: Storage policies for the avatars bucket (using RLS on storage.objects)
-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Avatar upload policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar view policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar update policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar delete policy" ON storage.objects;

-- Policy: Authenticated users can upload avatars
CREATE POLICY "Avatar upload policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

-- Policy: Anyone can view avatars (public bucket)
CREATE POLICY "Avatar view policy"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

-- Policy: Authenticated users can update their avatars
CREATE POLICY "Avatar update policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars');

-- Policy: Authenticated users can delete their avatars
CREATE POLICY "Avatar delete policy"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars');

-- Step 3: Update search_users function to include profile_photo_url
DROP FUNCTION IF EXISTS search_users(TEXT, INT);

CREATE OR REPLACE FUNCTION search_users(
    search_query TEXT,
    result_limit INT DEFAULT 20
)
RETURNS TABLE (
    userId UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    fitnessGoal TEXT,
    experienceLevel TEXT,
    profilePhotoUrl TEXT,
    isFriend BOOLEAN,
    hasPendingRequest BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        u.id::UUID as userId,
        up.name,
        u.email::TEXT,
        up.username,
        up.fitness_goal as fitnessGoal,
        up.experience_level as experienceLevel,
        up.profile_photo_url as profilePhotoUrl,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as isFriend,
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as hasPendingRequest
    FROM auth.users u
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    WHERE u.id != current_user_uuid
    AND (
        up.name ILIKE '%' || search_query || '%'
        OR u.email ILIKE '%' || search_query || '%'
        OR up.username ILIKE '%' || search_query || '%'
    )
    ORDER BY 
        CASE WHEN up.username ILIKE search_query THEN 0
             WHEN up.username ILIKE search_query || '%' THEN 1
             WHEN up.name ILIKE search_query || '%' THEN 2
             ELSE 3 END,
        up.name
    LIMIT result_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION search_users(TEXT, INT) TO authenticated;

-- Step 4: Update get_friends function to include profile_photo_url
DROP FUNCTION IF EXISTS get_friends();

CREATE OR REPLACE FUNCTION get_friends()
RETURNS TABLE (
    friendshipId UUID,
    friendId UUID,
    friendName TEXT,
    friendEmail TEXT,
    friendUsername TEXT,
    fitnessGoal TEXT,
    experienceLevel TEXT,
    profilePhotoUrl TEXT,
    friendsSince TIMESTAMPTZ,
    totalWorkoutsShared INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        f.id as friendshipId,
        CASE 
            WHEN f.requester_id = current_user_uuid THEN f.addressee_id
            ELSE f.requester_id 
        END as friendId,
        up.name as friendName,
        u.email::TEXT as friendEmail,
        up.username as friendUsername,
        up.fitness_goal as fitnessGoal,
        up.experience_level as experienceLevel,
        up.profile_photo_url as profilePhotoUrl,
        f.created_at as friendsSince,
        COALESCE((
            SELECT COUNT(*)::INT FROM shared_workouts sw
            WHERE (sw.sender_id = current_user_uuid AND sw.recipient_id = CASE 
                WHEN f.requester_id = current_user_uuid THEN f.addressee_id
                ELSE f.requester_id 
            END)
            OR (sw.recipient_id = current_user_uuid AND sw.sender_id = CASE 
                WHEN f.requester_id = current_user_uuid THEN f.addressee_id
                ELSE f.requester_id 
            END)
        ), 0) as totalWorkoutsShared
    FROM friendships f
    JOIN auth.users u ON u.id = CASE 
        WHEN f.requester_id = current_user_uuid THEN f.addressee_id
        ELSE f.requester_id 
    END
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    WHERE f.status = 'accepted'
    AND (f.requester_id = current_user_uuid OR f.addressee_id = current_user_uuid)
    ORDER BY f.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_friends() TO authenticated;

-- Done!
SELECT 'Profile photo setup complete!' AS status;
