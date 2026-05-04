-- ============================================================================
-- 20260535 — Battle cry: recipient "opened app" ack + sender bubble clear
-- ============================================================================
-- Product contract (2026-05-04):
--   • Recipient: foreground app → mark unread received battle cries so the
--     sender's dashboard "pending delivery" bubble can clear via realtime.
--   • Sender: subscribe to UPDATE on rows they sent; when
--     recipient_opened_app_at flips non-null, drop local pending-outgoing UI.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE RPC, grants.
-- SECURITY DEFINER RPC uses auth.uid() only (Infra #9 — no p_user_id).
-- ============================================================================

BEGIN;

ALTER TABLE challenge_reactions
    ADD COLUMN IF NOT EXISTS recipient_opened_app_at TIMESTAMPTZ;

COMMENT ON COLUMN challenge_reactions.recipient_opened_app_at IS
    'Set when the recipient next foregrounds the app after this row was inserted; drives sender-side "they saw it" bubble dismissal via realtime UPDATE.';

CREATE INDEX IF NOT EXISTS idx_challenge_reactions_recipient_unopened
    ON challenge_reactions (recipient_id, created_at DESC)
    WHERE recipient_opened_app_at IS NULL;

DROP FUNCTION IF EXISTS ack_my_pending_battle_cry_receipts();

CREATE OR REPLACE FUNCTION ack_my_pending_battle_cry_receipts()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE challenge_reactions
    SET recipient_opened_app_at = now()
    WHERE recipient_id = auth.uid()
      AND recipient_opened_app_at IS NULL
      AND created_at > (now() - interval '30 days');

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION ack_my_pending_battle_cry_receipts() TO authenticated;

DROP FUNCTION IF EXISTS list_acknowledged_battle_cry_ids_for_sender();

CREATE OR REPLACE FUNCTION list_acknowledged_battle_cry_ids_for_sender()
RETURNS TABLE (reaction_id UUID)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT cr.id AS reaction_id
    FROM challenge_reactions cr
    WHERE cr.sender_id = auth.uid()
      AND cr.recipient_opened_app_at IS NOT NULL
      AND cr.created_at > (now() - interval '30 days');
$$;

GRANT EXECUTE ON FUNCTION list_acknowledged_battle_cry_ids_for_sender() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
