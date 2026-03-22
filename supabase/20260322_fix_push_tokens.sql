-- Fix push token unique constraint
-- The old `user_push_tokens_user_id_key` constraint (UNIQUE on user_id alone)
-- blocks the upsert which uses onConflict: "user_id, device_token".
-- A user can have multiple devices, so user_id alone should NOT be unique.

BEGIN;

-- Drop the old single-column constraint that blocks upsert
ALTER TABLE user_push_tokens DROP CONSTRAINT IF EXISTS user_push_tokens_user_id_key;

-- Ensure the composite constraint exists (from 20260321_schema_fixes.sql)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_push_tokens_user_device'
  ) THEN
    -- Deduplicate first (keep newest per user+token pair)
    DELETE FROM user_push_tokens a
    USING user_push_tokens b
    WHERE a.user_id = b.user_id
      AND a.device_token = b.device_token
      AND a.updated_at < b.updated_at;

    ALTER TABLE user_push_tokens
      ADD CONSTRAINT uq_user_push_tokens_user_device UNIQUE (user_id, device_token);
  END IF;
END $$;

DO $$ BEGIN
  RAISE NOTICE 'Fixed user_push_tokens: dropped user_id-only unique, ensured (user_id, device_token) composite unique';
END $$;

COMMIT;
