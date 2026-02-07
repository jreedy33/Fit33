-- ============================================================================
-- FIX: Friend System Safety
-- ============================================================================
-- PROBLEM: Friends randomly disappearing. Multiple safety issues found:
--
-- 1. `decline_friend_request` and `cancel_friend_request` RPCs are called
--    by the iOS app but were NEVER DEFINED — they may have dangerous
--    implementations or not exist at all
--
-- 2. `reject_friend_request` deletes ANY friendship row by ID without
--    checking status — could delete accepted friendships if wrong ID passed
--
-- 3. No protection against accidental deletion of accepted friendships
--
-- This script fixes all of these issues.
-- ============================================================================

-- ============================================================================
-- STEP 0: DIAGNOSTIC — Check current state of friendships
-- Run this FIRST to see what's happening
-- ============================================================================

-- Show all friendships in the system
SELECT 
    f.id as friendship_id,
    f.status,
    f.created_at,
    f.updated_at,
    r.name as requester_name,
    r.username as requester_username,
    a.name as addressee_name,
    a.username as addressee_username
FROM friendships f
LEFT JOIN user_profiles r ON r.id = f.requester_id
LEFT JOIN user_profiles a ON a.id = f.addressee_id
ORDER BY f.created_at DESC;

-- Show recently deleted profiles (if any are in auth.users but not user_profiles)
SELECT 
    au.id,
    au.email,
    au.created_at,
    CASE WHEN up.id IS NULL THEN '❌ PROFILE MISSING' ELSE '✅ Has profile' END as profile_status
FROM auth.users au
LEFT JOIN user_profiles up ON up.id = au.id
ORDER BY au.created_at DESC;

-- ============================================================================
-- STEP 1: Create SAFE decline_friend_request function
-- Only declines PENDING requests where current user is the addressee
-- ============================================================================

DROP FUNCTION IF EXISTS decline_friend_request(UUID);

CREATE OR REPLACE FUNCTION decline_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Get the request — ONLY if it's PENDING
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id 
      AND status = 'pending';  -- ← SAFETY: only delete pending requests
    
    IF NOT FOUND THEN
        -- Could be already processed or an accepted friendship
        RAISE NOTICE 'Friend request % not found or not pending', request_id;
        RETURN FALSE;
    END IF;
    
    -- Verify current user is the addressee (only the recipient can decline)
    IF request_record.addressee_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only decline requests sent to you';
    END IF;
    
    -- Delete the pending request
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION decline_friend_request(UUID) IS 
  'Safely declines a PENDING friend request. Will NOT delete accepted friendships.';

GRANT EXECUTE ON FUNCTION decline_friend_request(UUID) TO authenticated;

-- ============================================================================
-- STEP 2: Create SAFE cancel_friend_request function
-- Only cancels PENDING requests where current user is the requester (sender)
-- ============================================================================

DROP FUNCTION IF EXISTS cancel_friend_request(UUID);

CREATE OR REPLACE FUNCTION cancel_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Get the request — ONLY if it's PENDING
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id 
      AND status = 'pending';  -- ← SAFETY: only cancel pending requests
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Friend request % not found or not pending', request_id;
        RETURN FALSE;
    END IF;
    
    -- Verify current user is the requester (only the sender can cancel)
    IF request_record.requester_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only cancel requests you sent';
    END IF;
    
    -- Delete the pending request
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    
    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION cancel_friend_request(UUID) IS 
  'Safely cancels a PENDING friend request that the current user sent. Will NOT delete accepted friendships.';

GRANT EXECUTE ON FUNCTION cancel_friend_request(UUID) TO authenticated;

-- ============================================================================
-- STEP 3: Fix reject_friend_request to be safe
-- The existing version deletes ANY friendship by ID (including accepted ones!)
-- ============================================================================

CREATE OR REPLACE FUNCTION reject_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    -- Get the request — ONLY if it's PENDING
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id
      AND status = 'pending';  -- ← SAFETY: only reject pending requests
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Friend request % not found or not pending (may be accepted friendship — protected)', request_id;
        RETURN FALSE;
    END IF;
    
    -- Can reject if you're the addressee OR cancel if you're the requester
    IF request_record.addressee_id != current_user_uuid 
       AND request_record.requester_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only reject/cancel your own requests';
    END IF;
    
    -- Delete the PENDING request only
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_friend_request(UUID) TO authenticated;

-- ============================================================================
-- STEP 4: Add RLS policy to protect friendships from accidental deletion
-- Only allow users to delete their own friendships (not others')
-- ============================================================================

-- Enable RLS on friendships if not already enabled
ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can view their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can insert friendships" ON friendships;
DROP POLICY IF EXISTS "Users can update their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can delete their friendships" ON friendships;

-- SELECT: Users can see friendships they're part of
CREATE POLICY "Users can view their friendships"
ON friendships FOR SELECT
TO authenticated
USING (
    auth.uid() = requester_id OR auth.uid() = addressee_id
);

-- INSERT: Users can create friend requests (as requester)
CREATE POLICY "Users can insert friendships"
ON friendships FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = requester_id
);

-- UPDATE: Users can update friendships they're part of (accept/decline)
CREATE POLICY "Users can update their friendships"
ON friendships FOR UPDATE
TO authenticated
USING (
    auth.uid() = requester_id OR auth.uid() = addressee_id
);

-- DELETE: Users can only delete friendships they're part of
CREATE POLICY "Users can delete their friendships"
ON friendships FOR DELETE
TO authenticated
USING (
    auth.uid() = requester_id OR auth.uid() = addressee_id
);

-- ============================================================================
-- STEP 5: Verify all friend functions exist and are safe
-- ============================================================================

DO $$
DECLARE
    func_list TEXT[] := ARRAY[
        'get_friends',
        'get_pending_friend_requests',
        'get_sent_friend_requests',
        'send_friend_request',
        'accept_friend_request',
        'decline_friend_request',
        'cancel_friend_request',
        'reject_friend_request',
        'are_friends',
        'search_users'
    ];
    func TEXT;
    func_exists BOOLEAN;
    missing_count INT := 0;
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '🔍 FRIEND SYSTEM SAFETY CHECK';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    
    FOREACH func IN ARRAY func_list
    LOOP
        SELECT EXISTS (
            SELECT 1 FROM information_schema.routines
            WHERE routine_schema = 'public'
              AND routine_name = func
              AND routine_type = 'FUNCTION'
        ) INTO func_exists;
        
        IF func_exists THEN
            RAISE NOTICE '✅ %', func;
        ELSE
            RAISE WARNING '❌ % is MISSING!', func;
            missing_count := missing_count + 1;
        END IF;
    END LOOP;
    
    RAISE NOTICE '';
    IF missing_count = 0 THEN
        RAISE NOTICE '✅ All friend functions exist!';
    ELSE
        RAISE NOTICE '❌ % functions are missing!', missing_count;
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '🛡️ SAFETY FIXES APPLIED:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '1. decline_friend_request — only deletes PENDING requests';
    RAISE NOTICE '2. cancel_friend_request — only cancels PENDING requests';
    RAISE NOTICE '3. reject_friend_request — FIXED: now only deletes PENDING';
    RAISE NOTICE '4. RLS policies — protect friendships from unauthorized access';
    RAISE NOTICE '';
    RAISE NOTICE '🔒 Accepted friendships can no longer be accidentally deleted';
    RAISE NOTICE '   by decline/cancel/reject operations.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
