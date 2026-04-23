-- ============================================================================
-- Content Moderation System
-- Adds automated moderation infrastructure: logging table, is_hidden columns,
-- rate limiting, suspension enforcement, and fetch RPC filtering.
-- ============================================================================

-- 1. Moderation log table (admin-only, stores all flagged content)
CREATE TABLE IF NOT EXISTS content_moderation_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
    table_name TEXT NOT NULL,
    record_id TEXT,
    content_snippet TEXT NOT NULL,
    flagged_categories JSONB NOT NULL DEFAULT '[]'::JSONB,
    category_scores JSONB NOT NULL DEFAULT '{}'::JSONB,
    action_taken TEXT NOT NULL DEFAULT 'hidden'
        CHECK (action_taken IN ('blocked', 'hidden', 'approved', 'confirmed')),
    admin_reviewed BOOLEAN NOT NULL DEFAULT FALSE,
    admin_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE content_moderation_log ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_moderation_log_user ON content_moderation_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderation_log_unreviewed ON content_moderation_log (admin_reviewed, created_at DESC)
    WHERE admin_reviewed = FALSE;
CREATE INDEX IF NOT EXISTS idx_moderation_log_table ON content_moderation_log (table_name, created_at DESC);

-- No user-facing RLS policies — admin CMS reads via service role


-- 2. Add is_hidden column to all user-generated content tables
ALTER TABLE private_challenge_chat ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_reactions ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE shared_workouts ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE group_challenges ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE private_challenges ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE community_challenges ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE friend_activity_feed ADD COLUMN IF NOT EXISTS is_hidden BOOLEAN NOT NULL DEFAULT FALSE;

-- Partial indexes for efficient filtering (only index the rare hidden rows)
CREATE INDEX IF NOT EXISTS idx_pcc_hidden ON private_challenge_chat (is_hidden) WHERE is_hidden = TRUE;
CREATE INDEX IF NOT EXISTS idx_reactions_hidden ON challenge_reactions (is_hidden) WHERE is_hidden = TRUE;
CREATE INDEX IF NOT EXISTS idx_shared_workouts_hidden ON shared_workouts (is_hidden) WHERE is_hidden = TRUE;
CREATE INDEX IF NOT EXISTS idx_activity_feed_hidden ON friend_activity_feed (is_hidden) WHERE is_hidden = TRUE;


-- 3. Update send_private_challenge_message with rate limiting + suspension check
CREATE OR REPLACE FUNCTION send_private_challenge_message(
    p_challenge_id TEXT,
    p_content TEXT,
    p_message_type TEXT DEFAULT 'text'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_message_id UUID;
    v_recent_count INT;
BEGIN
    current_user_uuid := auth.uid();

    -- Suspension check
    IF EXISTS (
        SELECT 1 FROM user_suspensions
        WHERE user_id = current_user_uuid
          AND lifted_at IS NULL
          AND (expires_at IS NULL OR expires_at > NOW())
    ) THEN
        RAISE EXCEPTION 'Your account is suspended';
    END IF;

    -- Verify membership
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    -- Rate limit: max 50 messages per hour per challenge
    SELECT COUNT(*) INTO v_recent_count
    FROM private_challenge_chat
    WHERE sender_id = current_user_uuid
      AND challenge_id = p_challenge_id::UUID
      AND created_at > NOW() - INTERVAL '1 hour';

    IF v_recent_count >= 50 THEN
        RAISE EXCEPTION 'Rate limit exceeded. Please wait before sending more messages.';
    END IF;

    -- Rate limit: max 1 message per 2 seconds (anti-spam burst)
    IF EXISTS (
        SELECT 1 FROM private_challenge_chat
        WHERE sender_id = current_user_uuid
          AND challenge_id = p_challenge_id::UUID
          AND created_at > NOW() - INTERVAL '2 seconds'
    ) THEN
        RAISE EXCEPTION 'Please wait a moment before sending another message.';
    END IF;

    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (p_challenge_id::UUID, current_user_uuid, COALESCE(p_message_type, 'text'), p_content)
    RETURNING id INTO v_message_id;

    RETURN v_message_id;
END;
$$;

GRANT EXECUTE ON FUNCTION send_private_challenge_message(TEXT, TEXT, TEXT) TO authenticated;


-- 4. Update get_private_challenge_messages to filter hidden messages
CREATE OR REPLACE FUNCTION get_private_challenge_messages(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 50,
    p_before_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    message_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_username TEXT,
    sender_photo_url TEXT,
    message_type TEXT,
    content TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    is_current_user BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    -- Verify membership
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    RETURN QUERY
    SELECT
        pcc.id AS message_id,
        pcc.sender_id,
        up.name AS sender_name,
        up.username AS sender_username,
        up.profile_photo_url AS sender_photo_url,
        pcc.message_type,
        pcc.content,
        pcc.metadata,
        pcc.created_at,
        (pcc.sender_id = current_user_uuid) AS is_current_user
    FROM private_challenge_chat pcc
    JOIN user_profiles up ON up.id = pcc.sender_id
    WHERE pcc.challenge_id = p_challenge_id::UUID
      AND NOT pcc.is_hidden
      AND (p_before_id IS NULL OR pcc.id < p_before_id::UUID)
    ORDER BY pcc.created_at DESC
    LIMIT COALESCE(p_limit, 50);
END;
$$;

GRANT EXECUTE ON FUNCTION get_private_challenge_messages(TEXT, INT, TEXT) TO authenticated;


-- 5. Admin RPC: get flagged content for CMS moderation dashboard
CREATE OR REPLACE FUNCTION get_flagged_content(
    p_status TEXT DEFAULT 'unreviewed',
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    log_id UUID,
    user_id UUID,
    user_name TEXT,
    user_username TEXT,
    table_name TEXT,
    record_id TEXT,
    content_snippet TEXT,
    flagged_categories JSONB,
    category_scores JSONB,
    action_taken TEXT,
    admin_reviewed BOOLEAN,
    admin_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        cml.id AS log_id,
        cml.user_id,
        up.name AS user_name,
        up.username AS user_username,
        cml.table_name,
        cml.record_id,
        cml.content_snippet,
        cml.flagged_categories,
        cml.category_scores,
        cml.action_taken,
        cml.admin_reviewed,
        cml.admin_notes,
        cml.reviewed_at,
        cml.created_at
    FROM content_moderation_log cml
    LEFT JOIN user_profiles up ON up.id = cml.user_id
    WHERE (p_status = 'all' OR (p_status = 'unreviewed' AND cml.admin_reviewed = FALSE))
    ORDER BY cml.created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_flagged_content(TEXT, INT, INT) TO service_role;


-- 6. Admin RPC: review flagged content (approve or confirm flag)
CREATE OR REPLACE FUNCTION review_flagged_content(
    p_log_id TEXT,
    p_action TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_log RECORD;
BEGIN
    SELECT * INTO v_log FROM content_moderation_log WHERE id = p_log_id::UUID;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Moderation log entry not found';
    END IF;

    -- Update the log entry
    UPDATE content_moderation_log
    SET admin_reviewed = TRUE,
        admin_notes = p_notes,
        action_taken = p_action,
        reviewed_at = NOW()
    WHERE id = p_log_id::UUID;

    -- If approving (false positive), unhide the original content
    IF p_action = 'approved' AND v_log.record_id IS NOT NULL AND v_log.table_name IS NOT NULL THEN
        EXECUTE format(
            'UPDATE %I SET is_hidden = FALSE WHERE id = $1',
            v_log.table_name
        ) USING v_log.record_id::UUID;
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION review_flagged_content(TEXT, TEXT, TEXT) TO service_role;


-- 7. Admin RPC: get moderation stats
CREATE OR REPLACE FUNCTION get_moderation_stats()
RETURNS TABLE (
    total_flagged BIGINT,
    unreviewed_count BIGINT,
    flagged_today BIGINT,
    top_offenders JSONB,
    category_breakdown JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM content_moderation_log)::BIGINT AS total_flagged,
        (SELECT COUNT(*) FROM content_moderation_log WHERE admin_reviewed = FALSE)::BIGINT AS unreviewed_count,
        (SELECT COUNT(*) FROM content_moderation_log WHERE created_at > CURRENT_DATE)::BIGINT AS flagged_today,
        (
            SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::JSONB)
            FROM (
                SELECT cml.user_id, up.name, up.username, COUNT(*) AS flag_count
                FROM content_moderation_log cml
                LEFT JOIN user_profiles up ON up.id = cml.user_id
                WHERE cml.user_id IS NOT NULL
                GROUP BY cml.user_id, up.name, up.username
                ORDER BY flag_count DESC
                LIMIT 10
            ) t
        ) AS top_offenders,
        (
            SELECT COALESCE(jsonb_object_agg(cat, cnt), '{}'::JSONB)
            FROM (
                SELECT elem::TEXT AS cat, COUNT(*) AS cnt
                FROM content_moderation_log,
                     jsonb_array_elements_text(flagged_categories) AS elem
                GROUP BY elem
                ORDER BY cnt DESC
            ) t
        ) AS category_breakdown;
END;
$$;

GRANT EXECUTE ON FUNCTION get_moderation_stats() TO service_role;


DO $$ BEGIN
    RAISE NOTICE 'Content moderation system created: content_moderation_log, is_hidden columns, rate limits, suspension checks, admin RPCs';
END $$;
