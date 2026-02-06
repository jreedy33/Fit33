-- =====================================================
-- ENABLE SUPABASE REALTIME ON TABLES
-- =====================================================
-- This adds the required tables to the supabase_realtime publication
-- which enables real-time subscriptions from the iOS app
-- =====================================================

-- Check current realtime-enabled tables
SELECT 'Currently enabled tables:' as info;
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime';

-- Add tables to realtime publication
-- (Will skip if already added)

ALTER PUBLICATION supabase_realtime ADD TABLE friendships;
ALTER PUBLICATION supabase_realtime ADD TABLE shared_workouts;
ALTER PUBLICATION supabase_realtime ADD TABLE challenge_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE friend_challenges;

-- Verify tables are now enabled
SELECT 'After enabling - tables in realtime:' as info;
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

SELECT '✅ Realtime enabled on social tables!' as status;
