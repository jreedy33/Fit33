-- ============================================================================
-- SCHEMA FIXES FROM DEV SESSION LOG ANALYSIS (Session 2)
-- Date: 2026-03-21
-- Source: Claude analysis of dev session B0124A17
-- Fixes:
--   1. Add was_successful column to collaborative_workout_data
--   2. Add matched_user_id column to user_synced_contacts
-- ============================================================================

BEGIN;

-- 1. collaborative_workout_data missing was_successful
-- CollaborativeLearningEngine.swift line 154 inserts this column
ALTER TABLE collaborative_workout_data
  ADD COLUMN IF NOT EXISTS was_successful BOOLEAN DEFAULT true;

DO $$ BEGIN
  RAISE NOTICE '1. Added was_successful BOOLEAN to collaborative_workout_data';
END $$;

-- 2. user_synced_contacts missing matched_user_id
-- The RPC get_friends_from_contacts references usc.matched_user_id
ALTER TABLE user_synced_contacts
  ADD COLUMN IF NOT EXISTS matched_user_id UUID REFERENCES user_profiles(id);

CREATE INDEX IF NOT EXISTS idx_user_synced_contacts_matched
  ON user_synced_contacts(matched_user_id)
  WHERE matched_user_id IS NOT NULL;

DO $$ BEGIN
  RAISE NOTICE '2. Added matched_user_id UUID to user_synced_contacts';
END $$;

COMMIT;
