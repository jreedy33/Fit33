-- ============================================================================
-- 20260711_get_active_challenges_my_profile_photo.sql
-- Realtime Widget Server Pull — Phase 8a (2026-04-28)
--
-- Extend `get_active_challenges` (1v1) to surface the CALLER's own
-- `profile_photo_url`, alongside the existing `opponent_photo_url`. The
-- home-screen widget extension uses both URLs to download avatars
-- DIRECTLY from Supabase Storage when the main app's
-- `ActiveChallengeWidgetBridge.publish()` hasn't yet mirrored them into
-- the App Group container — e.g. user installs the widget before ever
-- opening the app, OR the iPhone has been killed for hours and the
-- in-memory `ProfilePhotoCache` is cold.
--
-- Background:
--   Pre-this-migration the widget's photo path was:
--
--     main app foreground
--         ↓
--     ProfilePhotoCache.shared.cachedImage   (own avatar)
--     FriendPhotoCache.shared.getImage(:id)  (opponent avatars)
--         ↓ (via ActiveChallengeWidgetBridge.publish)
--     App Group container <widget_user_photo.jpg, widget_opponent_*.jpg>
--         ↓ (read by widget extension)
--     ActiveChallengeWidgetSnapshot.userPhoto / .opponentPhoto
--
--   When the main app hadn't run, the widget rendered the gradient-
--   initials fallback for both avatars even though the `get_active_challenges`
--   response already carried `opponent_photo_url`. The user's own URL was
--   absent from the response entirely — the RPC's caller-side columns
--   (my_today_progress / my_current_streak / my_last_progress_at) all came
--   from `challenge_participants` and never joined back to the caller's
--   `user_profiles` row.
--
--   This migration adds ONE caller-side join + ONE column. The widget
--   side then downloads both photos from PostgREST URLs and writes them
--   into the App Group container with the same filenames the bridge
--   uses, so subsequent renders reuse the same cached files even after
--   the bridge takes over.
--
-- Behavior contract (consumed by Fit33/SupabaseDTOs.swift +
-- RunningActivityWidget/WidgetSupabaseFetcher.swift):
--   my_profile_photo_url TEXT
--     = user_profiles.profile_photo_url for `auth.uid()`, NULL when the
--       user hasn't uploaded one yet. Privacy: NEVER honor
--       `privacy_hide_photo` for the caller's OWN photo — they're
--       looking at their own widget; the privacy flag is for opponents
--       viewing them. Same posture the in-app `ProfileView` takes when
--       rendering the user's own avatar.
--
-- Idempotency: Supabase invariant #12 — DROP every overload before
--   CREATE OR REPLACE. The 1-arg overload from
--   20260620_get_active_challenges_progress_timestamps.sql is the only
--   deployed shape today; the loop is defensive against unknown drift.
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

-- 2) Recreate with my_profile_photo_url appended.
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
    my_last_progress_at TIMESTAMPTZ,
    opponent_last_progress_at TIMESTAMPTZ,
    -- New (Phase 8a, 2026-04-28):
    my_profile_photo_url TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_caller_tz TEXT;
    v_my_photo_url TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    -- Pull caller's own profile_photo_url ONCE upfront (cheap PK lookup,
    -- one row guaranteed). We deliberately do NOT honor privacy_hide_photo
    -- here — that flag is for opponents viewing this user, not for the
    -- user's own widget. Mirrors how the in-app ProfileView renders the
    -- caller's own avatar regardless of the privacy flag.
    SELECT profile_photo_url INTO v_my_photo_url
      FROM user_profiles
     WHERE id = current_user_uuid;

    RETURN QUERY
    SELECT gc.id, gc.challenge_type, gc.title, gc.description,
        gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
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
        (SELECT MAX(cdp_my.updated_at)
           FROM challenge_daily_progress cdp_my
          WHERE cdp_my.challenge_id = gc.id
            AND cdp_my.user_id = current_user_uuid
            AND cdp_my.progress_date >= gc.start_date),
        (SELECT MAX(cdp_opp.updated_at)
           FROM challenge_daily_progress cdp_opp
          WHERE cdp_opp.challenge_id = gc.id
            AND cdp_opp.user_id = opp_cp.user_id
            AND cdp_opp.progress_date >= gc.start_date),
        -- Caller's own profile photo URL (Phase 8a). Same value on every
        -- row — repeating it per challenge is cheap (TEXT pointer in
        -- Postgres) and avoids a separate round-trip from the widget.
        v_my_photo_url
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

-- 3) Audit (Supabase invariant 28+29). Fail loud if more than one
--    definition survives, or the new column didn't land.
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

    -- The new column lives in pg_get_function_result(oid) (the RETURNS
    -- TABLE signature), NOT in prosrc. Verify both: the return signature
    -- must expose `my_profile_photo_url` AND the body must populate it.
    SELECT pg_get_function_result(p.oid) || ' || ' || p.prosrc INTO v_src
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_active_challenges';
    IF v_src NOT ILIKE '%my_profile_photo_url%' THEN
        RAISE EXCEPTION 'get_active_challenges signature is missing my_profile_photo_url';
    END IF;
    IF v_src NOT ILIKE '%v_my_photo_url%' THEN
        RAISE EXCEPTION 'get_active_challenges body never populates v_my_photo_url';
    END IF;
    -- Defensive: ensure the previous Phase 2a columns are still present
    -- (this migration was authored as additive — never dropped existing
    -- columns; fail loud if a future hand-edit accidentally regressed).
    IF v_src NOT ILIKE '%my_last_progress_at%'
       OR v_src NOT ILIKE '%opponent_last_progress_at%' THEN
        RAISE EXCEPTION 'get_active_challenges regression — Phase 2a timestamp columns missing';
    END IF;

    RAISE NOTICE '✅ get_active_challenges now exposes my_profile_photo_url (Phase 8a)';
END $$;

COMMIT;

-- ============================================================================
-- Manual verification (run as a real authenticated user — NOT psql):
--
--   SELECT challenge_id, opponent_name, opponent_photo_url, my_profile_photo_url
--     FROM get_active_challenges(p_timezone := 'America/New_York')
--    LIMIT 3;
--
-- Expected: every row repeats the caller's own profile_photo_url in the
-- `my_profile_photo_url` column (or NULL if the user has never uploaded
-- a photo). The opponent_photo_url column behavior is unchanged.
-- ============================================================================
