-- ============================================================================
-- SMART INSIGHTS: Phase 4.3 - Targeted Push Notifications
-- ============================================================================
-- RPC function that generates smart nudge notifications based on
-- cross-table correlation data. Call via cron or manually.
--
-- Writes to push_notification_queue for delivery by the
-- send-push-notification Edge Function.
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_smart_nudges()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_nudges_created INT := 0;
  v_user RECORD;
BEGIN
  -- Nudge 1: Users with no friends who haven't worked out in 3+ days
  FOR v_user IN
    SELECT src.user_id, up.name
    FROM v_social_retention_correlation src
    JOIN user_profiles up ON up.id = src.user_id
    WHERE src.friend_count = 0
      AND src.days_since_last_workout >= 3
      AND src.days_since_last_workout < 14
      AND NOT EXISTS (
        SELECT 1 FROM push_notification_queue pnq
        WHERE pnq.recipient_user_id = src.user_id
          AND pnq.notification_type = 'smart_nudge_social'
          AND pnq.created_at > now() - INTERVAL '7 days'
      )
  LOOP
    INSERT INTO push_notification_queue (recipient_user_id, title, body, notification_type, data, status)
    VALUES (
      v_user.user_id,
      'Train With a Friend',
      'Users with friends work out 2x more! Add a friend to stay motivated.',
      'smart_nudge_social',
      '{"action": "add_friend"}'::jsonb,
      'pending'
    );
    v_nudges_created := v_nudges_created + 1;
  END LOOP;

  -- Nudge 2: Users with low completion rate - suggest shorter workouts
  FOR v_user IN
    SELECT wh.user_id, up.name,
           ROUND(AVG(wh.completion_rate) * 100) AS avg_completion_pct
    FROM workout_history wh
    JOIN user_profiles up ON up.id = wh.user_id
    WHERE wh.completion_rate IS NOT NULL
      AND wh.date::date >= (now() - INTERVAL '14 days')::date
      AND NOT EXISTS (
        SELECT 1 FROM push_notification_queue pnq
        WHERE pnq.recipient_user_id = wh.user_id
          AND pnq.notification_type = 'smart_nudge_completion'
          AND pnq.created_at > now() - INTERVAL '7 days'
      )
    GROUP BY wh.user_id, up.name
    HAVING AVG(wh.completion_rate) < 0.75 AND COUNT(*) >= 3
  LOOP
    INSERT INTO push_notification_queue (recipient_user_id, title, body, notification_type, data, status)
    VALUES (
      v_user.user_id,
      'Try a Quick Workout',
      'Your recent completion is ' || v_user.avg_completion_pct || '%. A shorter session might be the move!',
      'smart_nudge_completion',
      '{"action": "start_express_workout"}'::jsonb,
      'pending'
    );
    v_nudges_created := v_nudges_created + 1;
  END LOOP;

  -- Nudge 3: Users not in any challenge - encourage joining
  FOR v_user IN
    SELECT cpc.user_id, up.name
    FROM v_challenge_progress_correlation cpc
    JOIN user_profiles up ON up.id = cpc.user_id
    WHERE cpc.total_challenges = 0
      AND cpc.total_workouts >= 3
      AND NOT EXISTS (
        SELECT 1 FROM push_notification_queue pnq
        WHERE pnq.recipient_user_id = cpc.user_id
          AND pnq.notification_type = 'smart_nudge_challenge'
          AND pnq.created_at > now() - INTERVAL '14 days'
      )
  LOOP
    INSERT INTO push_notification_queue (recipient_user_id, title, body, notification_type, data, status)
    VALUES (
      v_user.user_id,
      'Challenge Yourself',
      'Challenge participants complete 40% more workouts. Start one today!',
      'smart_nudge_challenge',
      '{"action": "create_challenge"}'::jsonb,
      'pending'
    );
    v_nudges_created := v_nudges_created + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'nudges_created', v_nudges_created,
    'generated_at', now()
  );
END;
$$;

COMMENT ON FUNCTION generate_smart_nudges() IS
  'Generates targeted push notifications based on cross-table correlation data. '
  'Safe to call repeatedly -- deduplicates via 7/14-day cooldown windows.';

GRANT EXECUTE ON FUNCTION generate_smart_nudges() TO service_role;

DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE 'Created generate_smart_nudges() RPC function';
  RAISE NOTICE '   - Social nudge: no friends + inactive';
  RAISE NOTICE '   - Completion nudge: low completion rate';
  RAISE NOTICE '   - Challenge nudge: no challenges + active';
  RAISE NOTICE '';
  RAISE NOTICE '   Call via: SELECT generate_smart_nudges();';
END $$;
