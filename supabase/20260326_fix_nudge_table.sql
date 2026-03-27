-- Fix: "column challenge_id does not exist" on group_challenge_nudges
-- The nudge_group_challenge_member RPC references group_challenge_nudges.challenge_id,
-- but the table may not exist or may be missing the column.
-- Crash IDs: 9acc6b4f, a535ce96 (v1.35.0, first seen v1.32.0)

BEGIN;

CREATE TABLE IF NOT EXISTS group_challenge_nudges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL,
    sender_id UUID NOT NULL,
    recipient_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE group_challenge_nudges ADD COLUMN IF NOT EXISTS challenge_id UUID;
ALTER TABLE group_challenge_nudges ADD COLUMN IF NOT EXISTS sender_id UUID;
ALTER TABLE group_challenge_nudges ADD COLUMN IF NOT EXISTS recipient_id UUID;
ALTER TABLE group_challenge_nudges ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_nudges_challenge_sender_date
    ON group_challenge_nudges (challenge_id, sender_id, recipient_id, created_at);

ALTER TABLE group_challenge_nudges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert nudges" ON group_challenge_nudges;
CREATE POLICY "Users can insert nudges"
    ON group_challenge_nudges FOR INSERT TO authenticated
    WITH CHECK (sender_id = auth.uid());

DROP POLICY IF EXISTS "Users can view own nudges" ON group_challenge_nudges;
CREATE POLICY "Users can view own nudges"
    ON group_challenge_nudges FOR SELECT TO authenticated
    USING (sender_id = auth.uid() OR recipient_id = auth.uid());

COMMIT;
