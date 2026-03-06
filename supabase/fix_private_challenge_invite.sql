-- ============================================================================
-- FIX: Private Challenge Invite + Detail Errors
-- ============================================================================
-- Fixes two bugs:
--
-- 1. get_private_challenge_detail — "column reference 'challenge_id' is ambiguous"
--    The RETURNS TABLE declares output columns (challenge_id, title, etc.) which
--    become PL/pgSQL variables. The IF NOT EXISTS membership check used unqualified
--    column names that clash with those variables.
--    FIX: Add table alias to the membership check.
--
-- 2. invite_to_private_challenge — "relation 'notifications' does not exist"
--    The function tries INSERT INTO notifications, which doesn't exist.
--    PostgreSQL validates the table at parse time even when the WHERE clause
--    would skip execution.
--    FIX: Remove the INSERT INTO notifications (use push notifications instead).
-- ============================================================================


-- ============================================================================
-- FIX 1: get_private_challenge_detail — qualify ambiguous column references
-- ============================================================================
CREATE OR REPLACE FUNCTION get_private_challenge_detail(
    p_challenge_id TEXT,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    member_count INT,
    max_members INT,
    join_code TEXT,
    is_recurring BOOLEAN,
    show_leaderboard BOOLEAN,
    allow_member_invites BOOLEAN,
    notifications_enabled BOOLEAN,
    total_completions INT,
    created_by UUID,
    status TEXT,
    created_at TIMESTAMPTZ,
    -- My stats
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT,
    my_total_progress INT,
    my_rank INT,
    my_role TEXT,
    -- Community stats
    avg_today_progress INT,
    top_today_progress INT,
    total_active_today INT,
    completion_rate_today DOUBLE PRECISION,
    -- Full leaderboard
    leaderboard JSONB,
    -- Pending invites count
    pending_invites_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Verify user is a member (use table alias to avoid ambiguity with RETURNS TABLE columns)
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members pcm_check
        WHERE pcm_check.challenge_id = v_challenge_id
          AND pcm_check.user_id = current_user_uuid
          AND pcm_check.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    RETURN QUERY
    SELECT
        pc.id AS challenge_id,
        pc.title,
        pc.description,
        pc.emoji,
        pc.challenge_type,
        pc.daily_target,
        pc.target_unit,
        pc.member_count,
        pc.max_members,
        pc.join_code,
        pc.is_recurring,
        pc.show_leaderboard,
        pc.allow_member_invites,
        pc.notifications_enabled,
        pc.total_completions,
        pc.created_by,
        pc.status,
        pc.created_at,
        -- My stats
        COALESCE((SELECT dp.progress_value FROM private_challenge_daily_progress dp WHERE dp.challenge_id = v_challenge_id AND dp.user_id = current_user_uuid AND dp.progress_date = today_date), 0)::INT,
        COALESCE((SELECT m.days_completed FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.current_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.best_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.total_progress FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        (
            SELECT COUNT(*)::INT + 1
            FROM private_challenge_members other_m
            LEFT JOIN private_challenge_daily_progress other_dp
                ON other_dp.challenge_id = other_m.challenge_id AND other_dp.user_id = other_m.user_id AND other_dp.progress_date = today_date
            WHERE other_m.challenge_id = v_challenge_id AND other_m.is_active = TRUE AND other_m.user_id != current_user_uuid
            AND COALESCE(other_dp.progress_value, 0) > COALESCE(
                (SELECT dp2.progress_value FROM private_challenge_daily_progress dp2 WHERE dp2.challenge_id = v_challenge_id AND dp2.user_id = current_user_uuid AND dp2.progress_date = today_date), 0
            )
        )::INT,
        (SELECT m2.role FROM private_challenge_members m2 WHERE m2.challenge_id = v_challenge_id AND m2.user_id = current_user_uuid)::TEXT,
        -- Community stats
        COALESCE((SELECT AVG(COALESCE(dp3.progress_value, 0))::INT FROM private_challenge_members m3 LEFT JOIN private_challenge_daily_progress dp3 ON dp3.challenge_id = m3.challenge_id AND dp3.user_id = m3.user_id AND dp3.progress_date = today_date WHERE m3.challenge_id = v_challenge_id AND m3.is_active = TRUE), 0)::INT,
        COALESCE((SELECT MAX(COALESCE(dp4.progress_value, 0))::INT FROM private_challenge_members m4 LEFT JOIN private_challenge_daily_progress dp4 ON dp4.challenge_id = m4.challenge_id AND dp4.user_id = m4.user_id AND dp4.progress_date = today_date WHERE m4.challenge_id = v_challenge_id AND m4.is_active = TRUE), 0)::INT,
        (SELECT COUNT(*)::INT FROM private_challenge_daily_progress dp5 WHERE dp5.challenge_id = v_challenge_id AND dp5.progress_date = today_date AND dp5.progress_value > 0)::INT,
        CASE WHEN pc.member_count > 0 THEN
            (SELECT COUNT(*)::DOUBLE PRECISION / pc.member_count FROM private_challenge_daily_progress dp6 WHERE dp6.challenge_id = v_challenge_id AND dp6.progress_date = today_date AND dp6.target_hit = TRUE)
        ELSE 0 END,
        -- Full leaderboard
        (
            SELECT jsonb_agg(entry ORDER BY entry->>'rank')
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC),
                    'user_id', m5.user_id,
                    'name', up5.name,
                    'username', up5.username,
                    'profile_photo_url', up5.profile_photo_url,
                    'role', m5.role,
                    'today_progress', COALESCE(dp7.progress_value, 0),
                    'days_completed', m5.days_completed,
                    'current_streak', m5.current_streak,
                    'best_streak', m5.best_streak,
                    'target_hit_today', COALESCE(dp7.target_hit, FALSE),
                    'is_current_user', (m5.user_id = current_user_uuid)
                ) AS entry
                FROM private_challenge_members m5
                JOIN user_profiles up5 ON up5.id = m5.user_id
                LEFT JOIN private_challenge_daily_progress dp7
                    ON dp7.challenge_id = m5.challenge_id AND dp7.user_id = m5.user_id AND dp7.progress_date = today_date
                WHERE m5.challenge_id = v_challenge_id AND m5.is_active = TRUE
                ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC
            ) sub
        ) AS leaderboard,
        -- Pending invites count
        (SELECT COUNT(*)::INT FROM private_challenge_invites pci WHERE pci.challenge_id = v_challenge_id AND pci.status = 'pending')
    FROM private_challenges pc
    WHERE pc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_private_challenge_detail(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- FIX 2: invite_to_private_challenge — remove non-existent notifications table
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
    SELECT allow_member_invites, max_members, member_count, title
    INTO v_allow_member_invites, v_max_members, v_member_count, v_challenge_title
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

    -- Note: Push notifications for the invite are handled app-side via
    -- PushNotificationService, not via a DB notifications table.

    RETURN v_invite_id;
END;
$$;

GRANT EXECUTE ON FUNCTION invite_to_private_challenge(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- DONE
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ PRIVATE CHALLENGE FIX APPLIED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Fix 1: get_private_challenge_detail';
    RAISE NOTICE '   → Added table alias (pcm_check) to membership check';
    RAISE NOTICE '   → Resolves "challenge_id is ambiguous" error';
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Fix 2: invite_to_private_challenge';
    RAISE NOTICE '   → Removed INSERT INTO notifications (table does not exist)';
    RAISE NOTICE '   → Push notifications handled app-side instead';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
