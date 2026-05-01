-- =============================================================================
-- Smart Notification Engine — Phase 2: Per-User Engagement History
-- =============================================================================
-- Migration #170
-- Date: 2026-08-04
-- Authors: Data/Backend
-- Depends on: 20260801_notification_categories_and_caps.sql (#168)
--             20260802_notification_intents.sql (#169)
--
-- Purpose:
--
--   notification_engagement_history aggregates per-(user, category, hour-of-day)
--   open rates from push_notification_delivery_log so the orchestrator can
--   boost intents whose hour matches the user's historical pattern.
--   Cold-start users fall back to global tier defaults.
--
--   This is the "smart timing" learning signal — it answers
--   "for THIS user + THIS category, what hour gets the highest tap rate?"
--
-- Refresh strategy: rolling 30-day window; cron rolls up nightly.
-- Cheap to query (PK lookup); cheap to refresh (one INSERT-from-SELECT).
-- =============================================================================

BEGIN;

-- ── Table ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notification_engagement_history (
  user_id        UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  category       TEXT NOT NULL
                 CHECK (category IN ('rivalry','workout','recovery','nutrition','streak','social','announcement')),
  hour_of_day    SMALLINT NOT NULL CHECK (hour_of_day BETWEEN 0 AND 23),

  delivered_count INTEGER NOT NULL DEFAULT 0,
  opened_count    INTEGER NOT NULL DEFAULT 0,

  -- Derived: opened / delivered. NULL when delivered=0 (cold start).
  -- Stored so orchestrator can ORDER BY without a divide.
  open_rate      NUMERIC(5,4)
                 GENERATED ALWAYS AS (
                   CASE WHEN delivered_count > 0
                        THEN opened_count::NUMERIC / delivered_count::NUMERIC
                        ELSE NULL END
                 ) STORED,

  -- Window the rollup represents.
  window_start   TIMESTAMPTZ NOT NULL,
  window_end     TIMESTAMPTZ NOT NULL,
  refreshed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (user_id, category, hour_of_day)
);

CREATE INDEX IF NOT EXISTS idx_engagement_history_open_rate
  ON notification_engagement_history (category, hour_of_day, open_rate DESC NULLS LAST);

ALTER TABLE notification_engagement_history ENABLE ROW LEVEL SECURITY;

-- Service role only (orchestrator + rollup cron).
DROP POLICY IF EXISTS "service writes engagement history" ON notification_engagement_history;
CREATE POLICY "service writes engagement history"
  ON notification_engagement_history
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── Cross-user baseline view ────────────────────────────────────────────
--
-- Cold-start fallback: when a user has no history for a (category, hour),
-- the orchestrator looks up the cross-user mean open_rate for that
-- (category, hour) instead. View not table — refreshes lazily and the
-- aggregation cost is dominated by index scans.

CREATE OR REPLACE VIEW notification_engagement_baseline
WITH (security_invoker = on) AS
SELECT
  category,
  hour_of_day,
  SUM(delivered_count) AS delivered_count,
  SUM(opened_count)    AS opened_count,
  CASE WHEN SUM(delivered_count) > 0
       THEN SUM(opened_count)::NUMERIC / SUM(delivered_count)::NUMERIC
       ELSE NULL END AS open_rate
FROM notification_engagement_history
WHERE refreshed_at > NOW() - INTERVAL '14 days'
GROUP BY category, hour_of_day;

GRANT SELECT ON notification_engagement_baseline TO service_role;

-- ── Refresh function: rolling 30-day rollup ─────────────────────────────

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
  -- Compute fresh per-(user, category, hour) counts from delivery log.
  -- "delivered" = apns_success event. "opened" = opened event.
  -- hour_of_day is in UTC for v1; tz-localization is a Phase 5+ refinement.
  WITH events AS (
    SELECT
      user_id,
      COALESCE(category, (detail->>'category'), 'social') AS category,
      EXTRACT(HOUR FROM created_at)::SMALLINT AS hour_of_day,
      event,
      COUNT(*) AS event_count
    FROM push_notification_delivery_log
    WHERE created_at >= v_window_start
      AND created_at <  v_window_end
      AND event IN ('apns_success', 'opened')
      AND user_id IS NOT NULL
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

  -- Drop rows that haven't been touched in 60 days (user inactive). The
  -- table is per-user PK, so dead users hang around indefinitely otherwise.
  DELETE FROM notification_engagement_history
  WHERE refreshed_at < NOW() - INTERVAL '60 days';

  RETURN v_refreshed;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_notification_engagement_history() TO service_role;

-- ── Orchestrator helper RPC ─────────────────────────────────────────────
--
-- Returns the user's open_rate for a (category, hour_of_day), falling
-- back to the cross-user baseline when no per-user history exists.
-- Orchestrator multiplies this by `priority` to compute final score.

CREATE OR REPLACE FUNCTION get_engagement_score(
  p_user_id     UUID,
  p_category    TEXT,
  p_hour_of_day SMALLINT
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_rate     NUMERIC;
  v_user_delivered INTEGER;
  v_baseline_rate NUMERIC;
BEGIN
  -- Per-user rate (when delivered_count >= 5; otherwise too noisy).
  SELECT open_rate, delivered_count
  INTO v_user_rate, v_user_delivered
  FROM notification_engagement_history
  WHERE user_id = p_user_id
    AND category = p_category
    AND hour_of_day = p_hour_of_day;

  IF v_user_rate IS NOT NULL AND COALESCE(v_user_delivered, 0) >= 5 THEN
    RETURN v_user_rate;
  END IF;

  -- Fallback: cross-user baseline.
  SELECT open_rate INTO v_baseline_rate
  FROM notification_engagement_baseline
  WHERE category = p_category
    AND hour_of_day = p_hour_of_day;

  IF v_baseline_rate IS NOT NULL THEN
    RETURN v_baseline_rate;
  END IF;

  -- Cold-start universal default: 0.10 (modest, lets priority dominate).
  RETURN 0.10;
END;
$$;

GRANT EXECUTE ON FUNCTION get_engagement_score(UUID, TEXT, SMALLINT) TO service_role;

-- ── Cron: nightly rollup at 3:33 AM UTC ─────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-notification-engagement-history') THEN
    PERFORM cron.unschedule('refresh-notification-engagement-history');
  END IF;
END $$;

SELECT cron.schedule(
  'refresh-notification-engagement-history',
  '33 3 * * *',
  $$SELECT refresh_notification_engagement_history();$$
);

DO $$ BEGIN
  RAISE NOTICE '✅ Migration #170 (notification engagement history) complete';
  RAISE NOTICE '   - notification_engagement_history with generated open_rate column';
  RAISE NOTICE '   - notification_engagement_baseline view (cross-user fallback)';
  RAISE NOTICE '   - refresh_notification_engagement_history() RPC';
  RAISE NOTICE '   - get_engagement_score() RPC for orchestrator scoring';
  RAISE NOTICE '   - Nightly rollup scheduled at 3:33 AM UTC';
END $$;

COMMIT;
