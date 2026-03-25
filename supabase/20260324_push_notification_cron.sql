-- =============================================================================
-- Push Notification Queue Processor (pg_cron + pg_net)
-- =============================================================================
-- Ensures push_notification_queue rows are processed even when the iOS app
-- doesn't trigger the edge function directly. Runs every 30 seconds.
--
-- PREREQUISITE: After running this migration, insert your service role key:
--
--   INSERT INTO internal_config (key, value)
--   VALUES ('service_role_key', 'YOUR_SERVICE_ROLE_KEY')
--   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
--
-- =============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Config table for internal secrets (not exposed via RLS)
CREATE TABLE IF NOT EXISTS internal_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- No RLS policies = only service_role and SECURITY DEFINER functions can read
ALTER TABLE internal_config ENABLE ROW LEVEL SECURITY;

-- Seed the Supabase URL (known from project ref)
INSERT INTO internal_config (key, value)
VALUES ('supabase_url', 'https://ehooeghabzefgoqzugrc.supabase.co')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Function: check for pending notifications and invoke the edge function
-- Uses x-cron-key custom header because Supabase gateway mangles Authorization
CREATE OR REPLACE FUNCTION process_push_notification_queue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  pending_count INT;
  v_url   TEXT;
  v_key   TEXT;
  v_anon  TEXT;
BEGIN
  SELECT COUNT(*) INTO pending_count
  FROM push_notification_queue
  WHERE status = 'pending'
    AND (next_retry_at IS NULL OR next_retry_at <= NOW());

  IF pending_count = 0 THEN
    RETURN;
  END IF;

  SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
  SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
  SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

  IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
    RAISE WARNING 'push_notification_cron: internal_config missing required keys';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_anon,
      'apikey', v_anon,
      'x-cron-key', v_key,
      'Content-Type', 'application/json'
    ),
    body    := '{"batch": true}'::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION process_push_notification_queue() TO service_role;

-- Remove old job if re-running migration
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-push-notification-queue') THEN
    PERFORM cron.unschedule('process-push-notification-queue');
  END IF;
END $$;

-- Schedule: every 30 seconds
SELECT cron.schedule(
  'process-push-notification-queue',
  '30 seconds',
  $$SELECT process_push_notification_queue()$$
);

DO $$ BEGIN
  RAISE NOTICE '✅ Push notification queue cron job scheduled (every 30s)';
END $$;

-- =============================================================================
-- Test RPC: insert a test push notification targeting the calling user
-- =============================================================================
-- Used by PushNotificationDebugView to test the full pipeline end-to-end.

CREATE OR REPLACE FUNCTION insert_test_push_notification(
  p_notification_type TEXT,
  p_title TEXT,
  p_body TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_id UUID;
BEGIN
  INSERT INTO push_notification_queue (
    recipient_user_id,
    notification_type,
    title,
    body,
    data,
    status,
    created_at
  ) VALUES (
    auth.uid(),
    p_notification_type,
    p_title,
    p_body,
    jsonb_build_object('type', p_notification_type, 'test', true),
    'pending',
    NOW()
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_test_push_notification(TEXT, TEXT, TEXT) TO authenticated;

DO $$ BEGIN
  RAISE NOTICE '✅ insert_test_push_notification RPC created';
END $$;
