-- STEP 1: Drop the existing function
-- Run this FIRST, then run FIX_CHALLENGE_STEP2_CREATE.sql

DROP FUNCTION IF EXISTS get_active_challenges();

SELECT '✅ Function dropped. Now run FIX_CHALLENGE_STEP2_CREATE.sql' as result;
