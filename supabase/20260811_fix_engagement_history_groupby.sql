-- =============================================================================
-- Smart Notification Engine — Hotfix: refresh_notification_engagement_history
--                                     GROUP BY column resolution bug
-- =============================================================================
-- Migration #177
-- Date: 2026-05-02
-- Author: Data/Backend
-- Depends on: 20260804_notification_engagement_history.sql (#170)
--
-- Bug discovered via cron failures (2026-05-02):
--
--   ERROR:  column "push_notification_delivery_log.detail" must appear in
--           the GROUP BY clause or be used in an aggregate function
--   QUERY:  WITH events AS (
--             SELECT user_id,
--                    COALESCE(category, (detail->>'category'), 'social') ...
--             GROUP BY user_id, category, hour_of_day, event
--
-- Root cause: GROUP BY listed `category` (the bare column) but SELECT
-- projected `COALESCE(category, (detail->>'category'), 'social')` — a
-- computed expression that also references `detail`. Postgres requires
-- every non-aggregated column to be in GROUP BY; `detail` was missing.
--
-- Fix: pre-compute the resolved category in an inner subquery so the
-- outer GROUP BY can reference a clean column name. This also makes
-- the rollup logic easier to read.
--
-- The function shape and signature are unchanged so the cron job and
-- any callers continue to work without any other touch-ups.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION refresh_notification_engagement_history()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_end   TIMESTAMPTZ := NOW();
  v_window_start TIMESTAMPTZ := v_window_end - INTERVAL '30 days';
  v_refreshed    INTEGER     := 0;
BEGIN
  -- Resolve `category` once in `resolved`, then group cleanly downstream.
  -- "delivered" = apns_success event. "opened" = opened event.
  -- hour_of_day is in UTC for v1; tz-localization is a Phase 5+ refinement.
  WITH resolved AS (
    SELECT
      user_id,
      COALESCE(category, (detail->>'category'), 'social') AS category,
      EXTRACT(HOUR FROM created_at)::SMALLINT AS hour_of_day,
      event
    FROM push_notification_delivery_log
    WHERE created_at >= v_window_start
      AND created_at <  v_window_end
      AND event IN ('apns_success', 'opened')
      AND user_id IS NOT NULL
  ),
  events AS (
    SELECT
      user_id,
      category,
      hour_of_day,
      event,
      COUNT(*) AS event_count
    FROM resolved
    GROUP BY user_id, category, hour_of_day, event
  ),
  pivoted AS (
    SELECT
      user_id,
      category,
      hour_of_day,
      SUM(event_count) FILTER (WHERE event = 'apns_success') AS delivered_count,
      SUM(event_count) FILTER (WHERE event = 'opened')       AS opened_count
    FROM events
    GROUP BY user_id, category, hour_of_day
  )
  INSERT INTO notification_engagement_history
    (user_id, category, hour_of_day, delivered_count, opened_count, window_start, window_end, refreshed_at)
  SELECT
    user_id, category, hour_of_day,
    COALESCE(delivered_count, 0),
    COALESCE(opened_count, 0),
    v_window_start, v_window_end, NOW()
  FROM pivoted
  ON CONFLICT (user_id, category, hour_of_day) DO UPDATE
    SET delivered_count = EXCLUDED.delivered_count,
        opened_count    = EXCLUDED.opened_count,
        window_start    = EXCLUDED.window_start,
        window_end      = EXCLUDED.window_end,
        refreshed_at    = EXCLUDED.refreshed_at;

  GET DIAGNOSTICS v_refreshed = ROW_COUNT;

  -- Drop rows that haven't been touched in 60 days (inactive users).
  DELETE FROM notification_engagement_history
  WHERE refreshed_at < NOW() - INTERVAL '60 days';

  RETURN v_refreshed;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_notification_engagement_history() TO service_role;

-- Smoke-test the fix immediately so the audit fails LOUD if syntax is still off.
DO $$
DECLARE v_count INTEGER;
BEGIN
  SELECT refresh_notification_engagement_history() INTO v_count;
  RAISE NOTICE '✅ Migration #177 (engagement history GROUP BY fix) complete';
  RAISE NOTICE '   - refresh_notification_engagement_history() returns: % rows', v_count;
END $$;

COMMIT;
