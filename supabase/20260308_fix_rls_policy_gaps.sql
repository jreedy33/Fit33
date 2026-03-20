-- Migration: Fix RLS policy gaps for challenge tables
-- Date: 2026-03-08
-- Reason: Missing DELETE policies on challenge tables identified in security audit

BEGIN;

-- group_challenges: add DELETE policy
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'group_challenges' AND policyname = 'users_delete_own_challenges'
  ) THEN
    CREATE POLICY "users_delete_own_challenges" ON group_challenges
    FOR DELETE USING (created_by = auth.uid());
  END IF;
END $$;

-- challenge_participants: add DELETE policy
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'challenge_participants' AND policyname = 'users_delete_own_participation'
  ) THEN
    CREATE POLICY "users_delete_own_participation" ON challenge_participants
    FOR DELETE USING (user_id = auth.uid());
  END IF;
END $$;

-- challenge_daily_progress: add DELETE policy
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'challenge_daily_progress' AND policyname = 'users_delete_own_progress'
  ) THEN
    CREATE POLICY "users_delete_own_progress" ON challenge_daily_progress
    FOR DELETE USING (user_id = auth.uid());
  END IF;
END $$;

COMMIT;

-- ROLLBACK:
-- DROP POLICY IF EXISTS "users_delete_own_challenges" ON group_challenges;
-- DROP POLICY IF EXISTS "users_delete_own_participation" ON challenge_participants;
-- DROP POLICY IF EXISTS "users_delete_own_progress" ON challenge_daily_progress;
