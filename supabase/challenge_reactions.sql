-- ============================================================================
-- CHALLENGE REACTIONS: "Battle Cries" & "Power Ups"
-- ============================================================================
-- Quick-reaction system for active challenges:
--   ⚔️ Competition → Trash Talk / Battle Cries  (competitive banter)
--   🤝 Accountability → Power Ups / Cheers       (motivational support)
--
-- Think Rocket League quick-chat meets iMessage reactions.
-- Rate-limited to 5 per challenge per day to keep it fun, not spammy.
-- ============================================================================


-- ============================================================================
-- 1. CREATE TABLE: challenge_reactions
-- ============================================================================
CREATE TABLE IF NOT EXISTS challenge_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES group_challenges(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    reaction_key TEXT NOT NULL,        -- e.g. "trash_catch_me", "cheer_you_got_this"
    reaction_emoji TEXT NOT NULL,      -- e.g. "🔥", "💪"
    reaction_text TEXT NOT NULL,       -- e.g. "Catch me if you can!"
    reaction_category TEXT NOT NULL DEFAULT 'trash_talk',  -- 'trash_talk' or 'cheer'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_challenge_reactions_challenge
    ON challenge_reactions(challenge_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_challenge_reactions_recipient
    ON challenge_reactions(recipient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_challenge_reactions_sender_daily
    ON challenge_reactions(challenge_id, sender_id, created_at);

-- RLS policies
ALTER TABLE challenge_reactions ENABLE ROW LEVEL SECURITY;

-- Users can see reactions for challenges they participate in
DROP POLICY IF EXISTS "Users can view reactions for their challenges" ON challenge_reactions;
CREATE POLICY "Users can view reactions for their challenges" ON challenge_reactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = challenge_reactions.challenge_id
            AND user_id = auth.uid()
        )
    );

-- Users can insert reactions (rate limiting handled in RPC)
DROP POLICY IF EXISTS "Users can send reactions" ON challenge_reactions;
CREATE POLICY "Users can send reactions" ON challenge_reactions
    FOR INSERT
    WITH CHECK (sender_id = auth.uid());


-- ============================================================================
-- 2. RPC: send_challenge_reaction
-- ============================================================================
DROP FUNCTION IF EXISTS send_challenge_reaction(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION send_challenge_reaction(
    p_challenge_id TEXT,
    p_recipient_id TEXT,
    p_reaction_key TEXT,
    p_reaction_emoji TEXT,
    p_reaction_text TEXT,
    p_reaction_category TEXT DEFAULT 'trash_talk'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    recipient_uuid UUID;
    today_count INT;
    sender_name TEXT;
    challenge_title TEXT;
    new_reaction_id UUID;
    notif_title TEXT;
    notif_body TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    recipient_uuid := p_recipient_id::UUID;

    -- Validate: sender is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
        AND status = 'accepted'
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not a participant in this challenge');
    END IF;

    -- Validate: recipient is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = recipient_uuid
        AND status = 'accepted'
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Recipient is not in this challenge');
    END IF;

    -- Validate: challenge is active
    IF NOT EXISTS (
        SELECT 1 FROM group_challenges
        WHERE id = challenge_uuid AND status = 'active'
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Challenge is not active');
    END IF;

    -- Rate limit: max 5 reactions per challenge per day per sender
    SELECT COUNT(*) INTO today_count
    FROM challenge_reactions
    WHERE challenge_id = challenge_uuid
      AND sender_id = current_user_uuid
      AND created_at > CURRENT_DATE;

    IF today_count >= 5 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Daily reaction limit reached (5/day)', 'remaining', 0);
    END IF;

    -- Insert the reaction
    INSERT INTO challenge_reactions (
        challenge_id, sender_id, recipient_id,
        reaction_key, reaction_emoji, reaction_text, reaction_category,
        created_at
    ) VALUES (
        challenge_uuid, current_user_uuid, recipient_uuid,
        p_reaction_key, p_reaction_emoji, p_reaction_text, p_reaction_category,
        NOW()
    )
    RETURNING id INTO new_reaction_id;

    -- Get sender name and challenge title for notification
    SELECT name INTO sender_name FROM user_profiles WHERE id = current_user_uuid;
    SELECT title INTO challenge_title FROM group_challenges WHERE id = challenge_uuid;

    -- Build notification text based on category
    IF p_reaction_category = 'trash_talk' THEN
        notif_title := COALESCE(sender_name, 'Someone') || ' is talking smack! 🗣️';
        notif_body := p_reaction_emoji || ' "' || p_reaction_text || '"';
    ELSE
        notif_title := COALESCE(sender_name, 'Someone') || ' sent you a boost! 💪';
        notif_body := p_reaction_emoji || ' "' || p_reaction_text || '"';
    END IF;

    -- Queue push notification to recipient
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            recipient_uuid,
            'challenge_reaction',
            notif_title,
            notif_body,
            jsonb_build_object(
                'type', 'challenge_reaction',
                'challenge_id', challenge_uuid::TEXT,
                'from_user_id', current_user_uuid::TEXT,
                'from_user_name', COALESCE(sender_name, 'Someone'),
                'reaction_key', p_reaction_key,
                'reaction_emoji', p_reaction_emoji,
                'reaction_text', p_reaction_text,
                'reaction_category', p_reaction_category
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        -- Don't fail the reaction if notification fails
        RAISE WARNING 'Failed to queue reaction notification: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'reaction_id', new_reaction_id::TEXT,
        'remaining_today', 5 - today_count - 1
    );
END;
$$;

GRANT EXECUTE ON FUNCTION send_challenge_reaction(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 3. RPC: get_challenge_reactions
-- Returns recent reactions for a challenge (last 20), newest first.
-- ============================================================================
DROP FUNCTION IF EXISTS get_challenge_reactions(TEXT, INT);

CREATE OR REPLACE FUNCTION get_challenge_reactions(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 20
)
RETURNS TABLE (
    reaction_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_photo_url TEXT,
    recipient_id UUID,
    reaction_key TEXT,
    reaction_emoji TEXT,
    reaction_text TEXT,
    reaction_category TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    -- Verify caller is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        cr.id AS reaction_id,
        cr.sender_id,
        up.name AS sender_name,
        up.profile_photo_url AS sender_photo_url,
        cr.recipient_id,
        cr.reaction_key,
        cr.reaction_emoji,
        cr.reaction_text,
        cr.reaction_category,
        cr.created_at
    FROM challenge_reactions cr
    JOIN user_profiles up ON up.id = cr.sender_id
    WHERE cr.challenge_id = challenge_uuid
    ORDER BY cr.created_at DESC
    LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_reactions(TEXT, INT) TO authenticated;


-- ============================================================================
-- 4. RPC: get_challenge_reaction_count_today
-- Returns how many reactions the caller has sent today for this challenge.
-- ============================================================================
DROP FUNCTION IF EXISTS get_challenge_reaction_count_today(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_reaction_count_today(
    p_challenge_id TEXT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    count_today INT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    SELECT COUNT(*)::INT INTO count_today
    FROM challenge_reactions
    WHERE challenge_id = challenge_uuid
      AND sender_id = current_user_uuid
      AND created_at > CURRENT_DATE;

    RETURN count_today;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_reaction_count_today(TEXT) TO authenticated;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ CHALLENGE REACTIONS DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Created:';
    RAISE NOTICE '   • challenge_reactions table (with RLS + indexes)';
    RAISE NOTICE '   • send_challenge_reaction()   — send a reaction (rate-limited 5/day)';
    RAISE NOTICE '   • get_challenge_reactions()    — fetch recent reactions';
    RAISE NOTICE '   • get_challenge_reaction_count_today() — daily quota check';
    RAISE NOTICE '';
    RAISE NOTICE '🎮 Usage:';
    RAISE NOTICE '   ⚔️ Competition → "Battle Cries" (trash_talk category)';
    RAISE NOTICE '   🤝 Accountability → "Power Ups" (cheer category)';
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
