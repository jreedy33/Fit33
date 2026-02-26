-- ============================================================================
-- FIX: Allow challenge progress to DECREASE when meals/hydration are removed
-- ============================================================================
-- Problem: log_challenge_progress and log_group_challenge_progress use
--   GREATEST(existing, new) + WHERE new > existing
-- This means if a user removes a meal, the lower total is silently rejected,
-- no row changes, no realtime event fires, and the opponent never sees the update.
--
-- Solution: Add p_allow_decrease BOOLEAN DEFAULT FALSE parameter. When TRUE,
-- the upsert directly sets the new value (even if lower) and always triggers
-- the update (which fires the realtime event).
--
-- Called with allow_decrease=true ONLY from meal removal / hydration deletion.
-- All other callers (HealthKit sync, manual log, etc.) default to FALSE,
-- preserving the existing "only go up" safety behavior.
-- ============================================================================

-- ============================================================================
-- 1. Fix log_challenge_progress (1v1)
-- ============================================================================
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
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Parse date: use timezone-aware "today" when no explicit date given.
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    END IF;

    -- Verify user is a participant in this challenge
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    -- Get daily target for target_hit tracking
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;
    
    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    IF p_allow_decrease THEN
        -- Allow value to go DOWN (used when meals/hydration are removed).
        -- Always update so realtime event fires even if value decreased.
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, workout_id, updated_at
        ) VALUES (
            challenge_uuid, current_user_uuid, v_progress_date, p_progress_value,
            v_target_hit, p_source,
            CASE WHEN p_workout_id IS NOT NULL AND p_workout_id != '' THEN p_workout_id::UUID ELSE NULL END,
            NOW()
        )
        ON CONFLICT (challenge_id, user_id, progress_date)
        DO UPDATE SET
            progress_value = EXCLUDED.progress_value,
            target_hit = EXCLUDED.target_hit,
            source = EXCLUDED.source,
            updated_at = NOW();
    ELSE
        -- Normal behavior: only allow progress to GO UP (GREATEST).
        -- The WHERE clause ensures no-op if value didn't increase,
        -- which avoids spurious realtime events.
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, workout_id, updated_at
        ) VALUES (
            challenge_uuid, current_user_uuid, v_progress_date, p_progress_value,
            v_target_hit, p_source,
            CASE WHEN p_workout_id IS NOT NULL AND p_workout_id != '' THEN p_workout_id::UUID ELSE NULL END,
            NOW()
        )
        ON CONFLICT (challenge_id, user_id, progress_date)
        DO UPDATE SET
            progress_value = GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value),
            target_hit = CASE
                WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
                THEN EXCLUDED.target_hit
                ELSE challenge_daily_progress.target_hit
            END,
            source = EXCLUDED.source,
            updated_at = NOW()
        WHERE EXCLUDED.progress_value > challenge_daily_progress.progress_value;
    END IF;

    -- Update aggregate in challenge_participants
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

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- 2. Fix log_group_challenge_progress
-- ============================================================================
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
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Get daily target for target_hit tracking
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;
    
    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    IF p_allow_decrease THEN
        -- Allow value to go DOWN (used when meals/hydration are removed)
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, updated_at
        ) VALUES (
            challenge_uuid, current_user_uuid, today_date, p_progress,
            v_target_hit, 'healthkit', NOW()
        )
        ON CONFLICT (challenge_id, user_id, progress_date)
        DO UPDATE SET
            progress_value = EXCLUDED.progress_value,
            target_hit = EXCLUDED.target_hit,
            updated_at = NOW();
    ELSE
        -- Normal behavior: only allow progress to GO UP
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, updated_at
        ) VALUES (
            challenge_uuid, current_user_uuid, today_date, p_progress,
            v_target_hit, 'healthkit', NOW()
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
    END IF;

    -- Update aggregates
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
            AND cdp.progress_value >= COALESCE(gc.daily_target, 0)
        )
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_group_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- Verify
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Challenge progress decrease fix applied successfully';
    RAISE NOTICE '   • log_challenge_progress now accepts p_allow_decrease (7th param)';
    RAISE NOTICE '   • log_group_challenge_progress now accepts p_allow_decrease (4th param)';
    RAISE NOTICE '   • When TRUE: value can decrease and always triggers realtime event';
    RAISE NOTICE '   • When FALSE (default): existing GREATEST behavior preserved';
END $$;
