-- =============================================================================
-- Push Notification Reliability Improvements
-- =============================================================================
-- 1. push_notification_delivery_log table for end-to-end tracking
-- 2. diagnose_push_notifications() RPC for in-app diagnostics
-- 3. Auto-prune old delivery logs via pg_cron (14-day retention)
-- =============================================================================

-- 1. Delivery Log Table
-- Tracks each step of the push notification pipeline for debugging.
-- Rows are lightweight; auto-pruned after 14 days.

CREATE TABLE IF NOT EXISTS push_notification_delivery_log (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  notification_id UUID REFERENCES push_notification_queue(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL,
  event           TEXT NOT NULL,  -- queued, claimed, prefs_ok, prefs_blocked, token_found, apns_sent, apns_success, apns_failed, deferred, recovered
  detail          JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_log_user_created
  ON push_notification_delivery_log (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_log_notification
  ON push_notification_delivery_log (notification_id);

CREATE INDEX IF NOT EXISTS idx_delivery_log_created
  ON push_notification_delivery_log (created_at);

ALTER TABLE push_notification_delivery_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own delivery logs" ON push_notification_delivery_log;
CREATE POLICY "Users can read own delivery logs"
  ON push_notification_delivery_log FOR SELECT
  USING (user_id = auth.uid());

-- Service role can insert (edge function writes logs)
DROP POLICY IF EXISTS "Service can insert delivery logs" ON push_notification_delivery_log;
CREATE POLICY "Service can insert delivery logs"
  ON push_notification_delivery_log FOR INSERT
  WITH CHECK (true);

-- 2. Diagnostic RPC
-- Returns a JSON report with token status, preferences, recent queue items,
-- and recent delivery log entries for the calling user.

CREATE OR REPLACE FUNCTION diagnose_push_notifications()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_tokens  JSONB;
  v_prefs   JSONB;
  v_queue   JSONB;
  v_logs    JSONB;
  v_stats   JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Token status
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'device_token_prefix', LEFT(device_token, 12),
    'apns_environment', apns_environment,
    'is_valid', is_valid,
    'platform', platform,
    'updated_at', updated_at
  ) ORDER BY updated_at DESC), '[]'::jsonb)
  INTO v_tokens
  FROM user_push_tokens
  WHERE user_id = v_user_id;

  -- Notification preferences
  SELECT jsonb_build_object(
    'master_enabled', COALESCE(master_enabled, true),
    'disabled_types', COALESCE(disabled_types, '{}'),
    'quiet_hours_enabled', COALESCE(quiet_hours_enabled, false),
    'quiet_hours_start', quiet_hours_start,
    'quiet_hours_end', quiet_hours_end,
    'timezone', timezone,
    'updated_at', updated_at
  )
  INTO v_prefs
  FROM user_notification_preferences
  WHERE user_id = v_user_id;

  IF v_prefs IS NULL THEN
    v_prefs := jsonb_build_object('status', 'no_preferences_row', 'master_enabled', true);
  END IF;

  -- Recent queue items (last 25)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'type', notification_type,
    'title', title,
    'status', status,
    'error_message', error_message,
    'retry_count', retry_count,
    'created_at', created_at,
    'sent_at', sent_at,
    'last_attempt_at', last_attempt_at,
    'next_retry_at', next_retry_at
  ) ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_queue
  FROM (
    SELECT * FROM push_notification_queue
    WHERE recipient_user_id = v_user_id
    ORDER BY created_at DESC
    LIMIT 25
  ) q;

  -- Recent delivery log entries (last 50)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'event', event,
    'detail', detail,
    'notification_id', notification_id,
    'created_at', created_at
  ) ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_logs
  FROM (
    SELECT * FROM push_notification_delivery_log
    WHERE user_id = v_user_id
    ORDER BY created_at DESC
    LIMIT 50
  ) l;

  -- Queue stats for this user
  SELECT jsonb_build_object(
    'total', COUNT(*),
    'pending', COUNT(*) FILTER (WHERE status = 'pending'),
    'processing', COUNT(*) FILTER (WHERE status = 'processing'),
    'sent', COUNT(*) FILTER (WHERE status = 'sent'),
    'failed', COUNT(*) FILTER (WHERE status = 'failed'),
    'sent_last_24h', COUNT(*) FILTER (WHERE status = 'sent' AND sent_at > NOW() - INTERVAL '24 hours'),
    'failed_last_24h', COUNT(*) FILTER (WHERE status = 'failed' AND last_attempt_at > NOW() - INTERVAL '24 hours')
  )
  INTO v_stats
  FROM push_notification_queue
  WHERE recipient_user_id = v_user_id;

  RETURN jsonb_build_object(
    'user_id', v_user_id,
    'diagnosed_at', NOW(),
    'tokens', v_tokens,
    'preferences', v_prefs,
    'queue_stats', v_stats,
    'recent_queue', v_queue,
    'recent_delivery_logs', v_logs
  );
END;
$$;

GRANT EXECUTE ON FUNCTION diagnose_push_notifications() TO authenticated;

-- 3. Auto-prune delivery logs older than 14 days (runs daily at 3 AM UTC)
CREATE OR REPLACE FUNCTION prune_push_delivery_logs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INT;
BEGIN
  DELETE FROM push_notification_delivery_log
  WHERE created_at < NOW() - INTERVAL '14 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  IF deleted_count > 0 THEN
    RAISE NOTICE 'Pruned % old push delivery log entries', deleted_count;
  END IF;
END;
$$;

-- Also prune old queue entries (sent/failed older than 30 days)
CREATE OR REPLACE FUNCTION prune_push_notification_queue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INT;
BEGIN
  DELETE FROM push_notification_queue
  WHERE status IN ('sent', 'failed')
    AND created_at < NOW() - INTERVAL '30 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;

  IF deleted_count > 0 THEN
    RAISE NOTICE 'Pruned % old push queue entries', deleted_count;
  END IF;
END;
$$;

-- Schedule daily prune jobs
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-push-delivery-logs') THEN
    PERFORM cron.unschedule('prune-push-delivery-logs');
  END IF;
END $$;

SELECT cron.schedule(
  'prune-push-delivery-logs',
  '0 3 * * *',
  $$SELECT prune_push_delivery_logs(); SELECT prune_push_notification_queue();$$
);

DO $$ BEGIN
  RAISE NOTICE '✅ Push notification reliability migration complete';
  RAISE NOTICE '   - push_notification_delivery_log table created';
  RAISE NOTICE '   - diagnose_push_notifications() RPC created';
  RAISE NOTICE '   - Daily log pruning scheduled (3 AM UTC)';
END $$;
