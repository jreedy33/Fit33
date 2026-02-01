-- ============================================================================
-- ERASE ALL CHALLENGES
-- Run this in Supabase SQL Editor to delete all challenge data
-- ============================================================================

-- Delete in correct order due to foreign key constraints

-- 1. Delete daily progress (references challenge_participants)
DELETE FROM challenge_daily_progress;
SELECT 'Deleted all challenge_daily_progress' AS step1;

-- 2. Delete participants (references friend_challenges)
DELETE FROM challenge_participants;
SELECT 'Deleted all challenge_participants' AS step2;

-- 3. Delete challenges
DELETE FROM friend_challenges;
SELECT 'Deleted all friend_challenges' AS step3;

-- Verify all tables are empty
SELECT 'Verification:' AS verification;
SELECT COUNT(*) AS remaining_daily_progress FROM challenge_daily_progress;
SELECT COUNT(*) AS remaining_participants FROM challenge_participants;
SELECT COUNT(*) AS remaining_challenges FROM friend_challenges;

SELECT '✅ All challenges have been erased!' AS result;
