-- ============================================================================
-- Challenge Daily Reset — use caller's timezone, not creator_timezone
-- ============================================================================
-- BUG (bug-intelligence fingerprint 6be18e3a, medium):
--   "private challenge step count shows 15,718 at 7:27am instead of resetting
--    at midnight". Reporter in ET saw opponent Paul's yesterday-evening step
--    total rendered as "today's" count with a green target-hit checkmark at
--    7:27am local.
--
-- ROOT CAUSE:
--   `get_active_challenges`, `get_active_group_challenges`, `log_challenge_progress`,
--   and `log_group_challenge_progress` all computed `today_date` via
--       COALESCE(gc.creator_timezone, p_timezone, 'UTC')
--   When `creator_timezone` resolved to `'UTC'` (legacy challenges, or an
--   explicit UTC) the effective day boundary became 00:00 UTC — i.e. 8pm ET
--   the previous evening. Late-evening writes that were still "yesterday" in
--   the user's local calendar got stored with `progress_date = <next day UTC>`
--   and were then read back by any viewer that same calendar morning as
--   "today's" progress. The stale value persisted until 8pm ET rolled UTC
--   forward again — manifesting as "opponent already hit 16k at 7am".
--
--   Private + community RPCs were already using `p_timezone` directly for
--   the read side (`get_private_challenge_detail`, `get_my_private_challenges`,
--   `get_community_challenge_detail`, and the corresponding `log_*` RPCs), so
--   only the 1v1 / group paths and the associated log writers needed fixing.
--
-- FIX:
--   1. `today_date` for matching the daily-progress table now uses
--      `COALESCE(NULLIF(p_timezone, ''), 'UTC')` — i.e. the caller's device
--      timezone. Each user's "today" is their own local midnight. Writes and
--      reads agree on the date for any single user.
--   2. `days_elapsed` / `days_remaining` still use `creator_timezone` as a
--      stable reference so every participant sees the same "day N of the
--      challenge" / "2d left" text regardless of where they're travelling.
--   3. One-time cleanup of already-poisoned rows across all three daily
--      progress tables: any row whose `progress_date = today (America/New_York)`
--      but whose `updated_at` predates midnight America/New_York was written
--      under the UTC-rollover bug and must go. HealthKit / meal re-sync on
--      the next foreground will repopulate the correct values.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. get_active_challenges (1v1) — use caller tz for today_date join
-- ============================================================================
DROP FUNCTION IF EXISTS get_active_challenges(TEXT);

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
    opponent_is_verified BOOLEAN, opponent_is_gold_verified BOOLEAN
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
        COALESCE(opp_up.is_gold_verified, FALSE)
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

-- ============================================================================
-- 2. get_active_group_challenges (3+) — use caller tz for today_date join
-- ============================================================================
DROP FUNCTION IF EXISTS get_active_group_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_active_group_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID, title TEXT, description TEXT, challenge_type TEXT, mode TEXT,
    daily_target INT, total_target INT, target_unit TEXT,
    start_date TEXT, end_date TEXT, duration_days INT,
    days_elapsed INT, days_remaining INT, status TEXT,
    created_by UUID, member_count INT, members JSONB
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_caller_tz TEXT;
    v_today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');
    v_today_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    RETURN QUERY
    SELECT gc.id, gc.title, gc.description, gc.challenge_type,
        COALESCE(gc.mode, 'competition'), gc.daily_target, gc.total_target, gc.target_unit,
        gc.start_date::TEXT, gc.end_date::TEXT, gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, v_caller_tz))::DATE - gc.start_date)::INT),
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, v_caller_tz))::DATE)::INT),
        gc.status, gc.created_by,
        (SELECT COUNT(*)::INT FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id),
        (SELECT jsonb_agg(jsonb_build_object(
            'user_id', cp2.user_id, 'status', cp2.status,
            'total_progress', COALESCE(cp2.total_progress, 0),
            'today_progress', COALESCE(cdp.progress_value, 0),
            'days_completed', COALESCE(cp2.days_completed, 0),
            'current_streak', COALESCE(cp2.current_streak, 0),
            'name', up2.name, 'username', up2.username,
            'profile_photo_url', CASE WHEN COALESCE(up2.privacy_hide_photo, FALSE) THEN NULL ELSE up2.profile_photo_url END,
            'is_verified', COALESCE(up2.is_verified, FALSE),
            'is_gold_verified', COALESCE(up2.is_gold_verified, FALSE)
        ))
        FROM challenge_participants cp2
        JOIN user_profiles up2 ON up2.id = cp2.user_id
        LEFT JOIN challenge_daily_progress cdp ON cdp.challenge_id = gc.id
            AND cdp.user_id = cp2.user_id
            AND cdp.progress_date = v_today_date
        WHERE cp2.challenge_id = gc.id)
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    WHERE gc.status IN ('pending', 'active')
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) > 2
    ORDER BY gc.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION get_active_group_challenges(TEXT) TO authenticated;

-- ============================================================================
-- 3. log_challenge_progress (1v1) — key progress_date off caller tz
-- ============================================================================
-- Swift sends 7 params (p_challenge_id, p_progress_value, p_progress_date,
-- p_source, p_workout_id, p_timezone, p_allow_decrease). The override
-- p_progress_date is still honored (simulator / backfill); otherwise "today"
-- is the caller's local date — NOT creator's.
-- ============================================================================
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id TEXT,
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_workout_id TEXT DEFAULT NULL,
    p_timezone TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    v_progress_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_caller_tz TEXT;
    v_current_streak INT := 0;
    v_best_streak INT := 0;
    v_check_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    SELECT daily_target INTO v_daily_target
    FROM group_challenges WHERE id = challenge_uuid;

    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    INSERT INTO challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, workout_id, updated_at
    ) VALUES (
        challenge_uuid, current_user_uuid, v_progress_date, p_progress_value,
        v_target_hit, p_source,
        CASE WHEN p_workout_id IS NOT NULL AND p_workout_id != '' THEN p_workout_id::UUID ELSE NULL END,
        NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = CASE
            WHEN p_allow_decrease THEN EXCLUDED.progress_value
            ELSE GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value)
        END,
        target_hit = CASE
            WHEN p_allow_decrease THEN EXCLUDED.target_hit
            WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
            THEN EXCLUDED.target_hit
            ELSE challenge_daily_progress.target_hit
        END,
        source = EXCLUDED.source,
        updated_at = NOW();

    v_check_date := v_progress_date;
    v_current_streak := 0;
    LOOP
        IF EXISTS (
            SELECT 1 FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid
              AND user_id = current_user_uuid
              AND challenge_daily_progress.progress_date = v_check_date
              AND (target_hit = TRUE OR progress_value >= COALESCE(v_daily_target, 0))
        ) THEN
            v_current_streak := v_current_streak + 1;
            v_check_date := v_check_date - INTERVAL '1 day';
        ELSE
            EXIT;
        END IF;
        IF v_current_streak > 365 THEN EXIT; END IF;
    END LOOP;

    SELECT COALESCE(best_streak, 0) INTO v_best_streak
    FROM challenge_participants
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    v_best_streak := GREATEST(v_best_streak, v_current_streak);

    UPDATE challenge_participants
    SET
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM challenge_daily_progress cdp
            JOIN group_challenges gc ON gc.id = cdp.challenge_id
            WHERE cdp.challenge_id = challenge_uuid
            AND cdp.user_id = current_user_uuid
            AND (cdp.target_hit = TRUE OR cdp.progress_value >= COALESCE(gc.daily_target, 0))
        ),
        current_streak = v_current_streak,
        best_streak = v_best_streak
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ============================================================================
-- 4. log_group_challenge_progress (3+) — key progress_date off caller tz
-- ============================================================================
DROP FUNCTION IF EXISTS log_group_challenge_progress(TEXT, INT);
DROP FUNCTION IF EXISTS log_group_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_group_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_group_challenge_progress(
    p_challenge_id TEXT,
    p_progress INT,
    p_timezone TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_caller_tz TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    today_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    INSERT INTO challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        challenge_uuid, current_user_uuid, today_date, p_progress, v_target_hit, 'healthkit', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = CASE
            WHEN p_allow_decrease THEN EXCLUDED.progress_value
            ELSE GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value)
        END,
        target_hit = CASE
            WHEN p_allow_decrease THEN EXCLUDED.target_hit
            WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
            THEN EXCLUDED.target_hit
            ELSE challenge_daily_progress.target_hit
        END,
        updated_at = NOW();

    UPDATE challenge_participants
    SET
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM challenge_daily_progress cdp
            JOIN group_challenges gc ON gc.id = cdp.challenge_id
            WHERE cdp.challenge_id = challenge_uuid
            AND cdp.user_id = current_user_uuid
            AND (cdp.target_hit = TRUE OR cdp.progress_value >= COALESCE(gc.daily_target, 0))
        )
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_group_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

-- ============================================================================
-- 5. One-time cleanup of UTC-rollover poisoned rows across all daily tables
-- ============================================================================
-- Before this migration, challenges whose creator_timezone resolved to 'UTC'
-- wrote progress rows keyed by UTC midnight. Those rows sit for ~hours
-- appearing as "today" to any ET/PT-based viewer before the real local
-- midnight rolls over. Delete any row whose progress_date matches today in
-- America/New_York but whose updated_at predates midnight America/New_York
-- (the same window used in 20260306_fix_daily_progress_reset cleanup).
-- Re-sync will repopulate from HealthKit / meals / hydration on next fg.
-- ============================================================================

-- 1v1 + group (same table)
DELETE FROM challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Community
DELETE FROM community_challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Private
DELETE FROM private_challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Recompute challenge_participants.total_progress after the targeted deletes.
-- SUM over remaining daily rows keeps the aggregate honest even though the
-- next log_*_progress write will also refresh it.
UPDATE challenge_participants cp
SET total_progress = (
    SELECT COALESCE(SUM(progress_value), 0)
    FROM challenge_daily_progress cdp
    WHERE cdp.challenge_id = cp.challenge_id AND cdp.user_id = cp.user_id
)
WHERE cp.challenge_id IN (
    SELECT DISTINCT challenge_id FROM challenge_daily_progress
);

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ CHALLENGE DAILY RESET → CALLER TZ DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Changes:';
    RAISE NOTICE '   1. get_active_challenges — today_date uses caller p_timezone';
    RAISE NOTICE '   2. get_active_group_challenges — today_date uses caller p_timezone';
    RAISE NOTICE '   3. log_challenge_progress — progress_date uses caller p_timezone';
    RAISE NOTICE '   4. log_group_challenge_progress — progress_date uses caller p_timezone';
    RAISE NOTICE '   5. creator_timezone still drives days_elapsed / days_remaining';
    RAISE NOTICE '   6. One-time UTC-rollover cleanup across all three daily tables';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Expected behavior:';
    RAISE NOTICE '   • Each user sees "today" reset at their OWN local midnight';
    RAISE NOTICE '   • No yesterday end-of-day value leaks into today''s number';
    RAISE NOTICE '   • Opponent step counts converge as their devices sync';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
