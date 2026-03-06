-- ============================================================================
-- ADD: lookup_private_challenge_by_code RPC (preview without joining)
-- ============================================================================
-- Problem: When a user enters a private challenge code, the app auto-joins
-- without showing a preview. Users should see challenge details and
-- explicitly choose to join.
--
-- This migration adds a lookup_private_challenge_by_code function that:
--   1. Looks up the private challenge by join_code
--   2. Returns preview info (title, emoji, type, target, member count, creator)
--   3. Indicates if the current user is already a member
--   4. Does NOT join the user — that still uses join_private_challenge_by_code
-- ============================================================================

DROP FUNCTION IF EXISTS lookup_private_challenge_by_code(TEXT);

CREATE OR REPLACE FUNCTION lookup_private_challenge_by_code(
    p_code TEXT
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
    creator_name TEXT,
    creator_username TEXT,
    creator_photo_url TEXT,
    already_joined BOOLEAN,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_code TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_code := upper(trim(p_code));

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
        up.name AS creator_name,
        up.username AS creator_username,
        up.profile_photo_url AS creator_photo_url,
        COALESCE(
            (SELECT TRUE FROM private_challenge_members pcm
             WHERE pcm.challenge_id = pc.id
             AND pcm.user_id = current_user_uuid
             AND pcm.is_active = TRUE),
            FALSE
        ) AS already_joined,
        pc.status
    FROM private_challenges pc
    LEFT JOIN user_profiles up ON up.id = pc.created_by
    WHERE (pc.join_code = v_code OR pc.join_code = trim(p_code))
    AND pc.status = 'active';
END;
$$;

GRANT EXECUTE ON FUNCTION lookup_private_challenge_by_code(TEXT) TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ lookup_private_challenge_by_code CREATED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  Returns challenge preview info without joining.';
    RAISE NOTICE '  Used by the Join-by-Code sheet to show details';
    RAISE NOTICE '  before the user confirms they want to join.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
