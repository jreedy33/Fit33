-- ============================================================================
-- 20260722 — Remove the 5/day smack-talk rate limit on send_challenge_reaction
-- ============================================================================
-- "For now" lift of the per-(challenge, sender) daily reaction cap so users
-- can talk smack / send hype without bumping into the 5-per-day wall while
-- the new home-screen widget shout-bubble feature is in active dogfood.
-- All other validation in the RPC stays intact:
--   • Sender is an accepted participant in the challenge.
--   • Recipient is an accepted participant in the challenge.
--   • Challenge is in `status = 'active'`.
-- The push-notification queue insert + JSONB shape (`type`, `challenge_id`,
-- `from_user_name`, `reaction_emoji`, `reaction_text`, `reaction_category`)
-- are preserved verbatim so the new iOS `SilentPushHandler.handleChallengeReaction`
-- + `SmackTalkWidgetBridge` paths keep working without a coordinated
-- client release.
--
-- Backward-compat: `remaining_today` stays in the response shape (sentinel
-- value `999`) so older `iOS::SendReactionResponse` decoders that read the
-- `remaining_today` key keep deserializing. The current iOS picker UI is
-- updated in the same commit to stop displaying the remaining-count badge
-- and stop gating the send button on it.
--
-- Companion: `get_challenge_reaction_count_today()` is intentionally LEFT
-- IN PLACE — it's a read-only count, no longer used by the picker but kept
-- for future analytics + an easy revert path if we re-introduce a cap.
-- To re-impose a daily cap later, restore the `today_count >= N` block in
-- this RPC + flip the iOS picker's gating back on.
-- ============================================================================

BEGIN;

-- Drop EVERY known overload before CREATE OR REPLACE per supabase-rules
-- invariant 12. The 6-arg shape is canonical (six TEXT params, the last
-- with a default of 'trash_talk'); a 5-arg shape would only exist on
-- pre-default-arg deployments. DROP IF EXISTS for both is defensive and
-- a no-op on the canonical deploy.
DROP FUNCTION IF EXISTS send_challenge_reaction(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS send_challenge_reaction(TEXT, TEXT, TEXT, TEXT, TEXT);

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
    sender_name TEXT;
    challenge_title TEXT;
    new_reaction_id UUID;
    notif_title TEXT;
    notif_body TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    recipient_uuid := p_recipient_id::UUID;

    -- Validate: sender is an accepted participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
        AND status = 'accepted'
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not a participant in this challenge');
    END IF;

    -- Validate: recipient is an accepted participant
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

    -- 5/day rate limit removed 2026-04-29 (this migration). To restore,
    -- re-introduce the SELECT COUNT(*) … created_at > CURRENT_DATE block
    -- here against `challenge_reactions` and the matching IF guard. The
    -- daily-count read RPC `get_challenge_reaction_count_today` is still
    -- in place for analytics / future re-cap.

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

    -- Queue push notification to recipient. Payload shape MUST stay
    -- aligned with `iOS::SilentPushHandler.handleChallengeReaction`'s
    -- decode keys (`challenge_id`, `from_user_name`, `reaction_emoji`,
    -- `reaction_text`, `reaction_category`, top-level `type`).
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
        -- Don't fail the reaction if notification queue write blows up.
        RAISE WARNING 'Failed to queue reaction notification: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'reaction_id', new_reaction_id::TEXT,
        -- Sentinel — `iOS::SendReactionResponse.remainingToday` stays
        -- decodable; the picker UI ignores it now (no badge, no gating).
        'remaining_today', 999
    );
END;
$$;

GRANT EXECUTE ON FUNCTION send_challenge_reaction(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- Audit: confirm the 5/day check is gone from the deployed function body
-- ============================================================================
DO $$
DECLARE
    src TEXT;
BEGIN
    SELECT prosrc INTO src
    FROM pg_proc
    WHERE proname = 'send_challenge_reaction'
      AND pronargs = 6;

    IF src IS NULL THEN
        RAISE EXCEPTION 'send_challenge_reaction(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) is missing after migration';
    END IF;

    -- Catch the canonical pattern of the old gate. If somebody edits
    -- this migration in the future to re-introduce a cap, they'll
    -- want to delete or update this audit too.
    IF src ~ 'today_count\s*>=\s*\d+' THEN
        RAISE EXCEPTION 'Migration failed — today_count >= N rate-limit check still present in send_challenge_reaction prosrc';
    END IF;

    -- Sanity: the body still queues into push_notification_queue with
    -- type='challenge_reaction' (otherwise the widget shout-bubble
    -- pipeline silently breaks).
    IF src !~ 'challenge_reaction' THEN
        RAISE EXCEPTION 'Migration failed — push_notification_queue insert with type=challenge_reaction missing from send_challenge_reaction prosrc';
    END IF;
END $$;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ SMACK-TALK RATE LIMIT REMOVED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • send_challenge_reaction now allows unlimited daily sends';
    RAISE NOTICE '   • All participant + status validation preserved';
    RAISE NOTICE '   • Push-notification queue payload unchanged (widget pipeline safe)';
    RAISE NOTICE '   • get_challenge_reaction_count_today() left in place for analytics';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
