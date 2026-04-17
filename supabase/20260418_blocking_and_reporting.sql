-- ============================================================================
-- Blocking + Reporting RPCs (Sprint 2, 2026-04-18)
-- Q2-7 — App Review requires user blocking and content reporting in any
-- social app. Server-side infra already exists (user_blocks,
-- content_moderation_log). This migration adds the two RPCs the iOS client
-- needs to round it out:
--
--   1. get_blocked_users() — list the caller's blocks with profile info for
--      the new Settings → Blocked Users screen.
--   2. report_content() — append to content_moderation_log from the client
--      when a user taps "Report". Admin CMS triages.
--
-- Both are SECURITY DEFINER and use auth.uid() — no IDOR surface.
-- ============================================================================

-- 1. get_blocked_users ---------------------------------------------------------

CREATE OR REPLACE FUNCTION get_blocked_users()
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    username TEXT,
    profile_photo_url TEXT,
    blocked_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
        ub.blocked_id AS user_id,
        COALESCE(up.name, 'Blocked user') AS name,
        up.username,
        up.profile_photo_url,
        ub.created_at AS blocked_at
    FROM user_blocks ub
    LEFT JOIN user_profiles up ON up.id = ub.blocked_id
    WHERE ub.blocker_id = current_user_uuid
    ORDER BY ub.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_blocked_users() TO authenticated;

COMMENT ON FUNCTION get_blocked_users() IS
  'Sprint 2: returns the caller''s block list with profile info for the in-app '
  'Blocked Users settings screen. IDOR-safe — uses auth.uid() only.';


-- 2. report_content -----------------------------------------------------------

CREATE OR REPLACE FUNCTION report_content(
    p_table_name TEXT,
    p_record_id TEXT,
    p_reported_user_id UUID,
    p_content_snippet TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_log_id UUID;
    v_allowed_tables CONSTANT TEXT[] := ARRAY[
        'private_challenge_chat',
        'challenge_reactions',
        'shared_workouts',
        'group_challenges',
        'private_challenges',
        'community_challenges',
        'friend_activity_feed',
        'user_profiles'
    ];
BEGIN
    current_user_uuid := auth.uid();

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_table_name IS NULL OR NOT (p_table_name = ANY(v_allowed_tables)) THEN
        RAISE EXCEPTION 'Invalid table name for report: %', p_table_name;
    END IF;

    IF p_reported_user_id = current_user_uuid THEN
        RAISE EXCEPTION 'Cannot report your own content';
    END IF;

    -- Trim the snippet so we never dump a novel into the moderation log.
    INSERT INTO content_moderation_log (
        user_id,
        table_name,
        record_id,
        content_snippet,
        flagged_categories,
        category_scores,
        action_taken,
        admin_reviewed,
        admin_notes
    )
    VALUES (
        p_reported_user_id,
        p_table_name,
        p_record_id,
        LEFT(COALESCE(p_content_snippet, ''), 500),
        '["user_report"]'::JSONB,
        jsonb_build_object(
            'reporter_id', current_user_uuid,
            'reason', COALESCE(NULLIF(TRIM(p_reason), ''), 'unspecified')
        ),
        'hidden',
        FALSE,
        'User-reported via iOS client'
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

GRANT EXECUTE ON FUNCTION report_content(TEXT, TEXT, UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION report_content(TEXT, TEXT, UUID, TEXT, TEXT) IS
  'Sprint 2: user-initiated content report. Writes to content_moderation_log '
  'with flagged_categories=["user_report"] and category_scores.reporter_id for '
  'admin triage. p_table_name is whitelisted. Intended to be called alongside '
  'block_user() from the iOS Report-and-Block sheet.';
