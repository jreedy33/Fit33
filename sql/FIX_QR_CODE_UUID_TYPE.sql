-- =====================================================
-- FIX QR CODE UUID TYPE MISMATCH
-- Fixes the "operator does not exist: uuid = text" error
-- =====================================================

-- =====================================================
-- 1. FIX: ensure_user_has_qr_code function
-- =====================================================
CREATE OR REPLACE FUNCTION ensure_user_has_qr_code(target_user_id UUID)
RETURNS TEXT AS $$
DECLARE
    existing_code TEXT;
    new_code TEXT;
BEGIN
    -- Check if user already has a QR code
    SELECT qr_code_id INTO existing_code
    FROM user_profiles
    WHERE id = target_user_id;  -- FIXED: Removed ::text cast
    
    IF existing_code IS NOT NULL THEN
        RETURN existing_code;
    END IF;
    
    -- Generate new QR code
    new_code := generate_unique_qr_code();
    
    -- Assign to user
    UPDATE user_profiles
    SET qr_code_id = new_code,
        updated_at = NOW()
    WHERE id = target_user_id;  -- FIXED: Removed ::text cast
    
    RETURN new_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION ensure_user_has_qr_code(UUID) TO authenticated;

-- =====================================================
-- 2. FIX: get_my_qr_code function
-- =====================================================
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
    WHERE up.id = current_user_id;  -- FIXED: Removed ::text cast
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_my_qr_code() TO authenticated;

-- =====================================================
-- 3. FIX: get_user_by_qr_code function
-- =====================================================
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
    AND up.id != current_user_id;  -- FIXED: Removed ::text cast
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_by_qr_code(TEXT) TO authenticated;

-- =====================================================
-- VERIFY THE FIX
-- =====================================================

-- Test that functions work correctly
DO $$
DECLARE
    test_result TEXT;
BEGIN
    -- Try to get current user's QR code
    SELECT qr_code_id INTO test_result FROM get_my_qr_code() LIMIT 1;
    
    IF test_result IS NOT NULL THEN
        RAISE NOTICE '✅ QR code functions are working! Your QR code: %', test_result;
    ELSE
        RAISE NOTICE '⚠️  QR code generated but check your setup';
    END IF;
END $$;
