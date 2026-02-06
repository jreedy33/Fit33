-- =====================================================
-- QR CODE FRIEND SYSTEM
-- Enables users to add friends by scanning QR codes
-- Run this in your Supabase SQL Editor
-- =====================================================

-- =====================================================
-- 1. ADD QR CODE COLUMN TO USER PROFILES
-- =====================================================

-- Add the qr_code_id column (unique identifier for QR codes)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' AND column_name = 'qr_code_id'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN qr_code_id TEXT UNIQUE;
    END IF;
END $$;

-- Create index for fast QR code lookups
CREATE INDEX IF NOT EXISTS idx_user_profiles_qr_code 
ON user_profiles(qr_code_id) WHERE qr_code_id IS NOT NULL;

-- =====================================================
-- 2. GENERATE UNIQUE QR CODE ID FUNCTION
-- =====================================================

-- Generate a unique, URL-safe QR code identifier
-- Format: fit33_XXXXXXXX (8 random alphanumeric characters)
-- This is short enough for QR codes but unique enough to prevent collisions
CREATE OR REPLACE FUNCTION generate_unique_qr_code()
RETURNS TEXT AS $$
DECLARE
    new_code TEXT;
    code_exists BOOLEAN;
    attempts INT := 0;
    max_attempts INT := 10;
    -- Characters for code generation (URL-safe, no confusing chars like 0/O, 1/l)
    chars TEXT := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
BEGIN
    LOOP
        -- Generate 8 random characters
        new_code := 'fit33_';
        FOR i IN 1..8 LOOP
            new_code := new_code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
        END LOOP;
        
        -- Check if code already exists
        SELECT EXISTS(
            SELECT 1 FROM user_profiles WHERE qr_code_id = new_code
        ) INTO code_exists;
        
        -- Exit if unique code found
        IF NOT code_exists THEN
            RETURN new_code;
        END IF;
        
        attempts := attempts + 1;
        IF attempts >= max_attempts THEN
            -- Fallback: add timestamp suffix for guaranteed uniqueness
            RETURN 'fit33_' || substr(md5(random()::text || now()::text), 1, 12);
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. ASSIGN QR CODE ON PROFILE CREATION
-- =====================================================

-- Function to ensure a user has a QR code (called during profile creation/update)
CREATE OR REPLACE FUNCTION ensure_user_has_qr_code(target_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    existing_code TEXT;
    new_code TEXT;
BEGIN
    -- Check if user already has a QR code
    SELECT qr_code_id INTO existing_code
    FROM user_profiles
    WHERE id = target_user_id;
    
    IF existing_code IS NOT NULL THEN
        RETURN existing_code;
    END IF;
    
    -- Generate new QR code
    new_code := generate_unique_qr_code();
    
    -- Assign to user
    UPDATE user_profiles
    SET qr_code_id = new_code,
        updated_at = NOW()
    WHERE id = target_user_id;
    
    RETURN new_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION ensure_user_has_qr_code(UUID) TO authenticated;

-- =====================================================
-- 4. BACKFILL EXISTING USERS WITH QR CODES
-- =====================================================

-- Generate QR codes for all existing users who don't have one
DO $$
DECLARE
    user_record RECORD;
    new_code TEXT;
BEGIN
    FOR user_record IN 
        SELECT id FROM user_profiles WHERE qr_code_id IS NULL
    LOOP
        new_code := generate_unique_qr_code();
        UPDATE user_profiles 
        SET qr_code_id = new_code, updated_at = NOW()
        WHERE id = user_record.id;
    END LOOP;
    
    RAISE NOTICE 'QR codes generated for existing users';
END $$;

-- =====================================================
-- 5. TRIGGER TO AUTO-GENERATE QR CODE ON NEW PROFILES
-- =====================================================

-- Create trigger function
CREATE OR REPLACE FUNCTION trigger_generate_qr_code()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.qr_code_id IS NULL THEN
        NEW.qr_code_id := generate_unique_qr_code();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS auto_generate_qr_code ON user_profiles;

-- Create trigger on insert
CREATE TRIGGER auto_generate_qr_code
    BEFORE INSERT ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_generate_qr_code();

-- =====================================================
-- 6. GET USER'S QR CODE
-- =====================================================

-- Get the current user's QR code ID (creates one if doesn't exist)
CREATE OR REPLACE FUNCTION get_my_qr_code()
RETURNS TABLE (
    qr_code_id TEXT,
    user_name TEXT,
    username TEXT,
    profile_photo_url TEXT
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
    user_qr_code TEXT;
BEGIN
    -- Ensure user has a QR code
    SELECT ensure_user_has_qr_code(current_user_id) INTO user_qr_code;
    
    RETURN QUERY
    SELECT 
        up.qr_code_id,
        up.name as user_name,
        up.username,
        up.profile_photo_url
    FROM user_profiles up
    WHERE up.id = current_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_my_qr_code() TO authenticated;

-- =====================================================
-- 7. LOOK UP USER BY QR CODE
-- =====================================================

-- Find a user by their QR code (for scanning)
CREATE OR REPLACE FUNCTION get_user_by_qr_code(scanned_code TEXT)
RETURNS TABLE (
    user_id UUID,
    user_name TEXT,
    username TEXT,
    profile_photo_url TEXT,
    fitness_goal TEXT,
    experience_level TEXT,
    is_already_friend BOOLEAN,
    has_pending_request BOOLEAN,
    request_direction TEXT  -- 'sent' or 'received' if pending
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        up.id::uuid as user_id,
        up.name as user_name,
        up.username,
        up.profile_photo_url,
        up.fitness_goal,
        up.experience_level,
        -- Check if already friends
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_id AND f.addressee_id = up.id::uuid)
                OR (f.addressee_id = current_user_id AND f.requester_id = up.id::uuid))
        ) as is_already_friend,
        -- Check if there's a pending request
        EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
            AND ((f.requester_id = current_user_id AND f.addressee_id = up.id::uuid)
                OR (f.addressee_id = current_user_id AND f.requester_id = up.id::uuid))
        ) as has_pending_request,
        -- Determine request direction
        CASE
            WHEN EXISTS (
                SELECT 1 FROM friendships f
                WHERE f.status = 'pending'
                AND f.requester_id = current_user_id 
                AND f.addressee_id = up.id::uuid
            ) THEN 'sent'
            WHEN EXISTS (
                SELECT 1 FROM friendships f
                WHERE f.status = 'pending'
                AND f.addressee_id = current_user_id 
                AND f.requester_id = up.id::uuid
            ) THEN 'received'
            ELSE NULL
        END as request_direction
    FROM user_profiles up
    WHERE up.qr_code_id = scanned_code
    AND up.id != current_user_id;  -- Can't add yourself
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_by_qr_code(TEXT) TO authenticated;

-- =====================================================
-- 8. ADD FRIEND VIA QR CODE
-- =====================================================

-- Send a friend request using a scanned QR code
CREATE OR REPLACE FUNCTION add_friend_by_qr_code(scanned_code TEXT, request_message TEXT DEFAULT NULL)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    request_id UUID,
    friend_user_id UUID,
    friend_name TEXT,
    status TEXT  -- 'request_sent', 'already_friends', 'already_pending', 'request_accepted', 'user_not_found', 'error'
) AS $$
DECLARE
    current_user_id UUID := auth.uid();
    target_user_id UUID;
    target_user_name TEXT;
    existing_friendship RECORD;
    new_request_id UUID;
BEGIN
    -- Find the user by QR code
    SELECT id::uuid, name INTO target_user_id, target_user_name
    FROM user_profiles
    WHERE qr_code_id = scanned_code;
    
    -- User not found
    IF target_user_id IS NULL THEN
        RETURN QUERY SELECT 
            false, 
            'User not found. The QR code may be invalid or expired.'::TEXT,
            NULL::UUID,
            NULL::UUID,
            NULL::TEXT,
            'user_not_found'::TEXT;
        RETURN;
    END IF;
    
    -- Can't add yourself
    IF target_user_id = current_user_id THEN
        RETURN QUERY SELECT 
            false, 
            'You cannot add yourself as a friend.'::TEXT,
            NULL::UUID,
            target_user_id,
            target_user_name,
            'error'::TEXT;
        RETURN;
    END IF;
    
    -- Check for existing friendship/request
    SELECT * INTO existing_friendship
    FROM friendships
    WHERE (requester_id = current_user_id AND addressee_id = target_user_id)
       OR (requester_id = target_user_id AND addressee_id = current_user_id);
    
    IF existing_friendship IS NOT NULL THEN
        -- Already friends
        IF existing_friendship.status = 'accepted' THEN
            RETURN QUERY SELECT 
                true, 
                ('You are already friends with ' || COALESCE(target_user_name, 'this user') || '!')::TEXT,
                existing_friendship.id,
                target_user_id,
                target_user_name,
                'already_friends'::TEXT;
            RETURN;
        
        -- Pending request from current user
        ELSIF existing_friendship.status = 'pending' AND existing_friendship.requester_id = current_user_id THEN
            RETURN QUERY SELECT 
                true, 
                ('Friend request already sent to ' || COALESCE(target_user_name, 'this user') || '.')::TEXT,
                existing_friendship.id,
                target_user_id,
                target_user_name,
                'already_pending'::TEXT;
            RETURN;
        
        -- Pending request FROM target user - auto-accept!
        ELSIF existing_friendship.status = 'pending' AND existing_friendship.addressee_id = current_user_id THEN
            -- Accept the existing request
            UPDATE friendships
            SET status = 'accepted', updated_at = NOW()
            WHERE id = existing_friendship.id;
            
            RETURN QUERY SELECT 
                true, 
                ('You and ' || COALESCE(target_user_name, 'this user') || ' are now friends!')::TEXT,
                existing_friendship.id,
                target_user_id,
                target_user_name,
                'request_accepted'::TEXT;
            RETURN;
        
        -- Declined or blocked - allow retry after removing old record
        ELSIF existing_friendship.status IN ('declined', 'blocked') THEN
            DELETE FROM friendships WHERE id = existing_friendship.id;
            -- Continue to create new request below
        END IF;
    END IF;
    
    -- Create new friend request
    INSERT INTO friendships (requester_id, addressee_id, status, message, created_at)
    VALUES (current_user_id, target_user_id, 'pending', request_message, NOW())
    RETURNING id INTO new_request_id;
    
    RETURN QUERY SELECT 
        true, 
        ('Friend request sent to ' || COALESCE(target_user_name, 'this user') || '!')::TEXT,
        new_request_id,
        target_user_id,
        target_user_name,
        'request_sent'::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION add_friend_by_qr_code(TEXT, TEXT) TO authenticated;

-- =====================================================
-- 9. VERIFY SETUP
-- =====================================================

-- Check the column was added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'user_profiles' 
AND column_name = 'qr_code_id';

-- Check functions exist
SELECT proname, prosecdef as security_definer
FROM pg_proc 
WHERE proname IN (
    'generate_unique_qr_code',
    'ensure_user_has_qr_code',
    'get_my_qr_code',
    'get_user_by_qr_code',
    'add_friend_by_qr_code'
);

-- Show sample of users with QR codes
SELECT id, name, username, qr_code_id, created_at
FROM user_profiles
WHERE qr_code_id IS NOT NULL
LIMIT 5;
