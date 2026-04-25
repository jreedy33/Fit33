-- ============================================================================
-- Migration #112 — Fix REPLICA IDENTITY for 1v1 / group challenge realtime
-- 2026-04-25
-- ============================================================================
--
-- USER REPORT (2026-04-25):
--   "all of my challenge 1v1 and group challenge doesn't appear to be
--    updating in real time"
--
-- ROOT CAUSE:
--   `challenge_type_migration.sql` added `challenge_daily_progress` to the
--   `supabase_realtime` publication but never set `REPLICA IDENTITY FULL`.
--   Without it, Supabase Realtime UPDATE events only carry the primary key
--   — `user_id`, `progress_value`, `challenge_id` are all null in the
--   payload. The iOS handler (`RealtimeService.handleDailyProgressChange`)
--   guards on `record["user_id"]` and silently drops the event, so opponent
--   live updates never reach the dashboard widget.
--
--   `challenge_participants` and `group_challenges` were also in the
--   publication without REPLICA IDENTITY FULL, with the same effect for
--   status / total_progress changes.
--
-- COMPANION FIX (Swift):
--   `RealtimeService.swift` no longer skips own-update refreshes, and
--   `ChallengeService.fetchMinInterval` was lowered from 5.0s → 1.0s so
--   post-workout multi-challenge refetches aren't dropped by the throttle.
--
-- IDEMPOTENT: ALTER TABLE ... REPLICA IDENTITY FULL is safe to re-run.
--   ALTER PUBLICATION ADD TABLE is wrapped in IF-NOT-EXISTS check.
--
-- This migration replaces the un-dated `fix_challenge_realtime_replica_identity.sql`
-- which was sitting in `supabase/` without an entry in MIGRATION_INDEX.md.
-- ============================================================================

BEGIN;

-- 1. challenge_daily_progress — the CRITICAL table for live opponent updates
ALTER TABLE challenge_daily_progress REPLICA IDENTITY FULL;

-- 2. challenge_participants — carries total_progress and status changes
ALTER TABLE challenge_participants REPLICA IDENTITY FULL;

-- 3. group_challenges — carries challenge status (active → completed)
ALTER TABLE group_challenges REPLICA IDENTITY FULL;

-- ─────────────────────────────────────────────────────────────────────────
-- Ensure publication membership (idempotent)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'challenge_daily_progress'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;
        RAISE NOTICE '✅ Added challenge_daily_progress to supabase_realtime publication';
    ELSE
        RAISE NOTICE 'ℹ️ challenge_daily_progress already in supabase_realtime publication';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'challenge_participants'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_participants;
        RAISE NOTICE '✅ Added challenge_participants to supabase_realtime publication';
    ELSE
        RAISE NOTICE 'ℹ️ challenge_participants already in supabase_realtime publication';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'group_challenges'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE group_challenges;
        RAISE NOTICE '✅ Added group_challenges to supabase_realtime publication';
    ELSE
        RAISE NOTICE 'ℹ️ group_challenges already in supabase_realtime publication';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────
-- Verify final state (writes to NOTICE log so deployer can confirm)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE '── REPLICA IDENTITY for challenge realtime tables ──';
    FOR r IN
        SELECT c.relname AS table_name,
               CASE c.relreplident
                   WHEN 'd' THEN 'DEFAULT (pk only) ❌'
                   WHEN 'n' THEN 'NOTHING ❌'
                   WHEN 'f' THEN 'FULL ✅'
                   WHEN 'i' THEN 'INDEX'
               END AS replica_identity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN (
              'challenge_daily_progress',
              'challenge_participants',
              'group_challenges'
          )
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '  % → %', r.table_name, r.replica_identity;
    END LOOP;
END $$;

COMMIT;
