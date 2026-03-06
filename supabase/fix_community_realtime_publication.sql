-- ============================================================================
-- FIX: Add community challenge tables to Supabase Realtime Publication
-- ============================================================================
--
-- Problem: community_challenge_daily_progress and community_challenge_participants
-- were NEVER added to the supabase_realtime publication. This means Postgres
-- doesn't broadcast changes to these tables via WebSocket, so the Swift
-- RealtimeService never receives events when other users log community
-- challenge progress. This is why community widgets don't update in real-time.
--
-- The private challenge tables had the same issue, fixed in
-- fix_private_realtime_publication.sql. This migration does the same for
-- community challenge tables.
-- ============================================================================

DO $$
BEGIN
    -- community_challenge_daily_progress: needed for real-time progress updates
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_daily_progress;
        RAISE NOTICE '✅ Added community_challenge_daily_progress to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ community_challenge_daily_progress already in realtime publication';
    END;

    -- community_challenge_participants: needed for real-time join/leave events
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_participants;
        RAISE NOTICE '✅ Added community_challenge_participants to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ community_challenge_participants already in realtime publication';
    END;

    -- community_challenges: needed for challenge status changes (optional but good to have)
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenges;
        RAISE NOTICE '✅ Added community_challenges to supabase_realtime publication';
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE '⏭️ community_challenges already in realtime publication';
    END;
END $$;

-- Set REPLICA IDENTITY FULL so Supabase sends complete row data in events
-- (without this, UPDATE events only contain the primary key, not the changed columns)
ALTER TABLE community_challenge_daily_progress REPLICA IDENTITY FULL;
ALTER TABLE community_challenge_participants REPLICA IDENTITY FULL;
ALTER TABLE community_challenges REPLICA IDENTITY FULL;

-- ============================================================================
-- VERIFICATION QUERY (run manually to confirm)
-- ============================================================================
-- SELECT schemaname, tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'supabase_realtime'
-- AND tablename LIKE 'community_challenge%'
-- ORDER BY tablename;
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ COMMUNITY CHALLENGE REALTIME PUBLICATION FIX COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  Tables added to supabase_realtime publication:';
    RAISE NOTICE '   - community_challenge_daily_progress (progress updates)';
    RAISE NOTICE '   - community_challenge_participants (join/leave events)';
    RAISE NOTICE '   - community_challenges (challenge status changes)';
    RAISE NOTICE '';
    RAISE NOTICE '  REPLICA IDENTITY set to FULL for complete row data.';
    RAISE NOTICE '';
    RAISE NOTICE '  Run this SQL in Supabase Dashboard → SQL Editor';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
