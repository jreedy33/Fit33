-- ============================================================================
-- FIX: Enable REPLICA IDENTITY FULL on challenge tables for Realtime
-- ============================================================================
-- 
-- PROBLEM:
--   challenge_daily_progress and challenge_participants are missing
--   REPLICA IDENTITY FULL. Without it, Supabase Realtime only sends the
--   primary key on UPDATE events (not the full row). This means:
--     - user_id, progress_value, challenge_id are all MISSING from events
--     - The Swift realtime handlers silently drop these events
--     - Opponents never see live progress updates
--
-- WHY TWO DIFFERENT NUMBERS:
--   1. challenge_participants.total_progress fires a partial event →
--      handler does a "defensive refresh" but the data may be stale
--   2. challenge_daily_progress.progress_value fires NO usable event →
--      opponent's today-progress stays stale until 2-min polling fallback
--
-- FIX:
--   Set REPLICA IDENTITY FULL on all 3 challenge tables so Supabase
--   Realtime sends the complete row (including old values) on every
--   INSERT/UPDATE/DELETE event.
--
-- NOTE: The community_challenge_* tables already have this set
--   (see community_friends_gating.sql lines 927-929). This was missed
--   for the regular challenge tables.
--
-- SAFE TO RE-RUN: ALTER TABLE ... REPLICA IDENTITY FULL is idempotent.
-- ============================================================================

-- 1. challenge_daily_progress — the CRITICAL table for live opponent updates
--    Without this, the Quick Realtime Test shows "❌ NO EVENT after 5 seconds"
ALTER TABLE challenge_daily_progress REPLICA IDENTITY FULL;

-- 2. challenge_participants — carries total_progress and status changes
--    Without this, opponent status/progress events only contain the PK
ALTER TABLE challenge_participants REPLICA IDENTITY FULL;

-- 3. group_challenges — carries challenge status (active → completed)
--    Without this, challenge completion events lack details
ALTER TABLE group_challenges REPLICA IDENTITY FULL;

-- ============================================================================
-- VERIFY: Confirm all challenge tables are in the supabase_realtime publication
-- ============================================================================
DO $$
BEGIN
    -- challenge_daily_progress
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'challenge_daily_progress'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;
        RAISE NOTICE '✅ Added challenge_daily_progress to supabase_realtime publication';
    ELSE
        RAISE NOTICE '✅ challenge_daily_progress already in supabase_realtime publication';
    END IF;

    -- challenge_participants
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'challenge_participants'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_participants;
        RAISE NOTICE '✅ Added challenge_participants to supabase_realtime publication';
    ELSE
        RAISE NOTICE '✅ challenge_participants already in supabase_realtime publication';
    END IF;

    -- group_challenges
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'group_challenges'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE group_challenges;
        RAISE NOTICE '✅ Added group_challenges to supabase_realtime publication';
    ELSE
        RAISE NOTICE '✅ group_challenges already in supabase_realtime publication';
    END IF;
END $$;

-- ============================================================================
-- VERIFY: Show current REPLICA IDENTITY setting for all challenge tables
-- ============================================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT c.relname AS table_name,
               CASE c.relreplident
                   WHEN 'd' THEN 'DEFAULT (pk only)'
                   WHEN 'n' THEN 'NOTHING'
                   WHEN 'f' THEN 'FULL ✅'
                   WHEN 'i' THEN 'INDEX'
               END AS replica_identity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
        AND c.relname IN ('challenge_daily_progress', 'challenge_participants', 'group_challenges')
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '  % → %', r.table_name, r.replica_identity;
    END LOOP;
END $$;
