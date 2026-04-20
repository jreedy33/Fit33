-- =============================================================================
-- Challenge Opponent Wake (silent push rate-limit + cron sweep)
-- =============================================================================
-- Supports the three-layer "background refresh" strategy: silent APNs pushes
-- (content-available: 1) that wake opponent devices so their HealthKit /
-- meal / hydration data is pushed to Supabase as close to realtime as iOS
-- allows — even when the opponent hasn't opened the app.
--
-- This migration provides:
--   1. silent_push_wake_log          — rate-limit table (15-min window per user)
--   2. prune_silent_push_wake_log    — daily prune of rows > 7 days old
--   3. trigger_challenge_opponent_wake() — pg_cron-invoked wrapper around the
--      `wake-challenge-opponents` edge function (every 30 min).
--
-- The heavy lifting (which opponents are stale, which device tokens to hit,
-- APNs call) lives in the `wake-challenge-opponents` edge function. This
-- migration is pure infra / scheduling glue.
--
-- ROLLBACK:
--   DROP TABLE IF EXISTS silent_push_wake_log CASCADE;
--   DROP FUNCTION IF EXISTS prune_silent_push_wake_log();
--   DROP FUNCTION IF EXISTS trigger_challenge_opponent_wake();
--   SELECT cron.unschedule('prune-silent-push-wake-log');
--   SELECT cron.unschedule('wake-stale-challenge-opponents');
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. silent_push_wake_log — one row per silent push sent. The edge function
--    checks for an existing row in the last 15 min before sending a new wake
--    to a given user_id. Combined with Apple's ~2-3/hr silent-push budget,
--    this keeps us safely under the ceiling regardless of how many challenges
--    the user is involved in.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS silent_push_wake_log (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    triggered_by TEXT NOT NULL CHECK (triggered_by IN ('foreground', 'cron', 'background_sync')),
    sent_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_silent_push_wake_log_user_sent
    ON silent_push_wake_log (user_id, sent_at DESC);

-- RLS: service-role only. Clients never read or write this table directly;
-- only the wake edge function (running with service role) touches it.
ALTER TABLE silent_push_wake_log ENABLE ROW LEVEL SECURITY;
-- (No policies defined → authenticated users get nothing, which is what we want.)

COMMENT ON TABLE silent_push_wake_log IS
    'Rate-limit log for silent APNs wake pushes. 15-min window per user_id.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. prune_silent_push_wake_log — delete rows older than 7 days. Scheduled
--    daily so the table never bloats (even a busy user gets < 400 rows/week).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION prune_silent_push_wake_log()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted INT;
BEGIN
    DELETE FROM silent_push_wake_log
    WHERE sent_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION prune_silent_push_wake_log() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION prune_silent_push_wake_log() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. trigger_challenge_opponent_wake — pg_cron entry point. Follows the
--    same internal_config pattern as process_push_notification_queue()
--    in supabase/20260324_push_notification_cron.sql. Invoked by cron
--    every 30 min; the edge function itself handles the per-recipient
--    15-min throttle + APNs call.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trigger_challenge_opponent_wake()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_anon TEXT;
BEGIN
    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'challenge_opponent_wake: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/wake-challenge-opponents',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_anon,
            'apikey',        v_anon,
            'x-cron-key',    v_key,
            'Content-Type',  'application/json'
        ),
        body    := '{"source": "cron"}'::jsonb
    );
END;
$$;

REVOKE ALL ON FUNCTION trigger_challenge_opponent_wake() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trigger_challenge_opponent_wake() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. pg_cron schedules
-- ─────────────────────────────────────────────────────────────────────────────

-- Remove old jobs if re-running migration (idempotent)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-silent-push-wake-log') THEN
        PERFORM cron.unschedule('prune-silent-push-wake-log');
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wake-stale-challenge-opponents') THEN
        PERFORM cron.unschedule('wake-stale-challenge-opponents');
    END IF;
END $$;

-- Daily prune at 03:10 UTC (off-peak)
SELECT cron.schedule(
    'prune-silent-push-wake-log',
    '10 3 * * *',
    $$SELECT prune_silent_push_wake_log()$$
);

-- Opponent wake sweep every 30 minutes. Edge function picks recipients and
-- applies per-user throttle.
SELECT cron.schedule(
    'wake-stale-challenge-opponents',
    '*/30 * * * *',
    $$SELECT trigger_challenge_opponent_wake()$$
);

DO $$ BEGIN
    RAISE NOTICE '✅ silent_push_wake_log created; cron jobs scheduled';
END $$;

COMMIT;
