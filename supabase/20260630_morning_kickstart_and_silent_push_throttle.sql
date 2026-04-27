-- ============================================================================
-- 20260630_morning_kickstart_and_silent_push_throttle.sql
-- Widget Freshness Sprint — Phase 7e (2026-04-27)
--
-- Server-side fixes for the "users not pushing morning steps" diagnostic
-- finding from 2026-04-27. The Phase 7a-d work fully shipped, but field
-- diagnostics revealed:
--
--   1. The `wake-stale-challenge-opponents` cron was firing every 30 min
--      (~2/hr per active user). APNs silent-push budget is ~2-3/hr per
--      app. Combined with the new Phase 7b `progress_update` pushes,
--      we exceeded budget — Apple silently dropped the excess. Net
--      effect: 18 wakes fired overnight at Abbie + Manuel, ZERO
--      resulted in fresh challenge_daily_progress rows.
--
--   2. The cron is timezone-blind — fires at 03:30 ET, 04:30 ET, etc.
--      when phones are locked and users are asleep. Pure waste.
--
--   3. There's no "good morning, you have an active challenge" prompt
--      — users wake up, walk around, but never open the app for hours
--      (or until lunch). The existing engagement-nudge cron triggers
--      on a 12h staleness floor + 20h throttle, which means a user
--      who pushed yesterday at 9 PM wouldn't qualify for a nudge until
--      9 AM the next morning AT THE EARLIEST — and the cron only
--      runs hourly, so worst-case 10 AM. Plus the 20h throttle bars
--      same-challenge re-nudges for nearly a full day.
--
-- Three fixes:
--
--   A. **Slow the silent-push cron 30min → 60min.** Halves our APNs
--      consumption to fit Apple's per-app budget. Pushes that DO get
--      delivered will land more reliably because they're not racing
--      Apple's rate limiter.
--
--   B. **Add per-user time-of-day filter to the cron's recipient
--      resolution.** Skip silent pushes for users whose local time
--      (from `user_notification_preferences.timezone`) is between
--      23:00 and 06:00. Their phones are asleep, no walking is
--      happening, the wake is pure budget waste. Done in SQL via a
--      new helper that the edge function consumes (could be added
--      directly to wake-challenge-opponents in TS but the SQL filter
--      keeps the policy auditable + version-controlled).
--
--   C. **New `enqueue_morning_kickstart_nudges()` cron — VISIBLE push
--      at user's local 7:30 AM** (±15 min) when:
--        • user is in an active 1v1 / private / community challenge
--        • user has NOT pushed challenge_daily_progress today (in
--          their local TZ)
--        • user has not been morning-kickstarted today already
--        • user has push notifications enabled
--      Visible pushes have a SEPARATE budget from silent pushes, so
--      this doesn't cannibalize the silent-wake quota. Goes through
--      the existing send-push-notification edge function which already
--      handles quiet-hours + master_enabled + disabled_types preference
--      gating. Reuses the `challenge_nudge` notification_type
--      (already in iOS allowlist — QP invariant 9) with `data.kind =
--      'morning_kickstart'` so iOS can route + render with morning
--      copy if it wants to (today the iOS handler treats them
--      identically; richer copy is a follow-up).
--
-- IMPACT
--   • Stops APNs budget waste — Apple stops dropping our pushes.
--   • Stops nighttime silent pushes that wake nothing.
--   • Sends one polite "good morning" prod per active-challenge user
--     per day, timed to their local morning, when they're most likely
--     to actually open the app.
--   • Resulting first-of-day push from main app then triggers our
--     existing Phase 7b silent-push fan-out → opponents see fresh
--     numbers within 5-10 sec.
--
-- IDEMPOTENCY
--   BEGIN/COMMIT, IF NOT EXISTS / DROP IF EXISTS, cron unschedule-
--   then-schedule pattern. Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) Slow silent-push cron: 30min → 60min
-- ---------------------------------------------------------------------------

DO $cron$ BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wake-stale-challenge-opponents') THEN
        PERFORM cron.unschedule('wake-stale-challenge-opponents');
    END IF;
END $cron$;

-- Hourly. Edge function applies its own per-source throttle
-- (silent_push_wake_log: 15-min for cron, 60s for progress_update).
SELECT cron.schedule(
    'wake-stale-challenge-opponents',
    '0 * * * *',  -- top of every hour, was every 30 min
    $$SELECT trigger_challenge_opponent_wake()$$
);

-- ---------------------------------------------------------------------------
-- B) Time-of-day filter helper: is_user_in_waking_hours
-- ---------------------------------------------------------------------------
-- Used by the morning-kickstart cron AND callable from any future
-- silent-push cron that wants to skip locked-asleep phones.
--
-- "Waking hours" = 06:00–23:00 in the user's local timezone (from
-- user_notification_preferences.timezone, fallback 'UTC'). Returns
-- TRUE if user is in window OR has no timezone preference set.
--
-- Returns NULL → boolean by design; callers should `COALESCE(... ,
-- TRUE)` if they want a fail-open default.

CREATE OR REPLACE FUNCTION is_user_in_waking_hours(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        CASE
            WHEN unp.timezone IS NULL OR unp.timezone = '' THEN TRUE
            ELSE EXTRACT(HOUR FROM (NOW() AT TIME ZONE unp.timezone)) BETWEEN 6 AND 22
        END
    FROM user_notification_preferences unp
    WHERE unp.user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION is_user_in_waking_hours(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_user_in_waking_hours(UUID) TO service_role, authenticated;

-- ---------------------------------------------------------------------------
-- C) Morning kickstart nudge RPC + cron
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION enqueue_morning_kickstart_nudges()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ := NOW();
    v_inserted INT := 0;
BEGIN
    WITH
    -- All active step-typed challenge participants across 1v1, private,
    -- community. We deliberately INCLUDE every challenge type that
    -- the iOS step-counting layer cares about so users in any kind
    -- of step competition get a morning prod.
    active_step_users AS (
        -- 1v1 / group
        SELECT DISTINCT cp.user_id, gc.id AS challenge_id, gc.title, 'group'::TEXT AS surface
          FROM group_challenges gc
          JOIN challenge_participants cp ON cp.challenge_id = gc.id
         WHERE gc.status = 'active'
           AND gc.end_date >= CURRENT_DATE
           AND cp.status = 'accepted'
           AND (gc.challenge_type IN ('steps', 'walk', 'run', 'active_minutes')
                OR gc.target_unit IN ('steps'))
        UNION
        -- Private
        SELECT DISTINCT pcm.user_id, pc.id, pc.title, 'private'::TEXT
          FROM private_challenges pc
          JOIN private_challenge_members pcm ON pcm.challenge_id = pc.id
         WHERE (pc.end_date IS NULL OR pc.end_date >= CURRENT_DATE)
           AND (pc.challenge_type IN ('steps', 'walk', 'run', 'active_minutes')
                OR pc.target_unit IN ('steps'))
        UNION
        -- Community
        SELECT DISTINCT ccp.user_id, cc.id, cc.title, 'community'::TEXT
          FROM community_challenges cc
          JOIN community_challenge_participants ccp ON ccp.challenge_id = cc.id
         WHERE cc.status = 'active'
           AND (cc.end_date IS NULL OR cc.end_date >= CURRENT_DATE)
           AND (cc.challenge_type IN ('steps', 'walk', 'run', 'active_minutes')
                OR cc.target_unit IN ('steps'))
    ),
    -- Resolve each user's effective timezone. Layered fallback because
    -- `user_notification_preferences` is missing for many users (it's
    -- created lazily on first prefs-screen interaction):
    --   1. `user_notification_preferences.timezone` (canonical)
    --   2. Most recent `group_challenges.creator_timezone` from any
    --      of their active challenges (proxy — challengers tend to
    --      live in similar regions).
    --   3. 'America/New_York' (our user-base default).
    user_tz AS (
        SELECT asu.user_id,
               COALESCE(
                   NULLIF(unp.timezone, ''),
                   (SELECT NULLIF(gc2.creator_timezone, '')
                      FROM challenge_participants cp2
                      JOIN group_challenges gc2 ON gc2.id = cp2.challenge_id
                     WHERE cp2.user_id = asu.user_id
                       AND gc2.status = 'active'
                     ORDER BY gc2.created_at DESC
                     LIMIT 1),
                   'America/New_York'
               ) AS tz
          FROM (SELECT DISTINCT user_id FROM active_step_users) asu
          LEFT JOIN user_notification_preferences unp ON unp.user_id = asu.user_id
    ),
    -- For each user: are we in their local 7:00 AM – 11:00 AM window?
    -- 4-hour envelope so the cron can catch anyone who hasn't pushed
    -- by mid-morning regardless of timezone or when iOS gets around
    -- to firing pg_cron. Per-user 20h throttle (below) caps to one
    -- nudge per day, so widening the window doesn't cause spam.
    users_in_morning_window AS (
        SELECT asu.user_id, asu.challenge_id, asu.title, asu.surface,
               ut.tz
          FROM active_step_users asu
          JOIN user_tz ut ON ut.user_id = asu.user_id
         WHERE EXTRACT(HOUR FROM (v_now AT TIME ZONE ut.tz)) BETWEEN 7 AND 10
    ),
    -- Has the user pushed any progress today (in their local TZ)?
    -- If yes, they're already engaged; don't kickstart.
    not_yet_pushed_today AS (
        SELECT umw.*
          FROM users_in_morning_window umw
         WHERE NOT EXISTS (
            SELECT 1 FROM challenge_daily_progress cdp
             WHERE cdp.user_id = umw.user_id
               AND cdp.progress_date = (v_now AT TIME ZONE umw.tz)::DATE
         )
         AND NOT EXISTS (
            SELECT 1 FROM private_challenge_daily_progress pcdp
             WHERE pcdp.user_id = umw.user_id
               AND pcdp.progress_date = (v_now AT TIME ZONE umw.tz)::DATE
         )
         AND NOT EXISTS (
            SELECT 1 FROM community_challenge_daily_progress ccdp
             WHERE ccdp.user_id = umw.user_id
               AND ccdp.progress_date = (v_now AT TIME ZONE umw.tz)::DATE
         )
    ),
    -- Per-user dedup: max one morning kickstart per day, regardless
    -- of how many step challenges they're in. Their first push will
    -- fan out to ALL their active challenges via existing iOS code.
    not_already_kickstarted AS (
        SELECT DISTINCT ON (n.user_id) n.*
          FROM not_yet_pushed_today n
         WHERE NOT EXISTS (
            SELECT 1 FROM push_notification_queue q
             WHERE q.recipient_user_id = n.user_id
               AND q.notification_type = 'challenge_nudge'
               AND q.data->>'kind' = 'morning_kickstart'
               AND q.created_at > v_now - INTERVAL '20 hours'
         )
         ORDER BY n.user_id, n.title
    )
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
        nak.user_id,
        'challenge_nudge',
        'Good morning ☀️',
        'You''ve got an active challenge — open Fit33 to log your first steps.',
        jsonb_build_object(
            'type', 'challenge_nudge',
            'kind', 'morning_kickstart',
            'challenge_id', nak.challenge_id,
            'surface', nak.surface
        ),
        'pending',
        v_now
      FROM not_already_kickstarted nak;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RAISE NOTICE 'enqueue_morning_kickstart_nudges: queued % nudge(s)', v_inserted;
    RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION enqueue_morning_kickstart_nudges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enqueue_morning_kickstart_nudges() TO service_role;

-- ---------------------------------------------------------------------------
-- D) pg_cron schedule for the morning kickstart
-- ---------------------------------------------------------------------------
-- Every 15 minutes. The function self-windows on each user's local
-- 07:00–08:30 AM, so each user is eligible for ~6 ticks during their
-- morning. The 20-hour intra-day throttle guarantees only one nudge
-- per user per day. Hitting :15 / :30 / :45 / :00 means worst-case
-- delivery latency from "user enters morning window" → "nudge
-- queued" is 15 min.

DO $cron$ BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'morning_kickstart_nudges') THEN
        PERFORM cron.unschedule('morning_kickstart_nudges');
    END IF;
END $cron$;

SELECT cron.schedule(
    'morning_kickstart_nudges',
    '*/15 * * * *',  -- every 15 minutes
    $$SELECT enqueue_morning_kickstart_nudges()$$
);

-- ---------------------------------------------------------------------------
-- E) Audit
-- ---------------------------------------------------------------------------

DO $audit$
DECLARE
    v_count INT;
    v_cron_count INT;
    v_helper_count INT;
    v_silent_schedule TEXT;
BEGIN
    -- A) Silent-push cron is now hourly, not 30-min.
    SELECT schedule INTO v_silent_schedule FROM cron.job
     WHERE jobname = 'wake-stale-challenge-opponents';
    IF v_silent_schedule <> '0 * * * *' THEN
        RAISE EXCEPTION '[20260630] expected wake-stale-challenge-opponents schedule = ''0 * * * *'', got ''%''',
            COALESCE(v_silent_schedule, 'NULL');
    END IF;

    -- B) is_user_in_waking_hours helper exists.
    SELECT COUNT(*) INTO v_helper_count
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'is_user_in_waking_hours';
    IF v_helper_count <> 1 THEN
        RAISE EXCEPTION '[20260630] is_user_in_waking_hours helper missing (count=%)', v_helper_count;
    END IF;

    -- C) Morning kickstart RPC exists.
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'enqueue_morning_kickstart_nudges';
    IF v_count <> 1 THEN
        RAISE EXCEPTION '[20260630] enqueue_morning_kickstart_nudges missing (count=%)', v_count;
    END IF;

    -- D) Cron registered.
    SELECT COUNT(*) INTO v_cron_count FROM cron.job
     WHERE jobname = 'morning_kickstart_nudges';
    IF v_cron_count <> 1 THEN
        RAISE EXCEPTION '[20260630] morning_kickstart_nudges cron missing (count=%)', v_cron_count;
    END IF;

    RAISE NOTICE '✅ Phase 7e installed: silent-push cron 30min→60min + morning kickstart visible push';
END $audit$;

COMMIT;

-- ============================================================================
-- POST-DEPLOY VERIFICATION
--
-- 1. Confirm cron schedules:
--      SELECT jobname, schedule FROM cron.job
--       WHERE jobname IN ('wake-stale-challenge-opponents', 'morning_kickstart_nudges');
--    Expect: '0 * * * *' and '*/15 * * * *'.
--
-- 2. Trigger a test run immediately (don't wait for cron):
--      SELECT enqueue_morning_kickstart_nudges();
--    Returns count of inserted rows. Likely 0 unless you run it
--    between 7:00–8:30 AM in your test users' local timezones.
--
-- 3. Inspect queued nudges:
--      SELECT recipient_user_id, title, body, data, status, created_at
--      FROM push_notification_queue
--      WHERE notification_type = 'challenge_nudge'
--        AND data->>'kind' = 'morning_kickstart'
--      ORDER BY created_at DESC LIMIT 20;
--
-- 4. Watch the wake log thin out tonight — should see one row every
--    60 min instead of every 30 min:
--      SELECT triggered_by, COUNT(*), MIN(sent_at), MAX(sent_at)
--      FROM silent_push_wake_log
--      WHERE sent_at >= NOW() - INTERVAL '6 hours'
--      GROUP BY triggered_by;
--
-- ROLLBACK
--   To revert silent-push cron: re-apply 20260420_challenge_opponent_wake.sql
--   (it sets the */30 schedule).
--   To remove morning kickstart: drop the cron + function:
--     SELECT cron.unschedule('morning_kickstart_nudges');
--     DROP FUNCTION IF EXISTS enqueue_morning_kickstart_nudges();
--     DROP FUNCTION IF EXISTS is_user_in_waking_hours(UUID);
--   Safe — purely additive, doesn't touch progress data.
-- ============================================================================
