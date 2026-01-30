-- =====================================================
-- FIX AVATAR STORAGE BUCKET AND POLICIES
-- Run this in Supabase SQL Editor if photo uploads fail
-- =====================================================

-- IMPORTANT: First, manually create the bucket if it doesn't exist:
-- 1. Go to Storage in Supabase Dashboard
-- 2. Click "New bucket"
-- 3. Name: avatars
-- 4. Toggle "Public bucket" to ON
-- 5. Click "Create bucket"

-- Step 1: Check if bucket exists
SELECT id, name, public FROM storage.buckets WHERE name = 'avatars';

-- Step 2: If bucket doesn't exist, create it via Dashboard or uncomment:
-- INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
-- VALUES ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp']);

-- Step 3: Drop existing storage policies
DROP POLICY IF EXISTS "Avatar upload policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar view policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar update policy" ON storage.objects;
DROP POLICY IF EXISTS "Avatar delete policy" ON storage.objects;
DROP POLICY IF EXISTS "Give users access to own folder" ON storage.objects;

-- Step 4: Create new policies that allow authenticated users to manage their photos

-- Policy: Authenticated users can upload to avatars bucket
CREATE POLICY "Avatar upload policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'avatars');

-- Policy: Anyone can view avatars (public bucket)
CREATE POLICY "Avatar view policy"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');

-- Policy: Authenticated users can update avatars
CREATE POLICY "Avatar update policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'avatars')
WITH CHECK (bucket_id = 'avatars');

-- Policy: Authenticated users can delete avatars
CREATE POLICY "Avatar delete policy"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'avatars');

-- Step 5: Verify policies
SELECT policyname, cmd, roles 
FROM pg_policies 
WHERE tablename = 'objects' AND schemaname = 'storage';

SELECT 'Avatar storage fix complete!' AS status;
