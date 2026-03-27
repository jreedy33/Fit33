-- ============================================================================
-- FIX: Add push notification to invite_to_private_challenge
-- Date: 2026-03-26
--
-- The original function had INSERT INTO notifications (table doesn't exist).
-- The fix migration removed it but never replaced it with push_notification_queue.
-- This adds the push notification so invited users actually get notified.
--
-- Also adds private challenge invites to badge count visibility.
-- ============================================================================

CREATE OR REPLACE FUNCTION invite_to_private_challenge(
    p_challenge_id TEXT,
    p_invited_user_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_invited_user_id UUID;
    v_role TEXT;
    v_allow_member_invites BOOLEAN;
    v_max_members INT;
    v_member_count INT;
    v_invite_id UUID;
    v_inviter_name TEXT;
    v_challenge_title TEXT;
    v_challenge_emoji TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    v_invited_user_id := p_invited_user_id::UUID;

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check inviter is a member and get their role
    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    -- Check if non-admin inviting is allowed
    SELECT allow_member_invites, max_members, member_count, title, emoji
    INTO v_allow_member_invites, v_max_members, v_member_count, v_challenge_title, v_challenge_emoji
    FROM private_challenges
    WHERE id = v_challenge_id AND status = 'active';

    IF v_role != 'admin' AND NOT v_allow_member_invites THEN
        RAISE EXCEPTION 'Only admins can invite members to this challenge';
    END IF;

    -- Check capacity
    IF v_max_members IS NOT NULL AND v_member_count >= v_max_members THEN
        RAISE EXCEPTION 'This challenge is full';
    END IF;

    -- Check if already a member
    IF EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = v_challenge_id AND user_id = v_invited_user_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'User is already a member';
    END IF;

    -- Check if already invited (pending)
    IF EXISTS (
        SELECT 1 FROM private_challenge_invites
        WHERE challenge_id = v_challenge_id AND invited_user_id = v_invited_user_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'User already has a pending invite';
    END IF;

    -- Get inviter name for notifications
    SELECT name INTO v_inviter_name FROM user_profiles WHERE id = current_user_uuid;

    -- Create the invite (upsert: if previously declined, reset to pending)
    INSERT INTO private_challenge_invites (
        challenge_id, invited_user_id, invited_by, status, created_at, responded_at
    ) VALUES (
        v_challenge_id, v_invited_user_id, current_user_uuid, 'pending', NOW(), NULL
    )
    ON CONFLICT (challenge_id, invited_user_id) 
    DO UPDATE SET 
        status = 'pending',
        invited_by = current_user_uuid,
        created_at = NOW(),
        responded_at = NULL
    RETURNING id INTO v_invite_id;

    -- Queue push notification to the invited user
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            v_invited_user_id,
            'private_challenge_invite',
            COALESCE(v_inviter_name, 'Someone') || ' invited you to a private community 🔒',
            'Join "' || v_challenge_title || '" — tap to accept or decline.',
            jsonb_build_object(
                'type', 'private_challenge_invite',
                'challenge_id', v_challenge_id::TEXT,
                'invite_id', v_invite_id::TEXT,
                'from_user_id', current_user_uuid::TEXT,
                'from_user_name', COALESCE(v_inviter_name, 'Someone'),
                'challenge_title', v_challenge_title,
                'challenge_emoji', COALESCE(v_challenge_emoji, '🔒')
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue push notification for private invite: %', SQLERRM;
    END;

    RETURN v_invite_id;
END;
$$;

GRANT EXECUTE ON FUNCTION invite_to_private_challenge(TEXT, TEXT) TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  ✅ invite_to_private_challenge updated';
    RAISE NOTICE '   → Now queues push notification to invited user';
    RAISE NOTICE '   → Format: "[Name] invited you to a private community 🔒"';
    RAISE NOTICE '   → Body: "Join [title] — tap to accept or decline."';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
