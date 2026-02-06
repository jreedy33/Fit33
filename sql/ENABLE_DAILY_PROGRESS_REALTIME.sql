-- =====================================================
-- ENABLE REALTIME ON CHALLENGE DAILY PROGRESS
-- =====================================================
-- This enables instant opponent progress updates in the challenge widget
-- Instead of polling every 30 seconds, updates appear immediately!
-- =====================================================

-- Add challenge_daily_progress to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;

-- Verify it's enabled
SELECT 'Realtime-enabled tables:' as info;
SELECT tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
AND tablename IN (
    'friendships', 
    'shared_workouts', 
    'challenge_participants', 
    'friend_challenges',
    'challenge_daily_progress'  -- NEW!
)
ORDER BY tablename;

SELECT '✅ challenge_daily_progress is now realtime-enabled!' as status;
SELECT 'Opponent progress will update INSTANTLY in the challenge widget' as result;
