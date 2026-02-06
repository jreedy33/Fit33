-- =====================================================
-- ENABLE REALTIME ON CHALLENGE DAILY PROGRESS
-- For instant opponent progress updates in challenge widget
-- =====================================================

-- Add challenge_daily_progress to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;

-- Verify it's enabled
SELECT tablename, '✅ Realtime enabled' as status
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
AND tablename = 'challenge_daily_progress';

SELECT '✅ Opponent progress will now update in real-time!' as result;
