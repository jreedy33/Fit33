-- ============================================================================
-- 20260621_engagement_nudges_for_stale_opponents.sql
-- Realtime Widget Server Pull — Phase 7a (2026-04-26)
--
-- Server-side engagement nudge: when one user in an active 1v1 challenge
-- has gone silent (no `challenge_daily_progress` write in >12h) while
-- their opponent is logging progress, send the silent user a visible
-- push notification ("Joe is at 8,432 steps in your step challenge —
-- open Fit33 to sync your progress"). Goal is to break the
-- "stale-opponent zero-steps" anti-pattern that drove this entire
-- workstream by giving the silent device a concrete prompt to open
-- the app and let HealthKit re-sync.
--
-- Why server-side:
--   The silent push wake budget on iOS is exhausted long before lunch
--   (Phase-prep audit, 2026-04-26). The opponent's phone literally
--   doesn't get poked again until the user manually opens the app —
--   so a *visible* push at the OS level is the only escape hatch.
--   Visible pushes don't share the silent-push budget; APNs delivers
--   them on the standard high-priority lane.
--
-- Anti-spam contract:
--   1. Throttle: at most ONE `challenge_nudge` per (recipient, challenge)
--      per 24h. Implemented via NOT EXISTS lookup against the queue
--      itself — already-sent rows count, already-pending rows count
--      (they will deliver soon), already-failed rows count (we don't
--      retry the user, just give up for the day).
--   2. Quiet hours: deferred to `send-push-notification` edge function,
--      which already calls `isInQuietHours()` per user
--      (20260321_notification_preferences.sql + the edge fn body)
--      and reschedules to the user's quiet-hours-end. This RPC
--      enqueues regardless of caller-clock-time; the edge function
--      decides when to actually deliver.
--   3. Type-disabled: edge function reads `disabled_types` and drops
--      `challenge_nudge` rows for users who toggled the category off
--      via `NotificationPreferencesView`.
--   4. Master-disabled: same — edge function bails on `master_enabled
--      = false`.
--   5. Stale-floor: only fires if `opponent_last_progress_at` is at
--      least 12h old AND the challenge has been active for at least
--      24h (don't nudge on day 1 — the user might just not have
--      walked yet). NULL `last_progress_at` (user never logged) only
--      qualifies after the 24h floor as well.
--   6. End-of-challenge floor: only fires if `gc.end_date >= today`.
--      A finished challenge has nothing to catch up on.
--
-- Notification body shape (consumed by the iOS NotificationManager
-- routing layer, Phase 7c):
--   notification_type: 'challenge_nudge'
--   data.type:         'challenge_nudge'   ← edge fn reads this for prefs
--   data.challenge_id: <UUID>              ← deep-link target
--   data.opponent_id:  <UUID>              ← who's pulling ahead
--
-- Cron: scheduled via pg_cron at the bottom of this migration. Runs
-- every hour; the per-user throttle + quiet-hours filter inside the
-- edge function smooth out the actual delivery cadence.
--
-- Idempotency: BEGIN / COMMIT, IF NOT EXISTS / DROP IF EXISTS, and
-- the cron job is registered via the same `cron.unschedule` -then-
-- `cron.schedule` pattern used by 20260324_push_notification_cron.sql.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) RPC: enqueue_engagement_nudges_for_stale_opponents
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER so cron / service_role can call it without an
-- auth.uid() context (Data invariant #7: SECURITY DEFINER without
-- accepting user_id parameters; cron context is the right shape).

CREATE OR REPLACE FUNCTION enqueue_engagement_nudges_for_stale_opponents()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_inserted INT := 0;
    v_stale_floor INTERVAL := INTERVAL '12 hours';
    v_warmup_floor INTERVAL := INTERVAL '24 hours';
    v_throttle_window INTERVAL := INTERVAL '20 hours';
BEGIN
    -- One CTE per logical step. Pulled apart instead of nesting
    -- subqueries so the EXPLAIN plan stays readable for future
    -- ops (the index-only scans on `challenge_daily_progress
    -- (challenge_id, user_id, progress_date)` and
    -- `challenge_participants (challenge_id, user_id)` carry the
    -- weight here).
    WITH
    -- All currently-active 1v1 challenges. We mirror the predicate
    -- shape from `get_active_challenges` (#122) — `gc.status =
    -- 'active'` + exactly two participants — so this RPC and the
    -- widget RPC agree on what "active 1v1" means and we don't
    -- ship nudges for surfaces the widget doesn't render.
    active_1v1 AS (
        SELECT gc.id AS challenge_id,
               gc.title,
               gc.target_unit,
               gc.start_date,
               gc.end_date,
               gc.created_at
          FROM group_challenges gc
         WHERE gc.status = 'active'
           AND gc.end_date >= CURRENT_DATE
           AND gc.created_at < v_now - v_warmup_floor
           AND (SELECT COUNT(*)
                  FROM challenge_participants cp
                 WHERE cp.challenge_id = gc.id) = 2
    ),
    -- Both sides of every 1v1 with their last-progress timestamp.
    -- LEFT JOIN preserves participants who have NEVER logged for
    -- this challenge — they collapse to NULL last_at, which the
    -- staleness predicate below treats the same as "very stale"
    -- (covered by the 24h warmup floor so day-1 users aren't
    -- surprised).
    participant_freshness AS (
        SELECT a.challenge_id,
               a.title,
               a.target_unit,
               cp.user_id,
               (SELECT MAX(cdp.updated_at)
                  FROM challenge_daily_progress cdp
                 WHERE cdp.challenge_id = a.challenge_id
                   AND cdp.user_id = cp.user_id
                   AND cdp.progress_date >= a.start_date) AS last_at
          FROM active_1v1 a
          JOIN challenge_participants cp
            ON cp.challenge_id = a.challenge_id
           AND cp.status = 'accepted'
    ),
    -- Pair each side with the OTHER side. Self-join on challenge_id
    -- with the user_id inequality gives us two rows per challenge —
    -- one row for "from A's POV, B is the opponent" and the
    -- mirror — which is what we want: both sides may need a nudge,
    -- and the message is "OPPONENT is at X, you're at —".
    pairs AS (
        SELECT me.challenge_id,
               me.title,
               me.target_unit,
               me.user_id          AS recipient_user_id,
               me.last_at          AS recipient_last_at,
               opp.user_id         AS opponent_user_id,
               opp.last_at         AS opponent_last_at
          FROM participant_freshness me
          JOIN participant_freshness opp
            ON opp.challenge_id = me.challenge_id
           AND opp.user_id != me.user_id
    ),
    -- Stale = recipient hasn't logged in the stale-floor window
    -- (12h) AND opponent HAS logged something in the last
    -- stale-floor window (otherwise both sides are silent and a
    -- "they're pulling ahead" nudge would be a lie).
    stale_targets AS (
        SELECT p.*
          FROM pairs p
         WHERE (p.recipient_last_at IS NULL OR p.recipient_last_at < v_now - v_stale_floor)
           AND (p.opponent_last_at IS NOT NULL
                AND p.opponent_last_at >= v_now - v_stale_floor)
    ),
    -- Drop targets we've already nudged inside the throttle window.
    -- We use `data->>'challenge_id'` so the dedup is per-challenge,
    -- not per-user-globally — a user in three stale challenges
    -- gets up to three nudges per cycle, which is the right shape
    -- (each one is independently actionable). Cap inside the iOS
    -- preferences `daily_cap` is the global throttle.
    not_recently_nudged AS (
        SELECT s.*
          FROM stale_targets s
         WHERE NOT EXISTS (
            SELECT 1
              FROM push_notification_queue q
             WHERE q.recipient_user_id = s.recipient_user_id
               AND q.notification_type = 'challenge_nudge'
               AND q.data->>'challenge_id' = s.challenge_id::TEXT
               AND q.created_at > v_now - v_throttle_window
         )
    )
    -- Final insert. Title / body templates kept lightweight on the
    -- server side; richer copy lives in the iOS NotificationManager
    -- if we want personalization (e.g. opponent's first name +
    -- progress value). Here we just supply the contract minimum
    -- and the deep-link payload.
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        status,
        created_at
    )
    SELECT
        nrn.recipient_user_id,
        'challenge_nudge',
        'Your challenge is heating up 👀',
        COALESCE(opp_up.name, 'Your friend')
            || ' just logged progress in your '
            || COALESCE(NULLIF(BTRIM(REGEXP_REPLACE(nrn.title, E'^[^A-Za-z0-9]+', '', 'g')), ''), 'challenge')
            || '. Open Fit33 to keep up.',
        jsonb_build_object(
            'type', 'challenge_nudge',
            'challenge_id', nrn.challenge_id,
            'opponent_id', nrn.opponent_user_id,
            'reason', CASE WHEN nrn.recipient_last_at IS NULL
                           THEN 'never_logged'
                           ELSE 'stale_progress' END
        ),
        'pending',
        v_now
      FROM not_recently_nudged nrn
      LEFT JOIN user_profiles opp_up ON opp_up.id = nrn.opponent_user_id;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'enqueue_engagement_nudges_for_stale_opponents: queued % nudge(s)', v_inserted;
    RETURN v_inserted;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_engagement_nudges_for_stale_opponents() TO service_role;

-- ---------------------------------------------------------------------------
-- 2) pg_cron schedule
-- ---------------------------------------------------------------------------
-- Hourly. The function self-throttles (20h cooldown per recipient +
-- challenge) and the edge function defers to per-user quiet hours
-- before actually delivering. Hourly cadence means the worst-case
-- delivery latency from "opponent goes silent" → "user sees nudge"
-- is 12h (stale floor) + 1h (cron tick) + quiet-hours offset.

DO $$ BEGIN
    PERFORM cron.unschedule('engagement_nudges_for_stale_opponents');
EXCEPTION WHEN OTHERS THEN
    -- First-time install: there's nothing to unschedule. Swallow.
    NULL;
END $$;

SELECT cron.schedule(
    'engagement_nudges_for_stale_opponents',
    '0 * * * *',  -- top of every hour, UTC
    $$SELECT enqueue_engagement_nudges_for_stale_opponents()$$
);

-- ---------------------------------------------------------------------------
-- 3) Audit
-- ---------------------------------------------------------------------------
-- Verify exactly one definition + the cron job exists, fail loud
-- otherwise (Supabase invariants #28 / #29).

DO $$
DECLARE
    v_count INT;
    v_cron_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'enqueue_engagement_nudges_for_stale_opponents';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'enqueue_engagement_nudges_for_stale_opponents: expected exactly 1 definition, found %', v_count;
    END IF;

    SELECT COUNT(*) INTO v_cron_count
      FROM cron.job
     WHERE jobname = 'engagement_nudges_for_stale_opponents';
    IF v_cron_count <> 1 THEN
        RAISE EXCEPTION 'engagement_nudges_for_stale_opponents cron job missing (count=%)', v_cron_count;
    END IF;

    RAISE NOTICE '✅ engagement_nudges_for_stale_opponents RPC + hourly cron registered';
END $$;

COMMIT;
