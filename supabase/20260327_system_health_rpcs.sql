-- ============================================================================
-- System Health RPCs (admin-only via service role)
-- ============================================================================
-- Provides table sizes, connection stats, index health, and RPC call stats
-- for the CMS System Health dashboard.
-- ============================================================================

-- 1. Table sizes + row estimates
CREATE OR REPLACE FUNCTION admin_get_table_sizes()
RETURNS TABLE(
  table_name TEXT,
  row_estimate BIGINT,
  total_bytes BIGINT,
  index_bytes BIGINT,
  toast_bytes BIGINT,
  table_bytes BIGINT
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    c.relname::TEXT AS table_name,
    c.reltuples::BIGINT AS row_estimate,
    pg_total_relation_size(c.oid)::BIGINT AS total_bytes,
    pg_indexes_size(c.oid)::BIGINT AS index_bytes,
    COALESCE(pg_total_relation_size(c.reltoastrelid), 0)::BIGINT AS toast_bytes,
    (pg_total_relation_size(c.oid) - pg_indexes_size(c.oid) - COALESCE(pg_total_relation_size(c.reltoastrelid), 0))::BIGINT AS table_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC;
$$;

-- 2. Connection pool stats
CREATE OR REPLACE FUNCTION admin_get_connection_stats()
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM pg_stat_activity),
    'active', (SELECT count(*) FROM pg_stat_activity WHERE state = 'active'),
    'idle', (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle'),
    'idle_in_transaction', (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction'),
    'waiting', (SELECT count(*) FROM pg_stat_activity WHERE wait_event IS NOT NULL AND state = 'active'),
    'max_connections', (SELECT setting::int FROM pg_settings WHERE name = 'max_connections'),
    'by_application', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object('app', application_name, 'count', cnt)), '[]')
      FROM (SELECT application_name, count(*) AS cnt FROM pg_stat_activity GROUP BY application_name ORDER BY cnt DESC LIMIT 10) t
    )
  );
$$;

-- 3. Index health: unused indexes + sequential scans
CREATE OR REPLACE FUNCTION admin_get_index_health()
RETURNS TABLE(
  table_name TEXT,
  index_name TEXT,
  index_size BIGINT,
  idx_scan BIGINT,
  idx_tup_read BIGINT,
  idx_tup_fetch BIGINT
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    schemaname || '.' || relname AS table_name,
    indexrelname AS index_name,
    pg_relation_size(indexrelid)::BIGINT AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
  FROM pg_stat_user_indexes
  WHERE schemaname = 'public'
  ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;
$$;

-- 4. RPC / function call stats
CREATE OR REPLACE FUNCTION admin_get_rpc_stats()
RETURNS TABLE(
  function_name TEXT,
  calls BIGINT,
  total_time_ms DOUBLE PRECISION,
  self_time_ms DOUBLE PRECISION,
  avg_time_ms DOUBLE PRECISION
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    funcname::TEXT AS function_name,
    calls,
    round(total_time::numeric, 2)::DOUBLE PRECISION AS total_time_ms,
    round(self_time::numeric, 2)::DOUBLE PRECISION AS self_time_ms,
    CASE WHEN calls > 0 THEN round((total_time / calls)::numeric, 2)::DOUBLE PRECISION ELSE 0 END AS avg_time_ms
  FROM pg_stat_user_functions
  WHERE schemaname = 'public'
  ORDER BY total_time DESC
  LIMIT 50;
$$;

-- 5. Push notification pipeline stats
CREATE OR REPLACE FUNCTION admin_get_push_pipeline_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_queue JSONB;
  v_delivery JSONB;
  v_hourly JSONB;
BEGIN
  SELECT jsonb_build_object(
    'total', count(*),
    'pending', count(*) FILTER (WHERE status = 'pending'),
    'processing', count(*) FILTER (WHERE status = 'processing'),
    'sent', count(*) FILTER (WHERE status = 'sent'),
    'failed', count(*) FILTER (WHERE status = 'failed'),
    'sent_24h', count(*) FILTER (WHERE status = 'sent' AND sent_at > NOW() - INTERVAL '24 hours'),
    'failed_24h', count(*) FILTER (WHERE status = 'failed' AND last_attempt_at > NOW() - INTERVAL '24 hours'),
    'oldest_pending', MIN(created_at) FILTER (WHERE status = 'pending')
  ) INTO v_queue
  FROM push_notification_queue;

  SELECT COALESCE(jsonb_build_object(
    'total_events', count(*),
    'apns_success', count(*) FILTER (WHERE event = 'apns_success'),
    'apns_failed', count(*) FILTER (WHERE event = 'apns_failed'),
    'prefs_blocked', count(*) FILTER (WHERE event = 'prefs_blocked'),
    'token_found', count(*) FILTER (WHERE event = 'token_found')
  ), '{}') INTO v_delivery
  FROM push_notification_delivery_log
  WHERE created_at > NOW() - INTERVAL '24 hours';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'hour', h, 'sent', sent_count, 'failed', failed_count
  ) ORDER BY h), '[]') INTO v_hourly
  FROM (
    SELECT
      date_trunc('hour', created_at) AS h,
      count(*) FILTER (WHERE event = 'apns_success') AS sent_count,
      count(*) FILTER (WHERE event = 'apns_failed') AS failed_count
    FROM push_notification_delivery_log
    WHERE created_at > NOW() - INTERVAL '24 hours'
    GROUP BY date_trunc('hour', created_at)
  ) t;

  RETURN jsonb_build_object(
    'queue', v_queue,
    'delivery_24h', v_delivery,
    'hourly_trend', v_hourly
  );
END;
$$;

DO $$ BEGIN
  RAISE NOTICE 'System health RPCs created (table sizes, connections, indexes, RPC stats, push pipeline)';
END $$;
