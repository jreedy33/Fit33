-- ============================================================================
-- FIX: Challenge Midnight Reset (Creator's Timezone)
-- ============================================================================
-- Problem: Challenge daily progress doesn't cleanly reset at midnight because:
--   1. No stored timezone per challenge — each client uses its own timezone
--   2. log_challenge_progress falls back to UTC CURRENT_DATE
--   3. get_active_challenges uses the CALLER's timezone for both participants
--
-- Fix: Store the challenge creator's timezone and use it consistently:
--   - All progress dates are calculated using the challenge's timezone
--   - Both participants see the same "today" boundary (creator's midnight)
--   - Existing challenges without a timezone default to the caller's timezone
-- ============================================================================

-- Step 1a: Add creator_timezone column to group_challenges
-- Default is NULL (not 'UTC') so existing challenges fall through the COALESCE
-- chain to use the caller's timezone: COALESCE(gc.creator_timezone, p_timezone, 'UTC')
-- New challenges will explicitly store the creator's timezone at creation time.
ALTER TABLE group_challenges
ADD COLUMN IF NOT EXISTS creator_timezone TEXT DEFAULT NULL;

-- Step 1b: Drop the overly-restrictive source CHECK constraint on challenge_daily_progress
-- This constraint blocks valid sources (e.g. simulator, future integrations).
-- The source column is free-text; allowed values are enforced by app logic, not DB.
ALTER TABLE challenge_daily_progress
DROP CONSTRAINT IF EXISTS challenge_daily_progress_source_check;


-- ============================================================================
-- Step 2: Update create_challenge to store creator's timezone
-- ============================================================================
DROP FUNCTION IF EXISTS create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION create_challenge(
    p_opponent_id TEXT,
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_daily_target INT DEFAULT NULL,
    p_total_target INT DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date TEXT DEFAULT NULL,
    p_duration_days INT DEFAULT 7,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    opponent_uuid UUID;
    new_challenge_id UUID;
    actual_start_date DATE;
    actual_end_date DATE;
    creator_name TEXT;
    creator_username TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    opponent_uuid := p_opponent_id::UUID;

    IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = opponent_uuid) THEN
        RAISE EXCEPTION 'Opponent not found: %', p_opponent_id;
    END IF;

    IF current_user_uuid = opponent_uuid THEN
        RAISE EXCEPTION 'Cannot challenge yourself';
    END IF;

    IF p_start_date IS NOT NULL AND p_start_date != '' THEN
        actual_start_date := p_start_date::DATE;
    ELSE
        actual_start_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    SELECT name, username INTO creator_name, creator_username
    FROM user_profiles
    WHERE id = current_user_uuid;

    INSERT INTO group_challenges (
        id, created_by, challenge_type, title, description, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, created_at,
        creator_timezone
    ) VALUES (
        gen_random_uuid(), current_user_uuid, p_challenge_type, p_title, p_description,
        CASE WHEN p_title LIKE '🤝%' THEN 'accountability' ELSE 'competition' END,
        p_daily_target, p_total_target, p_target_unit,
        actual_start_date, actual_end_date, p_duration_days, 'pending', NOW(),
        COALESCE(NULLIF(p_timezone, ''), 'UTC')
    )
    RETURNING id INTO new_challenge_id;

    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create challenge record';
    END IF;

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', 'creator', NOW(), 0, 0, 0, 0, TRUE
    );

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, opponent_uuid, 'pending', 'opponent', NOW(), 0, 0, 0, 0, TRUE
    );

    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            opponent_uuid, 'challenge_invite',
            COALESCE(creator_name, creator_username, 'Someone') || ' challenged you! 🏆',
            'Accept the "' || p_title || '" challenge!',
            jsonb_build_object(
                'type', 'challenge_invite',
                'challenge_id', new_challenge_id::TEXT,
                'from_user_id', current_user_uuid::TEXT,
                'from_user_name', COALESCE(creator_name, creator_username),
                'challenge_type', p_challenge_type,
                'challenge_title', p_title
            ),
            'pending', NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to queue notification: %', SQLERRM;
    END;

    RETURN new_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- Step 3: Update create_group_challenge to store creator's timezone
-- ============================================================================
DROP FUNCTION IF EXISTS create_group_challenge(TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS create_group_challenge(TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION create_group_challenge(
    p_member_ids TEXT[],
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_mode TEXT DEFAULT 'competition',
    p_daily_target INT DEFAULT NULL,
    p_total_target INT DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date TEXT DEFAULT NULL,
    p_duration_days INT DEFAULT 7,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_challenge_id UUID;
    actual_start_date DATE;
    actual_end_date DATE;
    member_id TEXT;
    member_uuid UUID;
    creator_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_start_date IS NOT NULL AND p_start_date != '' THEN
        actual_start_date := p_start_date::DATE;
    ELSE
        actual_start_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    SELECT name INTO creator_name FROM user_profiles WHERE id = current_user_uuid;

    INSERT INTO group_challenges (
        id, created_by, challenge_type, title, description, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, created_at,
        creator_timezone
    ) VALUES (
        gen_random_uuid(), current_user_uuid, p_challenge_type, p_title, p_description,
        COALESCE(p_mode, 'competition'),
        p_daily_target, p_total_target, p_target_unit,
        actual_start_date, actual_end_date, p_duration_days, 'pending', NOW(),
        COALESCE(NULLIF(p_timezone, ''), 'UTC')
    )
    RETURNING id INTO new_challenge_id;

    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create group challenge';
    END IF;

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', 'creator', NOW(), 0, 0, 0, 0, TRUE
    );

    FOREACH member_id IN ARRAY p_member_ids LOOP
        member_uuid := member_id::UUID;
        IF member_uuid = current_user_uuid THEN CONTINUE; END IF;

        INSERT INTO challenge_participants (
            challenge_id, user_id, status, role, joined_at,
            total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
        ) VALUES (
            new_challenge_id, member_uuid, 'pending', 'member', NOW(), 0, 0, 0, 0, TRUE
        );

        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                member_uuid, 'challenge_invite', 'Group Challenge Invite 🏆',
                COALESCE(creator_name, 'Someone') || ' invited you to "' || p_title || '"',
                jsonb_build_object(
                    'type', 'challenge_invite',
                    'challenge_id', new_challenge_id::TEXT,
                    'from_user_id', current_user_uuid::TEXT,
                    'from_user_name', COALESCE(creator_name, 'Someone'),
                    'challenge_type', p_challenge_type,
                    'challenge_title', p_title
                ),
                'pending', NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to queue notification for member %: %', member_uuid, SQLERRM;
        END;
    END LOOP;

    RETURN new_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_group_challenge(TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- Step 4: Update log_challenge_progress to use challenge's timezone
-- ============================================================================
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id TEXT,
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_workout_id TEXT DEFAULT NULL,
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
    -- NOTE: Named v_progress_date (not progress_date) to avoid ambiguity
    -- with the column challenge_daily_progress.progress_date
    v_progress_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_challenge_tz TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Get the challenge's timezone and daily target
    SELECT COALESCE(creator_timezone, NULLIF(p_timezone, ''), 'UTC'), daily_target
    INTO v_challenge_tz, v_daily_target
    FROM group_challenges WHERE id = challenge_uuid;

    -- Use the challenge's timezone to determine "today"
    -- If an explicit date is provided (e.g. from simulator), use it
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_challenge_tz)::DATE;
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Verify user is a participant in this challenge
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    -- Upsert daily progress (update if higher, don't decrease)
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
        progress_value = GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value),
        target_hit = CASE
            WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
            THEN EXCLUDED.target_hit
            ELSE challenge_daily_progress.target_hit
        END,
        source = EXCLUDED.source,
        updated_at = NOW()
    WHERE EXCLUDED.progress_value > challenge_daily_progress.progress_value;

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
            AND cdp.progress_value >= COALESCE(gc.daily_target, 0)
        )
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- Step 5: Update get_active_challenges to use challenge's timezone
-- Each challenge uses its OWN creator_timezone for "today" calculations.
-- This ensures both participants see the same daily boundary.
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

    -- NOTE: Each challenge uses its own creator_timezone for "today" date.
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
-- Step 6: Update log_group_challenge_progress to use challenge's timezone
-- ============================================================================
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

GRANT EXECUTE ON FUNCTION log_group_challenge_progress(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- Step 7: Update get_active_group_challenges to use challenge's timezone
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
-- Step 8: Update sim_log_progress_for_user to use challenge's timezone
-- ============================================================================
DROP FUNCTION IF EXISTS sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION sim_log_progress_for_user(
    p_challenge_id TEXT,
    p_user_id TEXT,
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_timezone TEXT DEFAULT 'UTC'
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
    v_challenge_tz TEXT;
BEGIN
    caller_uuid := auth.uid();
    IF caller_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    target_user_uuid := p_user_id::UUID;

    -- Get challenge's timezone and daily target
    SELECT COALESCE(creator_timezone, NULLIF(p_timezone, ''), 'UTC'), daily_target
    INTO v_challenge_tz, v_daily_target
    FROM group_challenges WHERE id = challenge_uuid;

    -- Parse date (explicit date for simulator, otherwise use challenge timezone)
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_challenge_tz)::DATE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = caller_uuid
    ) THEN
        RAISE EXCEPTION 'Caller is not a participant in this challenge';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = target_user_uuid
    ) THEN
        RAISE EXCEPTION 'Target user is not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

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

    -- Calculate streak
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

GRANT EXECUTE ON FUNCTION sim_log_progress_for_user(TEXT, TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ CHALLENGE MIDNIGHT RESET FIX DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Changes:';
    RAISE NOTICE '   1. Added creator_timezone column to group_challenges';
    RAISE NOTICE '   2. create_challenge now stores creator timezone';
    RAISE NOTICE '   3. create_group_challenge now stores creator timezone';
    RAISE NOTICE '   4. log_challenge_progress uses challenge timezone for "today"';
    RAISE NOTICE '   5. get_active_challenges uses challenge timezone per-challenge';
    RAISE NOTICE '   6. log_group_challenge_progress uses challenge timezone';
    RAISE NOTICE '   7. get_active_group_challenges uses challenge timezone';
    RAISE NOTICE '   8. sim_log_progress_for_user uses challenge timezone';
    RAISE NOTICE '';
    RAISE NOTICE '🔑 KEY: All participants now see the same daily boundary';
    RAISE NOTICE '   (midnight in the challenge creators timezone).';
    RAISE NOTICE '   Existing challenges without a stored timezone fall back';
    RAISE NOTICE '   to the callers timezone (p_timezone param).';
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
