-- ============================================================================
-- SIMULATOR TEST HELPER FUNCTIONS
-- ============================================================================
-- These SECURITY DEFINER functions allow the Social System Simulator to write
-- progress data for ANY user (not just auth.uid()). This enables realistic
-- bidirectional testing: User A logs 1,200 steps → User B logs 5,005 steps →
-- verify User A sees 5,005 and User B sees 1,200.
--
-- IMPORTANT: These functions are for TESTING ONLY. They are safe because:
--   1. They're SECURITY DEFINER (bypass RLS) — same as all other challenge RPCs
--   2. They require authentication (auth.uid() must exist)
--   3. They verify the target user is a participant in the challenge
--   4. They use the exact same logic as log_challenge_progress
--
-- DEPLOY: Run this in Supabase SQL Editor before running the simulator.
-- ============================================================================

-- Drop existing versions (all known overloads)
DROP FUNCTION IF EXISTS sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION sim_log_progress_for_user(
    p_challenge_id TEXT,
    p_user_id TEXT,         -- The user to log progress FOR (can be anyone in the challenge)
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_timezone TEXT DEFAULT 'UTC',
    p_force BOOLEAN DEFAULT FALSE  -- When TRUE, always SET the value (no GREATEST guard).
                                    -- Used by the cross-type realtime test to ensure
                                    -- every write fires a Postgres NOTIFY → WebSocket event.
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_uuid UUID;
    target_user_uuid UUID;
    challenge_uuid UUID;
    v_progress_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_current_streak INT := 0;
    v_best_streak INT := 0;
    v_check_date DATE;
BEGIN
    -- Must be authenticated
    caller_uuid := auth.uid();
    IF caller_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    target_user_uuid := p_user_id::UUID;

    -- Parse date (timezone-aware default, matching log_challenge_progress)
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    END IF;

    -- Verify the caller is a participant (security: only challenge members can invoke)
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = caller_uuid
    ) THEN
        RAISE EXCEPTION 'Caller is not a participant in this challenge';
    END IF;

    -- Verify the target user is also a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid
    ) THEN
        RAISE EXCEPTION 'Target user is not a participant in this challenge';
    END IF;

    -- Get daily target
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Upsert daily progress for the TARGET user (not caller)
    IF p_force THEN
        -- FORCE MODE: Always write the exact value. Guarantees a DB UPDATE event
        -- fires every time, which is essential for realtime test verification.
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
        ) VALUES (
            challenge_uuid, target_user_uuid, v_progress_date, p_progress_value,
            v_target_hit, p_source, NOW()
        )
        ON CONFLICT (challenge_id, user_id, progress_date)
        DO UPDATE SET
            progress_value = EXCLUDED.progress_value,
            target_hit = EXCLUDED.target_hit,
            source = EXCLUDED.source,
            updated_at = NOW();
    ELSE
        -- NORMAL MODE: Only update if the new value is higher (production behavior)
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
        ) VALUES (
            challenge_uuid, target_user_uuid, v_progress_date, p_progress_value,
            v_target_hit, p_source, NOW()
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

    -- Calculate streak for the target user
    v_check_date := v_progress_date;
    v_current_streak := 0;
    LOOP
        IF EXISTS (
            SELECT 1 FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid
              AND user_id = target_user_uuid
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
    WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid;

    v_best_streak := GREATEST(v_best_streak, v_current_streak);

    -- Update aggregates for the target user
    UPDATE challenge_participants
    SET
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM challenge_daily_progress cdp
            JOIN group_challenges gc ON gc.id = cdp.challenge_id
            WHERE cdp.challenge_id = challenge_uuid
            AND cdp.user_id = target_user_uuid
            AND (cdp.target_hit = TRUE OR cdp.progress_value >= COALESCE(gc.daily_target, 0))
        ),
        current_streak = v_current_streak,
        best_streak = v_best_streak
    WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ============================================================================
-- FUNCTION 2: sim_accept_challenge_for_user
-- Accepts a challenge on behalf of another user (for simulation testing).
-- Also activates the challenge if all participants are now accepted.
-- ============================================================================

DROP FUNCTION IF EXISTS sim_accept_challenge_for_user(TEXT, TEXT);

CREATE OR REPLACE FUNCTION sim_accept_challenge_for_user(
    p_challenge_id TEXT,
    p_user_id TEXT          -- The user to accept FOR
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    caller_uuid UUID;
    target_user_uuid UUID;
    challenge_uuid UUID;
    v_all_accepted BOOLEAN;
    v_participant_count INT;
    v_accepted_count INT;
BEGIN
    -- Must be authenticated
    caller_uuid := auth.uid();
    IF caller_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    target_user_uuid := p_user_id::UUID;

    -- Verify the caller is a participant (security)
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = caller_uuid
    ) THEN
        RAISE EXCEPTION 'Caller is not a participant in this challenge';
    END IF;

    -- Verify the target user is a pending participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid AND status = 'pending'
    ) THEN
        -- Already accepted or doesn't exist
        RETURN TRUE;
    END IF;

    -- Accept the challenge for the target user
    UPDATE challenge_participants
    SET status = 'accepted'
    WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid;

    -- Check if ALL participants are now accepted
    SELECT COUNT(*), COUNT(*) FILTER (WHERE status = 'accepted')
    INTO v_participant_count, v_accepted_count
    FROM challenge_participants
    WHERE challenge_id = challenge_uuid;

    v_all_accepted := (v_participant_count = v_accepted_count AND v_participant_count > 0);

    -- If all accepted, activate the challenge
    IF v_all_accepted THEN
        UPDATE group_challenges
        SET status = 'active'
        WHERE id = challenge_uuid AND status = 'pending';
    END IF;

    RETURN v_all_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION sim_accept_challenge_for_user(TEXT, TEXT) TO authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ sim_log_progress_for_user function created';
    RAISE NOTICE '✅ sim_accept_challenge_for_user function created';
    RAISE NOTICE '';
    RAISE NOTICE 'Available simulator helpers:';
    RAISE NOTICE '  sim_log_progress_for_user(challenge_id, user_id, progress, date, source, timezone)';
    RAISE NOTICE '  sim_accept_challenge_for_user(challenge_id, user_id)';
END $$;
