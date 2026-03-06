-- ============================================================================
-- FIX: Add allow_decrease support to community & private challenge progress RPCs
-- ============================================================================
-- Problem: When a user removes a meal (protein goes from 89 → 60), the GREATEST()
-- clause in log_community_challenge_progress and log_private_challenge_progress
-- prevents the value from decreasing. This means removed meals are not reflected.
-- 
-- Solution: Add p_allow_decrease BOOLEAN parameter (default FALSE) that bypasses
-- GREATEST() when TRUE, allowing the value to decrease.
-- ============================================================================

-- ── Community Challenge Progress ──

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
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

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


-- ── Private Challenge Progress ──

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
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

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
