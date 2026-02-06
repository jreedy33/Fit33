-- =====================================================================
-- 🧪 NOTIFICATION TESTING SUITE
-- =====================================================================
-- This file contains tests for EACH notification type
-- Run each section individually to test that notification type
-- 
-- ⚠️ IMPORTANT: Replace USER_ID values with your actual test user ID
-- Joseph's ID: e31f9d3b-a43e-44a8-a31f-6826e9d17e1a
-- =====================================================================

-- Set your test user ID here (replace with actual UUID)
DO $$ 
BEGIN
    PERFORM set_config('notification_test.user_id', 'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a', false);
END $$;

-- =====================================================================
-- TEST 1: DIRECT PUSH QUEUE TEST
-- Tests if push notifications can be sent directly (bypasses app_notifications)
-- This is the most fundamental test
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 1: DIRECT PUSH QUEUE TEST' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Insert directly into push queue
INSERT INTO push_notification_queue (
    recipient_user_id,
    notification_type,
    title,
    body,
    data,
    status
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,  -- Replace with your user ID
    'test_direct',
    '🔬 Direct Queue Test',
    'If you receive this, the push queue and Edge Function are working!',
    '{"test": true, "timestamp": "' || NOW()::text || '"}'::jsonb,
    'pending'
)
RETURNING id, 'Direct push test inserted - check your phone!' AS status;

-- Verify it's in the queue
SELECT 
    id, 
    notification_type, 
    status, 
    created_at,
    'Should be pending, then sent within 1 minute' AS expected
FROM push_notification_queue 
WHERE notification_type = 'test_direct'
ORDER BY created_at DESC 
LIMIT 1;

-- =====================================================================
-- TEST 2: APP_NOTIFICATIONS TRIGGER TEST
-- Tests if trigger correctly copies to push_notification_queue
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 2: APP_NOTIFICATIONS TRIGGER TEST' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Insert into app_notifications (should trigger push queue entry)
INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,  -- Replace with your user ID
    'test_trigger',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    '⚡ Trigger Test',
    'If you receive this, the app_notifications trigger is working!',
    false
)
RETURNING id, 'App notification created - checking push queue...' AS status;

-- Wait a moment and check push queue
SELECT 
    'app_notifications' AS source,
    id,
    notification_type,
    created_at
FROM app_notifications 
WHERE notification_type = 'test_trigger'
ORDER BY created_at DESC 
LIMIT 1;

SELECT 
    'push_notification_queue' AS source,
    id,
    notification_type,
    status,
    created_at,
    CASE 
        WHEN id IS NOT NULL THEN '✅ Trigger fired correctly!'
        ELSE '❌ TRIGGER NOT FIRING - Check trigger setup'
    END AS diagnosis
FROM push_notification_queue 
WHERE notification_type = 'test_trigger'
ORDER BY created_at DESC 
LIMIT 1;

-- =====================================================================
-- TEST 3: FRIEND REQUEST NOTIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 3: FRIEND REQUEST NOTIFICATION' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Simulate friend request notification
INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,  -- Recipient
    'friend_request_received',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,  -- Sender (self for test)
    'New Friend Request! 👋',
    'Test User wants to be your workout buddy.',
    false
)
RETURNING id, 'Friend request notification created' AS status;

-- Verify in push queue
SELECT 
    id,
    notification_type,
    title,
    status,
    created_at
FROM push_notification_queue 
WHERE notification_type = 'friend_request_received'
ORDER BY created_at DESC 
LIMIT 1;

-- =====================================================================
-- TEST 4: CHALLENGE INVITE NOTIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 4: CHALLENGE INVITE NOTIFICATION' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'challenge_invite',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'New Challenge Invite 🏆',
    'Test Challenger challenged you to "7-Day Push-up Challenge"',
    false
)
RETURNING id, 'Challenge invite notification created' AS status;

-- Verify
SELECT 
    id,
    notification_type,
    title,
    status,
    created_at
FROM push_notification_queue 
WHERE notification_type = 'challenge_invite'
ORDER BY created_at DESC 
LIMIT 1;

-- =====================================================================
-- TEST 5: CHALLENGE ACCEPTED NOTIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 5: CHALLENGE ACCEPTED NOTIFICATION' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'challenge_accepted',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'Challenge Accepted! ⚔️',
    'Your friend accepted your challenge. Game on!',
    false
)
RETURNING id, 'Challenge accepted notification created' AS status;

-- =====================================================================
-- TEST 6: SHARED WORKOUT NOTIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 6: SHARED WORKOUT NOTIFICATION' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'shared_workout',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'Test User sent you a workout! 💪',
    'Tap to check out "Killer Chest Day" and start training.',
    false
)
RETURNING id, 'Shared workout notification created' AS status;

-- =====================================================================
-- TEST 7: CONTACT JOINED NOTIFICATION
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '🧪 TEST 7: CONTACT JOINED NOTIFICATION' AS test;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

INSERT INTO app_notifications (
    user_id,
    notification_type,
    reference_id,
    from_user_id,
    title,
    body,
    is_read
) VALUES (
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'contact_joined',
    gen_random_uuid(),
    'e31f9d3b-a43e-44a8-a31f-6826e9d17e1a'::uuid,
    'Your contact joined Fit33! 🎉',
    'John Doe just joined Fit33. Add them as a friend!',
    false
)
RETURNING id, 'Contact joined notification created' AS status;

-- =====================================================================
-- TEST RESULTS SUMMARY
-- =====================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '📊 TEST RESULTS SUMMARY' AS section;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Check all test notifications
SELECT 
    notification_type,
    title,
    status,
    error_message,
    created_at,
    sent_at,
    CASE 
        WHEN status = 'sent' THEN '✅ DELIVERED'
        WHEN status = 'pending' THEN '⏳ PENDING (wait 1 min)'
        WHEN status = 'failed' THEN '❌ FAILED: ' || COALESCE(error_message, 'Unknown')
        ELSE '❓ ' || status
    END AS result
FROM push_notification_queue
WHERE created_at > NOW() - INTERVAL '10 minutes'
AND (notification_type LIKE 'test%' OR notification_type IN (
    'friend_request_received',
    'challenge_invite', 
    'challenge_accepted',
    'shared_workout',
    'contact_joined'
))
ORDER BY created_at DESC;

-- =====================================================================
-- CLEANUP (Optional - uncomment to delete test notifications)
-- =====================================================================
/*
DELETE FROM push_notification_queue WHERE notification_type LIKE 'test%';
DELETE FROM app_notifications WHERE notification_type LIKE 'test%';
*/

SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '✅ Testing complete! Check your device for notifications.' AS status;
SELECT 'Wait ~1 minute for cron job to process pending notifications.' AS note;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;
