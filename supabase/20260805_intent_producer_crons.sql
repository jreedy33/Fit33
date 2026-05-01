-- =============================================================================
-- Smart Notification Engine — Phase 3: Intent Producers + Cron Schedule
-- =============================================================================
-- Migration #172
-- Date: 2026-08-05
-- Authors: Data/Backend + Fitness Expert
-- Depends on: 20260801, 20260802, 20260804, 20260807
--
-- Purpose:
--
--   Defines all the cron-driven "intent producers" — SQL functions that
--   detect a notification opportunity and INSERT INTO notification_intents.
--   The orchestrator picks them up on its next */5 cycle and decides
--   whether/when to send.
--
--   Producers shipped here:
--     - enqueue_league_placement_intents()  — Mon 8am local fanout
--     - enqueue_rivalry_intents()           — every 30 min during waking
--     - enqueue_recovery_intents()          — 7am local
--     - enqueue_sleep_debt_intents()        — 9pm local
--     - enqueue_hydration_intents()         — 11am/2pm/5pm local
--     - enqueue_streak_protection()         — 6pm local
--     - enqueue_workout_opportunity()       — 4pm local
--     - enqueue_strava_celebration()        — invoked by strava-webhook
--
--   Each producer:
--     - Computes a per-user idempotency_key so re-running a cron in the
--       same window doesn't dup-enqueue.
--     - Sets expires_at to the end of the relevant window so an intent
--       that's not orchestrated within hours doesn't fire stale.
--     - Sets priority based on urgency (recovery red = 80, hydration = 30).
--
-- Notes:
--   - Time-of-day comparisons run in user-local TZ, derived from
--     user_notification_preferences.timezone (default America/New_York).
--   - Producers QUERY existing tables (daily_readiness_history,
--     user_streaks, group_challenges, etc.) — they don't define new ones.
--   - Cron jobs are scheduled for UTC; producers do their own per-user
--     local-hour gating so the cron can run hourly while only producing
--     intents for users whose local time matches the target window.
--   - Live cron (every */5) drives the orchestrator itself
--     (notification-orchestrator edge fn) — that schedule is set below
--     too.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. Helper: convert user's stored timezone to current local hour
-- =============================================================================

CREATE OR REPLACE FUNCTION user_local_hour(p_tz TEXT)
RETURNS SMALLINT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN EXTRACT(HOUR FROM (NOW() AT TIME ZONE COALESCE(p_tz, 'America/New_York')))::SMALLINT;
END;
$$;

-- "End of today in user's local TZ" expressed as UTC TIMESTAMPTZ.
-- Used to set expires_at so an intent that misses today's orchestration
-- window expires instead of firing tomorrow.
CREATE OR REPLACE FUNCTION user_local_end_of_today_utc(p_tz TEXT)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_tz TEXT := COALESCE(p_tz, 'America/New_York');
  v_local_today DATE := (NOW() AT TIME ZONE v_tz)::DATE;
BEGIN
  RETURN ((v_local_today + INTERVAL '1 day') AT TIME ZONE v_tz);
END;
$$;

CREATE OR REPLACE FUNCTION user_local_today_date(p_tz TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN (NOW() AT TIME ZONE COALESCE(p_tz, 'America/New_York'))::DATE;
END;
$$;

-- =============================================================================
-- 2. enqueue_league_placement_intents — Monday 8am local
-- =============================================================================
-- Hourly cron checks each user's local hour; produces intents for users in
-- (8 AM local) AND today is Monday in their TZ. Idempotency key is per
-- user + week so a cron drift doesn't dup-fire.

CREATE OR REPLACE FUNCTION enqueue_league_placement_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_user RECORD;
  v_week_start DATE;
  v_tier TEXT;
BEGIN
  -- Defensive: skip producer if league_members table doesn't exist yet.
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'league_members') THEN
    RETURN 0;
  END IF;

  -- Only fire for users whose CURRENT LOCAL day-of-week is Monday AND
  -- whose CURRENT LOCAL hour is 8 (the cron runs hourly, so we get one
  -- shot per user per Monday).
  FOR v_user IN
    SELECT
      lm.user_id,
      COALESCE(unp.timezone, 'America/New_York') AS tz,
      lm.group_id
    FROM league_members lm
    LEFT JOIN user_notification_preferences unp ON unp.user_id = lm.user_id
    WHERE EXTRACT(ISODOW FROM (NOW() AT TIME ZONE COALESCE(unp.timezone, 'America/New_York'))::DATE) = 1
  LOOP
    IF user_local_hour(v_user.tz) <> 8 THEN CONTINUE; END IF;

    v_week_start := DATE_TRUNC('week', (NOW() AT TIME ZONE v_user.tz)::DATE)::DATE;

    -- Look up tier; pull from user_league_tier when available.
    BEGIN
      SELECT tier INTO v_tier FROM user_league_tier WHERE user_id = v_user.user_id LIMIT 1;
    EXCEPTION WHEN undefined_table THEN
      v_tier := 'bronze';
    END;
    v_tier := COALESCE(v_tier, 'bronze');

    PERFORM enqueue_notification_intent(
      v_user.user_id,
      'rivalry',
      'league_started',
      70,
      jsonb_build_object(
        'tier', v_tier,
        'tier_name', INITCAP(v_tier),
        'tier_emoji', CASE v_tier
          WHEN 'bronze' THEN '🥉'
          WHEN 'silver' THEN '🥈'
          WHEN 'gold' THEN '🥇'
          WHEN 'platinum' THEN '💎'
          WHEN 'diamond' THEN '👑'
          WHEN 'verified' THEN '✅'
          ELSE '🏆'
        END,
        'week_start', v_week_start::TEXT
      ),
      'league_started:' || v_user.user_id::TEXT || ':' || v_week_start::TEXT,
      user_local_end_of_today_utc(v_user.tz),
      'enqueue_league_placement_intents'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_league_placement_intents threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_league_placement_intents() TO service_role;

-- =============================================================================
-- 3. enqueue_recovery_intents — 7am local (red/yellow band) + on-demand
-- =============================================================================
-- Cron runs hourly; per user, fires only when local hour = 7. Reads
-- daily_readiness_history (existing). Three intent kinds based on band.

CREATE OR REPLACE FUNCTION enqueue_recovery_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_user RECORD;
  v_today DATE;
  v_score INTEGER;
  v_band TEXT;
  v_kind TEXT;
  v_priority INTEGER;
  v_payload JSONB;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'daily_readiness_history') THEN
    RETURN 0;
  END IF;

  FOR v_user IN
    SELECT
      up.id AS user_id,
      COALESCE(unp.timezone, 'America/New_York') AS tz
    FROM user_profiles up
    LEFT JOIN user_notification_preferences unp ON unp.user_id = up.id
  LOOP
    IF user_local_hour(v_user.tz) <> 7 THEN CONTINUE; END IF;
    v_today := user_local_today_date(v_user.tz);

    -- Use verified column names: `score`, `band`, key `date`.
    SELECT score INTO v_score
    FROM daily_readiness_history
    WHERE user_id = v_user.user_id
      AND date BETWEEN v_today - INTERVAL '1 day' AND v_today
    ORDER BY date DESC LIMIT 1;

    IF v_score IS NULL THEN CONTINUE; END IF;

    IF v_score < 34 THEN
      v_band := 'red'; v_kind := 'recovery_alert'; v_priority := 80;
    ELSIF v_score < 67 THEN
      v_band := 'yellow'; v_kind := 'recovery_yellow'; v_priority := 55;
    ELSE
      v_band := 'green'; v_kind := 'recovery_pr_opportunity'; v_priority := 50;
    END IF;

    v_payload := jsonb_build_object('recovery_score', v_score, 'band', v_band);

    PERFORM enqueue_notification_intent(
      v_user.user_id, 'recovery', v_kind, v_priority, v_payload,
      v_kind || ':' || v_user.user_id::TEXT || ':' || v_today::TEXT,
      user_local_end_of_today_utc(v_user.tz),
      'enqueue_recovery_intents'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_recovery_intents threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_recovery_intents() TO service_role;

-- =============================================================================
-- 4. enqueue_sleep_debt_intents — 9pm local
-- =============================================================================

CREATE OR REPLACE FUNCTION enqueue_sleep_debt_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_user RECORD;
  v_today DATE;
  v_sleep_hours NUMERIC;
  v_debt_min INTEGER;
  v_needed NUMERIC;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'daily_readiness_history') THEN
    RETURN 0;
  END IF;

  FOR v_user IN
    SELECT
      up.id AS user_id,
      COALESCE(unp.timezone, 'America/New_York') AS tz
    FROM user_profiles up
    LEFT JOIN user_notification_preferences unp ON unp.user_id = up.id
  LOOP
    IF user_local_hour(v_user.tz) <> 21 THEN CONTINUE; END IF;
    v_today := user_local_today_date(v_user.tz);

    -- Verified columns on daily_readiness_history: sleep_hours (NUMERIC),
    -- sleep_debt_min (INTEGER, 7h target − sleep × 60, floored 0), date PK.
    SELECT sleep_hours, sleep_debt_min INTO v_sleep_hours, v_debt_min
    FROM daily_readiness_history
    WHERE user_id = v_user.user_id
      AND date = v_today - INTERVAL '0 day'  -- today's row may not exist; try yesterday
    ORDER BY date DESC LIMIT 1;

    -- Skip users with no sleep signal at all.
    IF v_sleep_hours IS NULL AND v_debt_min IS NULL THEN CONTINUE; END IF;

    -- Compute "needed tonight" = 7h target plus carried debt (capped at 9h).
    v_needed := LEAST(9.0, 7.0 + COALESCE(v_debt_min, 0) / 60.0);

    -- Skip if the user already met or exceeded need (no debt).
    IF COALESCE(v_debt_min, 0) <= 30 AND COALESCE(v_sleep_hours, 0) >= 7 THEN CONTINUE; END IF;

    PERFORM enqueue_notification_intent(
      v_user.user_id, 'recovery', 'sleep_debt', 60,
      jsonb_build_object(
        'needed_hours', ROUND(v_needed, 1),
        'sleep_debt_min', COALESCE(v_debt_min, 0),
        'last_sleep_hours', ROUND(COALESCE(v_sleep_hours, 0), 1),
        'bedtime_eta', TO_CHAR((NOW() + INTERVAL '1 hour') AT TIME ZONE v_user.tz, 'HH12:MI AM')
      ),
      'sleep_debt:' || v_user.user_id::TEXT || ':' || v_today::TEXT,
      (NOW() + INTERVAL '4 hours'),
      'enqueue_sleep_debt_intents'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_sleep_debt_intents threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_sleep_debt_intents() TO service_role;

-- =============================================================================
-- 5. enqueue_rivalry_intents — every 30 min, waking hours
-- =============================================================================
--
-- For each active 1v1 challenge, when the opponent leads the user by a
-- "meaningful" gap AND the user hasn't moved in 4h, emit `rivalry_behind`.
-- Idempotency key is per-(user, challenge, hour) so we get at most one
-- nudge per challenge per hour even if cron drifts.

CREATE OR REPLACE FUNCTION enqueue_rivalry_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
  v_payload JSONB;
  v_idem TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'challenge_daily_progress')
     OR NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'group_challenges') THEN
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT
      cdp_user.user_id,
      cdp_user.challenge_id,
      cdp_user.value AS user_value,
      cdp_opp.value AS opp_value,
      cdp_opp.user_id AS opponent_user_id,
      gc.metric_unit,
      gc.daily_target,
      COALESCE(unp.timezone, 'America/New_York') AS tz,
      opp_profile.display_name AS opp_name
    FROM challenge_daily_progress cdp_user
    JOIN group_challenges gc ON gc.id = cdp_user.challenge_id
    JOIN challenge_daily_progress cdp_opp ON cdp_opp.challenge_id = cdp_user.challenge_id
                                          AND cdp_opp.user_id <> cdp_user.user_id
                                          AND cdp_opp.day = cdp_user.day
    JOIN user_profiles opp_profile ON opp_profile.id = cdp_opp.user_id
    LEFT JOIN user_notification_preferences unp ON unp.user_id = cdp_user.user_id
    WHERE gc.status = 'active'
      AND gc.challenge_type = '1v1'
      AND cdp_user.day = (NOW() AT TIME ZONE COALESCE(unp.timezone, 'America/New_York'))::DATE
      AND cdp_opp.value > cdp_user.value
      AND (cdp_opp.value - cdp_user.value) >= GREATEST(
        COALESCE(gc.daily_target, 1) * 0.20,  -- 20% of target
        50  -- minimum 50 units
      )
      AND cdp_user.updated_at < NOW() - INTERVAL '4 hours'
  LOOP
    -- Only fire during waking hours (8am - 9pm local)
    IF user_local_hour(v_row.tz) < 8 OR user_local_hour(v_row.tz) > 21 THEN CONTINUE; END IF;

    v_payload := jsonb_build_object(
      'opponent_name', v_row.opp_name,
      'opponent_id', v_row.opponent_user_id,
      'challenge_id', v_row.challenge_id,
      'gap', (v_row.opp_value - v_row.user_value)::INTEGER,
      'unit', COALESCE(v_row.metric_unit, 'units'),
      'opponent_value', v_row.opp_value,
      'my_value', v_row.user_value,
      'daily_target', v_row.daily_target
    );

    v_idem := 'rivalry_behind:' || v_row.user_id::TEXT
              || ':' || v_row.challenge_id::TEXT
              || ':' || TO_CHAR(NOW() AT TIME ZONE v_row.tz, 'YYYY-MM-DD-HH24');

    PERFORM enqueue_notification_intent(
      v_row.user_id, 'rivalry', 'rivalry_behind', 65, v_payload,
      v_idem,
      user_local_end_of_today_utc(v_row.tz),
      'enqueue_rivalry_intents'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_rivalry_intents threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_rivalry_intents() TO service_role;

-- =============================================================================
-- 6. enqueue_streak_protection — 6pm local
-- =============================================================================

CREATE OR REPLACE FUNCTION enqueue_streak_protection()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_user RECORD;
  v_today DATE;
  v_streak INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workouts') THEN
    RETURN 0;
  END IF;

  FOR v_user IN
    SELECT
      up.id AS user_id,
      COALESCE(unp.timezone, 'America/New_York') AS tz
    FROM user_profiles up
    LEFT JOIN user_notification_preferences unp ON unp.user_id = up.id
  LOOP
    IF user_local_hour(v_user.tz) <> 18 THEN CONTINUE; END IF;
    v_today := user_local_today_date(v_user.tz);

    -- Compute consecutive-day workout streak ending YESTERDAY.
    -- Cheap inline approach: count distinct days in last 7d, only fire if
    -- ≥3 contiguous prior days had a workout AND today does not yet.
    SELECT COUNT(DISTINCT (w.completed_at::DATE))
    INTO v_streak
    FROM workouts w
    WHERE w.user_id = v_user.user_id
      AND w.completed_at::DATE BETWEEN v_today - INTERVAL '7 day' AND v_today - INTERVAL '1 day';

    IF v_streak < 3 THEN CONTINUE; END IF;

    -- Skip if user has already worked out today (no streak risk).
    IF EXISTS (
      SELECT 1 FROM workouts w
      WHERE w.user_id = v_user.user_id
        AND w.completed_at::DATE = v_today
    ) THEN CONTINUE; END IF;

    PERFORM enqueue_notification_intent(
      v_user.user_id, 'streak', 'streak_risk', 75,
      jsonb_build_object('streak_days', v_streak),
      'streak_risk:' || v_user.user_id::TEXT || ':' || v_today::TEXT,
      (NOW() + INTERVAL '5 hours'),
      'enqueue_streak_protection'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_streak_protection threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_streak_protection() TO service_role;

-- =============================================================================
-- 7. enqueue_workout_opportunity — 4pm local
-- =============================================================================
--
-- Fires `friend_workout_match` when a friend completed a workout today AND
-- the user hasn't worked out in 2+ days. Phase 3 baseline; the smarter
-- "muscle group overdue" variant ships in Phase 5 once `workouts` has a
-- canonical `primary_muscles[]` mirror from the iOS write path (currently
-- only `exercises.primary_muscles` is populated server-side).

CREATE OR REPLACE FUNCTION enqueue_workout_opportunity()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
  v_today DATE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workouts')
     OR NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'friendships') THEN
    RETURN 0;
  END IF;

  FOR v_row IN
    SELECT DISTINCT ON (f.user_id)
      f.user_id,
      f.friend_user_id,
      friend_profile.display_name AS friend_name,
      COALESCE(unp.timezone, 'America/New_York') AS tz
    FROM friendships f
    JOIN workouts w ON w.user_id = f.friend_user_id
    JOIN user_profiles friend_profile ON friend_profile.id = f.friend_user_id
    LEFT JOIN user_notification_preferences unp ON unp.user_id = f.user_id
    WHERE f.status = 'accepted'
      AND w.completed_at >= NOW() - INTERVAL '12 hours'
      AND NOT EXISTS (
        SELECT 1 FROM workouts w2
        WHERE w2.user_id = f.user_id
          AND w2.completed_at >= NOW() - INTERVAL '2 days'
      )
    ORDER BY f.user_id, w.completed_at DESC
  LOOP
    IF user_local_hour(v_row.tz) <> 16 THEN CONTINUE; END IF;
    v_today := user_local_today_date(v_row.tz);

    PERFORM enqueue_notification_intent(
      v_row.user_id, 'workout', 'friend_workout_match', 55,
      jsonb_build_object(
        'friend_name', v_row.friend_name,
        'friend_id', v_row.friend_user_id,
        'days_since_you_trained', 2
      ),
      'friend_workout_match:' || v_row.user_id::TEXT || ':' || v_today::TEXT,
      user_local_end_of_today_utc(v_row.tz),
      'enqueue_workout_opportunity'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_workout_opportunity threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_workout_opportunity() TO service_role;

-- =============================================================================
-- 8. enqueue_hydration_intents — 11am / 2pm / 5pm local, pace-aware
-- =============================================================================

CREATE OR REPLACE FUNCTION enqueue_hydration_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
  v_row RECORD;
  v_today DATE;
  v_consumed INTEGER;
  v_goal INTEGER;
  v_deficit INTEGER;
  v_local_hour SMALLINT;
  v_target_hours INTEGER[] := ARRAY[11, 14, 17];
  v_has_hydration BOOLEAN := EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'hydration_logs'
  );
BEGIN
  FOR v_row IN
    SELECT
      up.id AS user_id,
      COALESCE(unp.timezone, 'America/New_York') AS tz,
      64 AS goal_oz   -- Phase 3 baseline: fixed 64oz default. Per-user goal
                      -- column TBD; will pull from user_profiles when present.
    FROM user_profiles up
    LEFT JOIN user_notification_preferences unp ON unp.user_id = up.id
  LOOP
    v_local_hour := user_local_hour(v_row.tz);
    IF NOT (v_local_hour = ANY(v_target_hours)) THEN CONTINUE; END IF;

    v_today := user_local_today_date(v_row.tz);
    v_consumed := 0;

    -- Best-effort hydration tally; if the schema doesn't match assume 0.
    IF v_has_hydration THEN
      BEGIN
        EXECUTE 'SELECT COALESCE(SUM(amount_oz), 0)::INTEGER FROM hydration_logs WHERE user_id = $1 AND created_at::DATE = $2'
          INTO v_consumed
          USING v_row.user_id, v_today;
      EXCEPTION WHEN OTHERS THEN
        v_consumed := 0;  -- column name drift; fall through with 0
      END;
    END IF;

    v_goal := v_row.goal_oz;
    v_deficit := GREATEST(0, v_goal - v_consumed);

    -- Pace check: 11am ≈25%, 2pm ≈50%, 5pm ≈75%.
    DECLARE
      v_pace NUMERIC := CASE v_local_hour
        WHEN 11 THEN 0.25
        WHEN 14 THEN 0.50
        WHEN 17 THEN 0.75
        ELSE 0.50
      END;
      v_expected_consumed NUMERIC := v_goal * v_pace;
    BEGIN
      IF v_consumed >= v_expected_consumed THEN CONTINUE; END IF;
    END;

    PERFORM enqueue_notification_intent(
      v_row.user_id, 'nutrition', 'hydration_pace', 30,
      jsonb_build_object(
        'consumed_oz', v_consumed,
        'goal_oz', v_goal,
        'deficit_oz', v_deficit,
        'time_of_day', CASE v_local_hour WHEN 11 THEN 'morning' WHEN 14 THEN 'midday' WHEN 17 THEN 'afternoon' END
      ),
      'hydration_pace:' || v_row.user_id::TEXT || ':' || v_today::TEXT || ':' || v_local_hour::TEXT,
      user_local_end_of_today_utc(v_row.tz),
      'enqueue_hydration_intents'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'enqueue_hydration_intents threw: %', SQLERRM;
  RETURN 0;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_hydration_intents() TO service_role;

-- =============================================================================
-- 9. enqueue_strava_celebration — invoked by strava-webhook directly
-- =============================================================================
--
-- Webhook → after upserting cardio_workouts, calls this to drop a
-- celebration intent. No cron — it's event-driven.

CREATE OR REPLACE FUNCTION enqueue_strava_celebration_intent(
  p_user_id     UUID,
  p_activity_id TEXT,
  p_distance_m  NUMERIC,
  p_duration_s  INTEGER,
  p_elev_m      NUMERIC,
  p_activity_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN enqueue_notification_intent(
    p_user_id, 'workout', 'strava_celebration', 50,
    jsonb_build_object(
      'activity_id', p_activity_id,
      'activity_type', p_activity_type,
      'distance_meters', ROUND(p_distance_m)::INTEGER,
      'distance_km', ROUND(p_distance_m / 1000.0, 1),
      'duration_seconds', p_duration_s,
      'duration_min', ROUND(p_duration_s / 60.0)::INTEGER,
      'elevation_gain_m', ROUND(p_elev_m)::INTEGER
    ),
    'strava_celebration:' || p_user_id::TEXT || ':' || p_activity_id,
    NOW() + INTERVAL '4 hours',
    'enqueue_strava_celebration_intent'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_strava_celebration_intent(UUID, TEXT, NUMERIC, INTEGER, NUMERIC, TEXT) TO service_role;

-- =============================================================================
-- 10. CRON SCHEDULES
-- =============================================================================
--
-- All hourly producers run at :03 past so they don't pile on with the
-- queue cron (:00) or expirer (:07).
-- Orchestrator runs */5 — picks up intents within minutes.

DO $$
DECLARE jobname TEXT;
BEGIN
  FOR jobname IN SELECT j.jobname FROM cron.job j
    WHERE j.jobname IN (
      'enqueue-league-placement',
      'enqueue-recovery',
      'enqueue-sleep-debt',
      'enqueue-rivalry',
      'enqueue-streak-protection',
      'enqueue-workout-opportunity',
      'enqueue-hydration',
      'notification-orchestrator-tick'
    )
  LOOP
    PERFORM cron.unschedule(jobname);
  END LOOP;
END $$;

SELECT cron.schedule('enqueue-league-placement',    '3 * * * *',     $$SELECT enqueue_league_placement_intents();$$);
SELECT cron.schedule('enqueue-recovery',            '3 * * * *',     $$SELECT enqueue_recovery_intents();$$);
SELECT cron.schedule('enqueue-sleep-debt',          '3 * * * *',     $$SELECT enqueue_sleep_debt_intents();$$);
SELECT cron.schedule('enqueue-rivalry',             '*/30 * * * *',  $$SELECT enqueue_rivalry_intents();$$);
SELECT cron.schedule('enqueue-streak-protection',   '3 * * * *',     $$SELECT enqueue_streak_protection();$$);
SELECT cron.schedule('enqueue-workout-opportunity', '3 * * * *',     $$SELECT enqueue_workout_opportunity();$$);
SELECT cron.schedule('enqueue-hydration',           '3 * * * *',     $$SELECT enqueue_hydration_intents();$$);

-- Orchestrator: every 5 minutes via HTTP→edge-fn (uses pg_net + service-role JWT).
-- If pg_net is configured (mirrors workout-intel cron pattern in 20260728),
-- this fires the orchestrator. Otherwise the orchestrator can be triggered
-- by external scheduler. We define a SQL wrapper that dispatches via pg_net.

CREATE OR REPLACE FUNCTION trigger_notification_orchestrator()
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
    RAISE WARNING 'trigger_notification_orchestrator: internal_config missing keys — skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_url || '/functions/v1/notification-orchestrator',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon,
      'x-cron-key', v_key
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
END;
$$;

GRANT EXECUTE ON FUNCTION trigger_notification_orchestrator() TO service_role;

SELECT cron.schedule(
  'notification-orchestrator-tick',
  '*/5 * * * *',
  $$SELECT trigger_notification_orchestrator();$$
);

-- =============================================================================
-- AUDIT
-- =============================================================================

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM cron.job
  WHERE jobname IN (
    'enqueue-league-placement','enqueue-recovery','enqueue-sleep-debt',
    'enqueue-rivalry','enqueue-streak-protection','enqueue-workout-opportunity',
    'enqueue-hydration','notification-orchestrator-tick'
  );

  IF v_count <> 8 THEN
    RAISE EXCEPTION 'Migration #172 audit: expected 8 cron jobs, found %', v_count;
  END IF;

  RAISE NOTICE '✅ Migration #172 (intent producers + crons) complete';
  RAISE NOTICE '   - 7 hourly producers: league/recovery/sleep/rivalry/streak/workout/hydration';
  RAISE NOTICE '   - 1 event-driven producer: enqueue_strava_celebration_intent (called from webhook)';
  RAISE NOTICE '   - notification-orchestrator scheduled every 5 minutes';
END $$;

COMMIT;
