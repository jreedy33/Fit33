-- ============================================================================
-- FIX: Add join_private_challenge_by_code RPC
-- ============================================================================
-- Problem: Private challenges have a join_code column but there was no RPC
-- function to join by code. When a user enters a private challenge code into
-- the "Join by Code" dialog, it only tries the community challenge RPC
-- (join_community_challenge) which fails with "Challenge not found".
--
-- This migration adds a join_private_challenge_by_code function that:
--   1. Looks up the private challenge by join_code
--   2. Validates the challenge is active and not full
--   3. Adds the user as a member (or reactivates if previously left)
--   4. Updates member_count
--   5. Posts a system chat message
-- ============================================================================

-- Drop existing if needed (clean re-create)
DROP FUNCTION IF EXISTS join_private_challenge_by_code(TEXT);

CREATE OR REPLACE FUNCTION join_private_challenge_by_code(
    p_join_code TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge RECORD;
    v_user_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_join_code IS NULL OR trim(p_join_code) = '' THEN
        RAISE EXCEPTION 'Join code is required';
    END IF;

    -- Find the private challenge by join code
    SELECT * INTO v_challenge
    FROM private_challenges
    WHERE join_code = upper(trim(p_join_code)) AND status = 'active';

    IF v_challenge IS NULL THEN
        RAISE EXCEPTION 'Private challenge not found or no longer active';
    END IF;

    -- Check max members
    IF v_challenge.max_members IS NOT NULL AND v_challenge.member_count >= v_challenge.max_members THEN
        RAISE EXCEPTION 'This challenge is full';
    END IF;

    -- Check if already a member
    IF EXISTS (
        SELECT 1 FROM private_challenge_members pcm_check
        WHERE pcm_check.challenge_id = v_challenge.id
        AND pcm_check.user_id = current_user_uuid
        AND pcm_check.is_active = TRUE
    ) THEN
        -- Already an active member — just return
        RETURN v_challenge.id;
    END IF;

    -- Add member (upsert: reactivate if previously left)
    INSERT INTO private_challenge_members (
        challenge_id, user_id, role, is_active, joined_at
    ) VALUES (
        v_challenge.id, current_user_uuid, 'member', TRUE, NOW()
    )
    ON CONFLICT (challenge_id, user_id)
    DO UPDATE SET
        is_active = TRUE,
        joined_at = NOW(),
        last_active_at = NOW();

    -- Update member count
    UPDATE private_challenges
    SET member_count = (
        SELECT COUNT(*) FROM private_challenge_members
        WHERE challenge_id = v_challenge.id AND is_active = TRUE
    ),
    updated_at = NOW()
    WHERE id = v_challenge.id;

    -- Get user name for system message
    SELECT name INTO v_user_name FROM user_profiles WHERE id = current_user_uuid;

    -- Post system message in chat
    INSERT INTO private_challenge_chat (
        challenge_id, sender_id, message_type, content
    ) VALUES (
        v_challenge.id, current_user_uuid, 'system',
        COALESCE(v_user_name, 'Someone') || ' joined via code!'
    );

    RETURN v_challenge.id;
END;
$$;

GRANT EXECUTE ON FUNCTION join_private_challenge_by_code(TEXT) TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ join_private_challenge_by_code CREATED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  Users can now join private challenges by entering';
    RAISE NOTICE '  the 6-character join code. The "Join by Code" UI';
    RAISE NOTICE '  will try community first, then private on failure.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
