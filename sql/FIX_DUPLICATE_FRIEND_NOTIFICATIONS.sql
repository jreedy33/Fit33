-- Fix: Remove duplicate friend request notification trigger
-- The send_friend_request() function already creates notifications,
-- so we don't need the trigger on friendships table

-- Drop the duplicate trigger on friendships
DROP TRIGGER IF EXISTS on_friend_request_sent ON friendships;

-- Also drop the function if it's no longer used
-- (Keep it commented out in case other code uses it)
-- DROP FUNCTION IF EXISTS queue_friend_request_notification();

-- Verify the trigger is gone
SELECT 
    tgname AS trigger_name,
    proname AS function_name
FROM pg_trigger tg
JOIN pg_class c ON tg.tgrelid = c.oid
JOIN pg_proc p ON tg.tgfoid = p.oid
WHERE c.relname = 'friendships'
AND tgname = 'on_friend_request_sent';

-- Should return no rows if successfully dropped
