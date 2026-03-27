-- Fix: "null value in column group_challenge_id" when nudging
-- The table has BOTH group_challenge_id (original, NOT NULL) and challenge_id (added later, nullable).
-- The RPC writes to challenge_id, leaving group_challenge_id NULL → constraint violation.
-- Solution: copy any existing data, drop the old column, make challenge_id NOT NULL.

BEGIN;

-- Copy existing data from old column into new column where missing
UPDATE group_challenge_nudges
SET challenge_id = group_challenge_id
WHERE challenge_id IS NULL AND group_challenge_id IS NOT NULL;

-- Drop the old column
ALTER TABLE group_challenge_nudges DROP COLUMN group_challenge_id;

-- Make challenge_id NOT NULL now that it has all the data
ALTER TABLE group_challenge_nudges ALTER COLUMN challenge_id SET NOT NULL;

-- Recreate the index
DROP INDEX IF EXISTS idx_nudges_challenge_sender_date;
CREATE INDEX idx_nudges_challenge_sender_date
    ON group_challenge_nudges (challenge_id, sender_id, recipient_id, created_at);

COMMIT;
