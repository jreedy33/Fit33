-- ============================================================================
-- 20260620_get_active_challenges_progress_timestamps.sql
-- Realtime Widget Server Pull — Phase 2a (2026-04-26)
--
-- Extend `get_active_challenges` (1v1) to surface the most recent server-side
-- progress timestamps for both participants, so the home-screen widget +
-- in-app `activeChallengeDetailWidget` can render an honest "— · 8h ago"
-- staleness label instead of a misleading "0 steps" when an opponent's
-- phone hasn't synced HealthKit data to Supabase recently.
--
-- Background:
--   Up until 2026-04-26 the widget's only signal was `opponent_today_progress`
--   (the row's `progress_value`). When the opponent's phone hadn't pushed any
--   HealthKit/meal/cardio data to Supabase since the local-midnight reset
--   (Manuel: opens app once a day; APNs silent-push budget exhausted), that
--   value sat at 0 indefinitely — and the widget displayed a confident
--   "0 steps" that was actually "no data".
--
--   With these timestamps the client side (Shared/ProgressFreshness.swift,
--   Phase 6) can route the value through a fresh / recent / stale evaluator:
--     • fresh   < 1 h     → render the value as-is
--     • recent  < 6 h     → render value with a small `8m ago` sub-label
--     • stale   ≥ 6 h     → swap value for `—` and surface `8h ago` prominently
--
-- Scope (deliberately minimal):
--   • Only `get_active_challenges` (1v1) — that's the only RPC the widget
--     extension consumes. Group / community / private challenges are NOT
--     surfaced on the home-screen widget today, so adding the same fields
--     to their RPCs is left to a follow-up if/when those surfaces ship.
--   • Steps / active_minutes / calories / hydrate / protein / etc. all flow
--     through the same `challenge_daily_progress` table, so a single
--     `MAX(updated_at)` query covers every challenge type without per-type
--     branching. We deliberately don't union across the 1v1 +
--     private + community tables here — Data invariant #48's fanout
--     trigger keeps them in sync and the per-table timestamp is the
--     authoritative "when did THIS row land?" signal.
--   • `start_date` is the historical floor for `MAX()` — older
--     `challenge_daily_progress` rows from previous challenges with the
--     same participants don't drift the freshness signal.
--
-- Behavior contract (consumed by Fit33/SupabaseDTOs.swift +
-- RunningActivityWidget/WidgetSupabaseFetcher.swift):
--   my_last_progress_at TIMESTAMPTZ
--     = MAX(updated_at) on `challenge_daily_progress` for (gc.id,
--       caller, progress_date >= gc.start_date), NULL when no rows
--   opponent_last_progress_at TIMESTAMPTZ
--     = same predicate against the opponent's user_id, NULL when no rows
--
-- Idempotency: Supabase invariant #12 — DROP every overload before
--   CREATE OR REPLACE. The 1-arg overload from
--   20260520_challenge_daily_reset_caller_tz.sql is the only deployed
--   shape today; the loop is defensive against unknown drift.
-- ============================================================================

BEGIN;

-- 1) Drop every existing overload (Supabase invariant 12).
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'get_active_challenges'
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.nspname, r.proname, r.args);
    END LOOP;
END $$;

-- 2) Recreate with two new TIMESTAMPTZ output columns appended.
CREATE OR REPLACE FUNCTION get_active_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, challenge_type TEXT, title TEXT, description TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    days_elapsed INT, days_remaining INT, status TEXT,
    my_total_progress INT, my_today_progress INT, my_days_completed INT, my_current_streak INT,
    opponent_id UUID, opponent_name TEXT, opponent_username TEXT, opponent_photo_url TEXT,
    opponent_total_progress INT, opponent_today_progress INT, opponent_days_completed INT,
    am_winning BOOLEAN, am_winning_today BOOLEAN,
    opponent_is_verified BOOLEAN, opponent_is_gold_verified BOOLEAN,
    -- New (Phase 2a, 2026-04-26):
    my_last_progress_at TIMESTAMPTZ,
    opponent_last_progress_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_caller_tz TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');
    RETURN QUERY
    SELECT gc.id, gc.challenge_type, gc.title, gc.description,
        gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        -- days_elapsed/remaining still anchored to creator_timezone so the
        -- number doesn't change as viewers travel across timezones.
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, v_caller_tz))::DATE - gc.start_date)::INT),
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, v_caller_tz))::DATE)::INT),
        gc.status,
        COALESCE(my_cp.total_progress, 0)::INT, COALESCE(my_today.progress_value, 0)::INT,
        COALESCE(my_cp.days_completed, 0)::INT, COALESCE(my_cp.current_streak, 0)::INT,
        opp_cp.user_id, opp_up.name, opp_up.username,
        CASE WHEN COALESCE(opp_up.privacy_hide_photo, FALSE) THEN NULL ELSE opp_up.profile_photo_url END,
        COALESCE(opp_cp.total_progress, 0)::INT, COALESCE(opp_today.progress_value, 0)::INT,
        COALESCE(opp_cp.days_completed, 0)::INT,
        (COALESCE(my_cp.total_progress, 0) >= COALESCE(opp_cp.total_progress, 0)),
        (COALESCE(my_today.progress_value, 0) >= COALESCE(opp_today.progress_value, 0)),
        COALESCE(opp_up.is_verified, FALSE),
        COALESCE(opp_up.is_gold_verified, FALSE),
        -- New columns: most recent server-side progress write per participant
        -- across the entire challenge window (not just today). Drives the
        -- widget freshness pill — "8h ago" — when the opponent's phone has
        -- gone silent. Scoped to progress_date >= gc.start_date so pre-challenge
        -- rows from prior 1v1s with the same person don't bleed in.
        (SELECT MAX(cdp_my.updated_at)
           FROM challenge_daily_progress cdp_my
          WHERE cdp_my.challenge_id = gc.id
            AND cdp_my.user_id = current_user_uuid
            AND cdp_my.progress_date >= gc.start_date),
        (SELECT MAX(cdp_opp.updated_at)
           FROM challenge_daily_progress cdp_opp
          WHERE cdp_opp.challenge_id = gc.id
            AND cdp_opp.user_id = opp_cp.user_id
            AND cdp_opp.progress_date >= gc.start_date)
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = gc.id AND opp_cp.user_id != current_user_uuid
    JOIN user_profiles opp_up ON opp_up.id = opp_cp.user_id
    LEFT JOIN challenge_daily_progress my_today ON my_today.challenge_id = gc.id AND my_today.user_id = current_user_uuid
        AND my_today.progress_date = (NOW() AT TIME ZONE v_caller_tz)::DATE
    LEFT JOIN challenge_daily_progress opp_today ON opp_today.challenge_id = gc.id AND opp_today.user_id = opp_cp.user_id
        AND opp_today.progress_date = (NOW() AT TIME ZONE v_caller_tz)::DATE
    WHERE gc.status = 'active' AND my_cp.status = 'accepted'
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) = 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;

-- 3) Audit (Supabase invariant 28+29). Fail loud if more than one definition
--    survives, or the new column names didn't land in the function body.
DO $$
DECLARE
    v_count INT;
    v_src TEXT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_active_challenges';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'get_active_challenges: expected exactly 1 definition, found %', v_count;
    END IF;

    -- The new columns are declared in RETURNS TABLE(...), so they live in
    -- pg_get_function_result(oid), NOT in prosrc (the body). Verify both:
    -- the return signature must expose the columns, and the body must populate
    -- them via the MAX(updated_at) subqueries.
    SELECT pg_get_function_result(p.oid) || ' || ' || p.prosrc INTO v_src
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_active_challenges';
    IF v_src NOT ILIKE '%my_last_progress_at%'
       OR v_src NOT ILIKE '%opponent_last_progress_at%' THEN
        RAISE EXCEPTION 'get_active_challenges signature is missing the new progress-timestamp columns';
    END IF;
    IF v_src NOT ILIKE '%MAX(cdp_my.updated_at)%'
       OR v_src NOT ILIKE '%MAX(cdp_opp.updated_at)%' THEN
        RAISE EXCEPTION 'get_active_challenges body is missing the MAX(updated_at) subqueries';
    END IF;

    RAISE NOTICE '✅ get_active_challenges now exposes my_last_progress_at + opponent_last_progress_at';
END $$;

COMMIT;
