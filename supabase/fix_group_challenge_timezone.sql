-- ============================================================================
-- FIX: Group challenge RPC parameter mismatch + timezone support
-- ============================================================================
-- CRITICAL BUG: The Swift app sends 3 parameters (p_challenge_id, p_progress,
-- p_timezone) to log_group_challenge_progress, but the SQL function only
-- accepts 2 (p_challenge_id, p_progress). PostgREST cannot find the function
-- so the call SILENTLY FAILS → group progress is NEVER written → shows 0.
--
-- This migration:
--   1. Fixes log_group_challenge_progress to accept p_timezone (3 params)
--   2. Fixes get_active_group_challenges to accept p_timezone
--   3. Both use timezone-aware date calculation for consistency
-- ============================================================================


-- ============================================================================
-- 1. FIX log_group_challenge_progress — accept timezone parameter
-- ============================================================================

-- Drop ALL existing signatures to avoid ambiguity
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
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    -- Use timezone-aware date so "today" matches the user's local day
    today_date := (NOW() AT TIME ZONE p_timezone)::DATE;

    -- Get daily target for target_hit calculation
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Upsert daily progress (only increases, never decreases)
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
-- 2. FIX get_active_group_challenges — accept timezone parameter
-- ============================================================================

DROP FUNCTION IF EXISTS get_active_group_challenges();
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
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Use timezone-aware date so "today" matches the user's local day
    today_date := (NOW() AT TIME ZONE p_timezone)::DATE;

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
        GREATEST(0, (today_date - gc.start_date)::INT) AS days_elapsed,
        GREATEST(0, (gc.end_date - today_date)::INT) AS days_remaining,
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
                AND cdp.user_id = cp2.user_id AND cdp.progress_date = today_date
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
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  GROUP CHALLENGE TIMEZONE FIX COMPLETE';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE '  🔴 CRITICAL FIX:';
    RAISE NOTICE '    log_group_challenge_progress now accepts 3 params:';
    RAISE NOTICE '    (p_challenge_id, p_progress, p_timezone)';
    RAISE NOTICE '    Previously only 2 params → Swift call SILENTLY FAILED';
    RAISE NOTICE '    → No group progress was ever written to the database!';
    RAISE NOTICE '';
    RAISE NOTICE '  ✅ get_active_group_challenges now accepts p_timezone';
    RAISE NOTICE '  ✅ Both functions use timezone-aware date calculation';
    RAISE NOTICE '  ✅ "Today" now matches the user''s local day';
    RAISE NOTICE '============================================';
END $$;
