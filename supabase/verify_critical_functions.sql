-- ============================================================================
-- VERIFICATION SCRIPT: Check for Missing Critical RPC Functions
-- ============================================================================
-- Run this script in Supabase SQL Editor to identify missing functions
-- that are breaking the app
-- ============================================================================

-- Check for missing critical functions
DO $$
DECLARE
  missing_functions TEXT[] := ARRAY[]::TEXT[];
  existing_functions TEXT[] := ARRAY[]::TEXT[];
  critical_functions TEXT[] := ARRAY[
    'get_friends',
    'get_received_workouts',
    'get_sent_workouts',
    'get_pending_friend_requests',
    'get_sent_friend_requests',
    'send_friend_request',
    'accept_friend_request',
    'decline_friend_request',
    'cancel_friend_request',
    'are_friends',
    'search_users',
    'create_user_profile',
    'get_active_challenges',
    'get_challenge_templates',
    'create_challenge',
    'create_group_challenge',
    'respond_to_challenge',
    'cancel_challenge',
    'log_challenge_progress',
    'get_pending_challenge_invites',
    'get_pending_sent_challenges',
    'accept_group_challenge',
    'decline_group_challenge',
    'leave_group_challenge',
    'cancel_group_challenge',
    'log_group_challenge_progress',
    'get_challenge_details',
    'get_active_group_challenges'
  ];
  func TEXT;
  func_exists BOOLEAN;
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '🔍 CHECKING CRITICAL RPC FUNCTIONS';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  
  -- Check each function
  FOREACH func IN ARRAY critical_functions
  LOOP
    SELECT EXISTS (
      SELECT 1 FROM information_schema.routines
      WHERE routine_schema = 'public'
        AND routine_name = func
        AND routine_type = 'FUNCTION'
    ) INTO func_exists;
    
    IF func_exists THEN
      existing_functions := array_append(existing_functions, func);
      RAISE NOTICE '✅ % exists', func;
    ELSE
      missing_functions := array_append(missing_functions, func);
      RAISE WARNING '❌ % is MISSING!', func;
    END IF;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '📊 SUMMARY';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE 'Total functions checked: %', array_length(critical_functions, 1);
  RAISE NOTICE 'Functions existing: %', COALESCE(array_length(existing_functions, 1), 0);
  RAISE NOTICE 'Functions missing: %', COALESCE(array_length(missing_functions, 1), 0);
  RAISE NOTICE '';
  
  IF array_length(missing_functions, 1) > 0 THEN
    RAISE NOTICE '🚨 MISSING FUNCTIONS:';
    RAISE NOTICE '   %', array_to_string(missing_functions, E'\n   ');
    RAISE NOTICE '';
    RAISE NOTICE '⚡️ ACTION REQUIRED:';
    RAISE NOTICE '   Run: supabase/create_friend_rpc_functions.sql';
    RAISE NOTICE '   This will create the missing friend system functions.';
  ELSE
    RAISE NOTICE '✅ All critical functions exist!';
  END IF;
  
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Show detailed function information
SELECT 
  routine_name as "Function Name",
  routine_type as "Type",
  CASE 
    WHEN routine_name IN ('get_friends', 'get_received_workouts', 'get_sent_workouts') 
    THEN '🔥 CRITICAL - Profile Screen'
    WHEN routine_name IN ('get_pending_friend_requests', 'send_friend_request', 'accept_friend_request')
    THEN '⚡️ HIGH - Friend System'
    WHEN routine_name IN ('get_active_challenges', 'create_user_profile')
    THEN '⭐️ HIGH - Core Features'
    ELSE '✅ Standard'
  END as "Priority"
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
  AND routine_name IN (
    'get_friends',
    'get_received_workouts',
    'get_sent_workouts',
    'get_pending_friend_requests',
    'get_sent_friend_requests',
    'send_friend_request',
    'accept_friend_request',
    'decline_friend_request',
    'cancel_friend_request',
    'are_friends',
    'search_users',
    'create_user_profile',
    'get_active_challenges'
  )
ORDER BY 
  CASE 
    WHEN routine_name IN ('get_friends', 'get_received_workouts', 'get_sent_workouts') THEN 1
    WHEN routine_name IN ('get_pending_friend_requests', 'send_friend_request') THEN 2
    ELSE 3
  END,
  routine_name;
