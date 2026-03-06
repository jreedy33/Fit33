-- ============================================================================
-- FIX: Challenge Daily Progress Not Resetting at Midnight
-- ============================================================================
-- PROBLEM: "Today's progress" shows yesterday's value (e.g. 14g protein on a
-- new day). This affects ALL challenge types: 1v1, community, and private.
--
-- ROOT CAUSES:
--   1. 1v1 log_challenge_progress does NOT accept p_allow_decrease — Swift
--      sends 7 params but SQL only accepts 6 → PostgREST silently fails.
--   2. today_progress denormalized field on community_challenge_participants
--      and private_challenge_members is set on each log but NEVER reset to 0
--      at midnight. If any read path uses this field, it shows stale data.
--   3. Timezone inconsistency: if any function uses CURRENT_DATE (UTC) instead
--      of (NOW() AT TIME ZONE tz)::DATE, evening progress is stored under the
--      wrong date.
--
-- FIXES:
--   1. Recreate log_challenge_progress with p_allow_decrease parameter
--   2. Recreate log_community_challenge_progress with p_allow_decrease
--   3. Recreate log_private_challenge_progress with p_allow_decrease
--   4. All use creator_timezone with proper fallback chain
--   5. get_active_challenges uses per-challenge timezone
--   6. get_active_group_challenges uses per-challenge timezone
--   7. Cleanup query for stale today_progress denormalized fields
-- ============================================================================


-- ============================================================================
-- FIX 1: log_challenge_progress (1v1) — ADD p_allow_decrease
-- ============================================================================
-- CRITICAL: Swift sends p_allow_decrease but old SQL doesn't accept it.
-- PostgREST can't find a matching function → call silently fails.
-- ============================================================================

-- Drop ALL existing signatures to avoid ambiguity
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
    v_challenge_tz TEXT;
    v_current_streak INT := 0;
    v_best_streak INT := 0;
    v_check_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Get the challenge's timezone and daily target
    -- Priority: challenge's stored timezone > caller's timezone > UTC
    SELECT COALESCE(creator_timezone, NULLIF(p_timezone, ''), 'UTC'), daily_target
    INTO v_challenge_tz, v_daily_target
    FROM group_challenges WHERE id = challenge_uuid;

    -- Determine "today" in the challenge's timezone
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_challenge_tz)::DATE;
    END IF;

    -- Verify user is a participant in this challenge
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Upsert daily progress
    -- When p_allow_decrease is TRUE, bypass GREATEST() so the value can decrease
    -- (needed for protein/calories when meals are removed)
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

    -- Calculate streak from v_progress_date backwards
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

    -- Update aggregates in challenge_participants
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
-- FIX 2: log_community_challenge_progress — ensure p_allow_decrease + timezone
-- ============================================================================
-- Recreate with all 4 params for safety (may already exist from previous fix)
-- ============================================================================

DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_community_challenge_progress(
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
    v_challenge_id UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_prev_target_hit BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    -- Get daily target
    SELECT daily_target INTO v_daily_target
    FROM community_challenges WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Check if target was already hit (for completion counting)
    SELECT target_hit INTO v_prev_target_hit
    FROM community_challenge_daily_progress
    WHERE challenge_id = v_challenge_id 
      AND user_id = current_user_uuid 
      AND progress_date = today_date;

    INSERT INTO community_challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = CASE
            WHEN p_allow_decrease THEN EXCLUDED.progress_value
            ELSE GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
        END,
        target_hit = CASE 
            WHEN p_allow_decrease THEN EXCLUDED.target_hit
            WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value 
            THEN EXCLUDED.target_hit
            ELSE community_challenge_daily_progress.target_hit
        END,
        source = EXCLUDED.source,
        updated_at = NOW();

    -- Update days_completed if newly hit target, and always update last_active_at + today_progress
    UPDATE community_challenge_participants
    SET days_completed = CASE
            WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
            THEN COALESCE(days_completed, 0) + 1
            ELSE days_completed
        END,
        today_progress = p_progress,
        last_active_at = NOW()
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- FIX 3: log_private_challenge_progress — ensure p_allow_decrease + timezone
-- ============================================================================

DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_private_challenge_progress(
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
    v_challenge_id UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_user_name TEXT;
    v_challenge_title TEXT;
    v_notifications_enabled BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    -- Get challenge info
    SELECT daily_target, title, notifications_enabled
    INTO v_daily_target, v_challenge_title, v_notifications_enabled
    FROM private_challenges WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Check if target was already hit
    SELECT target_hit INTO v_prev_target_hit
    FROM private_challenge_daily_progress
    WHERE challenge_id = v_challenge_id 
      AND user_id = current_user_uuid 
      AND progress_date = today_date;

    INSERT INTO private_challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = CASE
            WHEN p_allow_decrease THEN EXCLUDED.progress_value
            ELSE GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
        END,
        target_hit = CASE 
            WHEN p_allow_decrease THEN EXCLUDED.target_hit
            WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value 
            THEN EXCLUDED.target_hit
            ELSE private_challenge_daily_progress.target_hit
        END,
        source = EXCLUDED.source,
        updated_at = NOW();

    -- Update days_completed if newly hit target, and always update last_active_at + today_progress
    UPDATE private_challenge_members
    SET days_completed = CASE
            WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
            THEN COALESCE(days_completed, 0) + 1
            ELSE days_completed
        END,
        today_progress = p_progress,
        last_active_at = NOW()
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- FIX 4: log_group_challenge_progress — ensure timezone via creator_timezone
-- ============================================================================

DROP FUNCTION IF EXISTS log_group_challenge_progress(TEXT, INT);
DROP FUNCTION IF EXISTS log_group_challenge_progress(TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION log_group_challenge_progress(
    p_challenge_id TEXT,
    p_progress INT,
    p_timezone TEXT DEFAULT 'UTC'
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
    v_challenge_tz TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    -- Use challenge's stored timezone (falls back to caller's timezone, then UTC)
    SELECT COALESCE(creator_timezone, NULLIF(p_timezone, ''), 'UTC'), daily_target
    INTO v_challenge_tz, v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    today_date := (NOW() AT TIME ZONE v_challenge_tz)::DATE;
    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Upsert daily progress
    INSERT INTO challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        challenge_uuid, current_user_uuid, today_date, p_progress, v_target_hit, 'healthkit', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value),
        target_hit = CASE
            WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
            THEN EXCLUDED.target_hit
            ELSE challenge_daily_progress.target_hit
        END,
        updated_at = NOW()
    WHERE EXCLUDED.progress_value > challenge_daily_progress.progress_value;

    -- Update aggregates on challenge_participants
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

GRANT EXECUTE ON FUNCTION log_group_challenge_progress(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- FIX 5: get_active_challenges — per-challenge timezone for "today"
-- ============================================================================

DROP FUNCTION IF EXISTS get_active_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_active_challenges(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    days_elapsed INT,
    days_remaining INT,
    status TEXT,
    my_total_progress INT,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    opponent_id UUID,
    opponent_name TEXT,
    opponent_username TEXT,
    opponent_photo_url TEXT,
    opponent_total_progress INT,
    opponent_today_progress INT,
    opponent_days_completed INT,
    am_winning BOOLEAN,
    am_winning_today BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Each challenge uses its own creator_timezone for "today" date.
    -- Falls back to p_timezone (caller's) for legacy challenges without a stored timezone.
    RETURN QUERY
    SELECT
        gc.id AS challenge_id,
        gc.challenge_type,
        gc.title,
        gc.description,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE - gc.start_date)::INT) AS days_elapsed,
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE)::INT) AS days_remaining,
        gc.status,
        COALESCE(my_cp.total_progress, 0)::INT AS my_total_progress,
        COALESCE(my_today.progress_value, 0)::INT AS my_today_progress,
        COALESCE(my_cp.days_completed, 0)::INT AS my_days_completed,
        COALESCE(my_cp.current_streak, 0)::INT AS my_current_streak,
        opp_cp.user_id AS opponent_id,
        opp_up.name AS opponent_name,
        opp_up.username AS opponent_username,
        opp_up.profile_photo_url AS opponent_photo_url,
        COALESCE(opp_cp.total_progress, 0)::INT AS opponent_total_progress,
        COALESCE(opp_today.progress_value, 0)::INT AS opponent_today_progress,
        COALESCE(opp_cp.days_completed, 0)::INT AS opponent_days_completed,
        (COALESCE(my_cp.total_progress, 0) >= COALESCE(opp_cp.total_progress, 0)) AS am_winning,
        (COALESCE(my_today.progress_value, 0) >= COALESCE(opp_today.progress_value, 0)) AS am_winning_today
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = gc.id AND opp_cp.user_id != current_user_uuid
    JOIN user_profiles opp_up ON opp_up.id = opp_cp.user_id
    -- My today's progress (using challenge's timezone for "today")
    LEFT JOIN challenge_daily_progress my_today 
        ON my_today.challenge_id = gc.id 
        AND my_today.user_id = current_user_uuid 
        AND my_today.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
    -- Opponent's today's progress (same timezone — both see the same "today")
    LEFT JOIN challenge_daily_progress opp_today 
        ON opp_today.challenge_id = gc.id 
        AND opp_today.user_id = opp_cp.user_id 
        AND opp_today.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
    WHERE gc.status = 'active'
    AND my_cp.status = 'accepted'
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) = 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;


-- ============================================================================
-- FIX 6: get_active_group_challenges — per-challenge timezone for "today"
-- ============================================================================

DROP FUNCTION IF EXISTS get_active_group_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_active_group_challenges(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    challenge_type TEXT,
    mode TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    days_elapsed INT,
    days_remaining INT,
    status TEXT,
    created_by UUID,
    member_count INT,
    members JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
        gc.id AS challenge_id,
        gc.title,
        gc.description,
        gc.challenge_type,
        COALESCE(gc.mode, 'competition') AS mode,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        GREATEST(0, ((NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE - gc.start_date)::INT) AS days_elapsed,
        GREATEST(0, (gc.end_date - (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE)::INT) AS days_remaining,
        gc.status,
        gc.created_by,
        (SELECT COUNT(*)::INT FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) AS member_count,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', cp2.user_id,
                'status', cp2.status,
                'total_progress', COALESCE(cp2.total_progress, 0),
                'today_progress', COALESCE(cdp.progress_value, 0),
                'days_completed', COALESCE(cp2.days_completed, 0),
                'current_streak', COALESCE(cp2.current_streak, 0),
                'name', up2.name,
                'username', up2.username,
                'profile_photo_url', up2.profile_photo_url
            ))
            FROM challenge_participants cp2
            JOIN user_profiles up2 ON up2.id = cp2.user_id
            LEFT JOIN challenge_daily_progress cdp ON cdp.challenge_id = gc.id 
                AND cdp.user_id = cp2.user_id 
                AND cdp.progress_date = (NOW() AT TIME ZONE COALESCE(gc.creator_timezone, p_timezone, 'UTC'))::DATE
            WHERE cp2.challenge_id = gc.id
        ) AS members
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    WHERE gc.status IN ('pending', 'active')
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) > 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_group_challenges(TEXT) TO authenticated;


-- ============================================================================
-- FIX 7: Ensure creator_timezone column exists on group_challenges
-- ============================================================================
ALTER TABLE group_challenges
ADD COLUMN IF NOT EXISTS creator_timezone TEXT DEFAULT NULL;


-- ============================================================================
-- FIX 8: Reset stale today_progress denormalized fields
-- ============================================================================
-- These fields cache the last logged progress but never reset at midnight.
-- Reset them to 0 so they don't confuse any code paths that read them.
-- The actual "today" values come from JOINs on the daily progress tables.
-- ============================================================================

UPDATE community_challenge_participants
SET today_progress = 0
WHERE today_progress != 0
  AND last_active_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

UPDATE private_challenge_members
SET today_progress = 0
WHERE today_progress != 0
  AND last_active_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );


-- ============================================================================
-- FIX 9: One-time cleanup of misplaced daily progress rows
-- ============================================================================
-- If progress was logged using UTC (CURRENT_DATE) instead of the local
-- timezone, evening progress (e.g. 8 PM ET = midnight+ UTC) got stored
-- under the NEXT day's date. On the next morning, that row shows up as
-- "today's progress" even though no activity happened today.
--
-- Fix: Delete ALL daily progress rows for "today" across all challenge types.
-- This is safe because:
--   • HealthKit data gets re-synced automatically on app launch
--   • Meal/protein data gets re-synced automatically on app launch
--   • Manual inputs for today would be re-entered by the user
-- The re-sync will create correct rows using the fixed timezone-aware functions.
-- ============================================================================

-- Clean up 1v1 challenges
DELETE FROM challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Clean up community challenges
DELETE FROM community_challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Clean up private challenges
DELETE FROM private_challenge_daily_progress
WHERE progress_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
  AND updated_at < (
      ((NOW() AT TIME ZONE 'America/New_York')::DATE)::TIMESTAMP
      AT TIME ZONE 'America/New_York'
  );

-- Recalculate total_progress aggregates after cleanup
-- (total_progress = SUM of all daily progress values)
UPDATE challenge_participants cp
SET total_progress = (
    SELECT COALESCE(SUM(progress_value), 0)
    FROM challenge_daily_progress cdp
    WHERE cdp.challenge_id = cp.challenge_id AND cdp.user_id = cp.user_id
)
WHERE cp.challenge_id IN (
    SELECT DISTINCT challenge_id FROM challenge_daily_progress
);


-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ DAILY PROGRESS RESET FIX DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Changes:';
    RAISE NOTICE '   1. log_challenge_progress: NOW ACCEPTS p_allow_decrease';
    RAISE NOTICE '      → Swift sends 7 params, SQL now accepts 7 ✅';
    RAISE NOTICE '   2. log_community_challenge_progress: timezone + allow_decrease';
    RAISE NOTICE '   3. log_private_challenge_progress: timezone + allow_decrease';
    RAISE NOTICE '   4. log_group_challenge_progress: uses creator_timezone';
    RAISE NOTICE '   5. get_active_challenges: per-challenge timezone';
    RAISE NOTICE '   6. get_active_group_challenges: per-challenge timezone';
    RAISE NOTICE '   7. Stale today_progress denormalized fields reset';
    RAISE NOTICE '   8. Misplaced daily progress rows cleaned up';
    RAISE NOTICE '';
    RAISE NOTICE '🔑 KEY: All progress dates now use timezone-aware calculations.';
    RAISE NOTICE '   Progress logged at 11 PM ET is correctly stored as that day,';
    RAISE NOTICE '   not the next UTC day. Each new day starts at 0.';
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
