-- ============================================================================
-- FIX: Ambiguous column references + duplicate function overloads
-- ============================================================================
-- Error 1: log_challenge_progress has local variable "progress_date" that 
--   clashes with column "progress_date" in challenge_daily_progress table.
--   PostgreSQL error 42702: "column reference progress_date is ambiguous"
--
-- Error 2: cancel_group_challenge exists as both (TEXT) and (UUID) overloads.
--   PostgREST error PGRST203: "Could not choose the best candidate function"
-- ============================================================================


-- ============================================================================
-- FIX 1: log_challenge_progress — rename local var to avoid column ambiguity
-- ============================================================================

DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id TEXT,
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_workout_id TEXT DEFAULT NULL
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
    v_current_streak INT := 0;
    v_best_streak INT := 0;
    v_check_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Parse date (renamed to v_progress_date to avoid column ambiguity)
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := CURRENT_DATE;
    END IF;

    -- Verify user is a participant in this challenge
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    -- Get daily target for this challenge
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    -- Check if this progress value hits the daily target
    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Upsert daily progress (update if higher, don't decrease)
    INSERT INTO challenge_daily_progress (
        challenge_id,
        user_id,
        progress_date,
        progress_value,
        target_hit,
        source,
        workout_id,
        updated_at
    ) VALUES (
        challenge_uuid,
        current_user_uuid,
        v_progress_date,
        p_progress_value,
        v_target_hit,
        p_source,
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

    -- Calculate streak: count consecutive days where target was hit
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
        
        IF v_current_streak > 365 THEN
            EXIT;
        END IF;
    END LOOP;

    -- Get existing best streak
    SELECT COALESCE(best_streak, 0) INTO v_best_streak
    FROM challenge_participants
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    v_best_streak := GREATEST(v_best_streak, v_current_streak);

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
        ),
        current_streak = v_current_streak,
        best_streak = v_best_streak
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- FIX 2: cancel_group_challenge — drop duplicate UUID overload
-- ============================================================================

-- Drop BOTH overloads, then recreate only the TEXT version
DROP FUNCTION IF EXISTS cancel_group_challenge(TEXT);
DROP FUNCTION IF EXISTS cancel_group_challenge(UUID);

CREATE OR REPLACE FUNCTION cancel_group_challenge(
    p_challenge_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Only creator can cancel
    IF NOT EXISTS (
        SELECT 1 FROM group_challenges
        WHERE id = challenge_uuid AND created_by = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'Only the creator can cancel a group challenge';
    END IF;

    -- Cancel the challenge
    UPDATE group_challenges SET status = 'cancelled' WHERE id = challenge_uuid;
    
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_group_challenge(TEXT) TO authenticated;


-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  AMBIGUOUS COLUMN + OVERLOAD FIXES';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  ✅ log_challenge_progress: renamed progress_date → v_progress_date';
    RAISE NOTICE '     (fixes PostgreSQL error 42702)';
    RAISE NOTICE '  ✅ cancel_group_challenge: dropped UUID overload';
    RAISE NOTICE '     (fixes PostgREST error PGRST203)';
    RAISE NOTICE '============================================';
END $$;
