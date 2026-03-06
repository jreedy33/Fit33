-- ============================================================================
-- FIX: Add private challenge tables to Supabase Realtime Publication
-- ============================================================================
--
-- Problem: private_challenge_members and private_challenge_daily_progress
-- have REPLICA IDENTITY FULL (set in private_challenges_migration.sql) but
-- were never added to the supabase_realtime publication. This means Postgres
-- doesn't broadcast changes to these tables, so the Swift RealtimeService
-- never receives WebSocket events for private challenge joins or progress.
--
-- This migration adds them to the publication so real-time subscriptions work.
-- ============================================================================

DO $$
BEGIN
    -- private_challenge_members: needed for real-time join/leave events
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_members;
        RAISE NOTICE '✅ Added private_challenge_members to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ private_challenge_members already in realtime publication';
    END;

    -- private_challenge_daily_progress: needed for real-time progress updates
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_daily_progress;
        RAISE NOTICE '✅ Added private_challenge_daily_progress to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ private_challenge_daily_progress already in realtime publication';
    END;

    -- private_challenges: needed for challenge status changes (optional but good to have)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE private_challenges;
        RAISE NOTICE '✅ Added private_challenges to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ private_challenges already in realtime publication';
    END;

    -- private_challenge_invites: needed for invite status changes
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_invites;
        RAISE NOTICE '✅ Added private_challenge_invites to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ private_challenge_invites already in realtime publication';
    END;
END $$;

-- Verify REPLICA IDENTITY is already set (it should be from the original migration)
-- These are idempotent, so safe to run again
ALTER TABLE private_challenge_members REPLICA IDENTITY FULL;
ALTER TABLE private_challenge_daily_progress REPLICA IDENTITY FULL;
ALTER TABLE private_challenges REPLICA IDENTITY FULL;
ALTER TABLE private_challenge_invites REPLICA IDENTITY FULL;

-- ============================================================================
-- VERIFICATION QUERY (run manually to confirm)
-- ============================================================================
-- SELECT schemaname, tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'supabase_realtime'
-- AND tablename LIKE 'private_challenge%'
-- ORDER BY tablename;
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ PRIVATE CHALLENGE REALTIME PUBLICATION FIX COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  Tables added to supabase_realtime publication:';
    RAISE NOTICE '   - private_challenge_members (join/leave events)';
    RAISE NOTICE '   - private_challenge_daily_progress (progress updates)';
    RAISE NOTICE '   - private_challenges (challenge status changes)';
    RAISE NOTICE '   - private_challenge_invites (invite status changes)';
    RAISE NOTICE '';
    RAISE NOTICE '  Run this SQL in Supabase Dashboard → SQL Editor';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
