-- ============================================================================
-- CHALLENGE SYSTEM RPC FUNCTIONS
-- ============================================================================
-- These functions power the entire challenge system in Fit33.
-- Deploy to Supabase SQL Editor to fix challenge creation and all related features.
--
-- CRITICAL FIX: The create_challenge function was either missing or broken,
-- causing FK violation: challenge_participants.challenge_id -> group_challenges.id
-- The fix ensures group_challenges row is created FIRST, then participants.
-- ============================================================================

-- ============================================================================
-- FUNCTION 1: create_challenge (1v1)
-- Creates a challenge between the authenticated user and an opponent.
-- Inserts into group_challenges FIRST, then challenge_participants.
-- Returns the challenge UUID.
-- ============================================================================
DROP FUNCTION IF EXISTS create_challenge(UUID, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT);
DROP FUNCTION IF EXISTS create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT);

CREATE OR REPLACE FUNCTION create_challenge(
    p_opponent_id TEXT,
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_daily_target INT DEFAULT NULL,
    p_total_target INT DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date TEXT DEFAULT NULL,
    p_duration_days INT DEFAULT 7
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
    -- Step 1: Get the authenticated user
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Step 2: Parse opponent ID
    opponent_uuid := p_opponent_id::UUID;

    -- Step 3: Validate opponent exists
    IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = opponent_uuid) THEN
        RAISE EXCEPTION 'Opponent not found: %', p_opponent_id;
    END IF;

    -- Step 4: Cannot challenge yourself
    IF current_user_uuid = opponent_uuid THEN
        RAISE EXCEPTION 'Cannot challenge yourself';
    END IF;

    -- Step 5: Calculate dates
    IF p_start_date IS NOT NULL AND p_start_date != '' THEN
        actual_start_date := p_start_date::DATE;
    ELSE
        actual_start_date := CURRENT_DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    -- Step 6: Get creator info for notification
    SELECT name, username INTO creator_name, creator_username
    FROM user_profiles
    WHERE id = current_user_uuid;

    -- Step 7: INSERT into group_challenges FIRST (critical - FK depends on this)
    INSERT INTO group_challenges (
        id,
        created_by,
        challenge_type,
        title,
        description,
        mode,
        daily_target,
        total_target,
        target_unit,
        start_date,
        end_date,
        duration_days,
        status,
        created_at
    ) VALUES (
        gen_random_uuid(),
        current_user_uuid,
        p_challenge_type,
        p_title,
        p_description,
        CASE 
            WHEN p_title LIKE '🤝%' THEN 'accountability'
            ELSE 'competition'
        END,
        p_daily_target,
        p_total_target,
        p_target_unit,
        actual_start_date,
        actual_end_date,
        p_duration_days,
        'pending',
        NOW()
    )
    RETURNING id INTO new_challenge_id;

    -- Verify the challenge was created (belt-and-suspenders)
    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create challenge record';
    END IF;

    -- Step 8: Insert creator as participant (status = 'accepted' since they created it)
    INSERT INTO challenge_participants (
        challenge_id,
        user_id,
        status,
        role,
        joined_at,
        total_progress,
        days_completed,
        current_streak,
        best_streak,
        notify_on_opponent_complete
    ) VALUES (
        new_challenge_id,
        current_user_uuid,
        'accepted',
        'creator',
        NOW(),
        0,
        0,
        0,
        0,
        TRUE
    );

    -- Step 9: Insert opponent as participant (status = 'pending' until they accept)
    INSERT INTO challenge_participants (
        challenge_id,
        user_id,
        status,
        role,
        joined_at,
        total_progress,
        days_completed,
        current_streak,
        best_streak,
        notify_on_opponent_complete
    ) VALUES (
        new_challenge_id,
        opponent_uuid,
        'pending',
        'opponent',
        NOW(),
        0,
        0,
        0,
        0,
        TRUE
    );

    -- Step 10: Queue push notification to opponent
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data,
            status,
            created_at
        ) VALUES (
            opponent_uuid,
            'challenge_invite',
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
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        -- Don't fail the whole challenge creation if notification fails
        RAISE WARNING 'Failed to queue notification: %', SQLERRM;
    END;

    RETURN new_challenge_id;
END;
$$;

COMMENT ON FUNCTION create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT) IS
    'Creates a 1v1 challenge. Inserts into group_challenges first, then challenge_participants. Returns challenge UUID.';

GRANT EXECUTE ON FUNCTION create_challenge(TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT) TO authenticated;


-- ============================================================================
-- FUNCTION 2: create_group_challenge
-- Creates a group challenge with multiple members.
-- ============================================================================
DROP FUNCTION IF EXISTS create_group_challenge(TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT);

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
    p_duration_days INT DEFAULT 7
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
        actual_start_date := CURRENT_DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    SELECT name INTO creator_name FROM user_profiles WHERE id = current_user_uuid;

    -- Create the challenge
    INSERT INTO group_challenges (
        id, created_by, challenge_type, title, description, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, created_at
    ) VALUES (
        gen_random_uuid(), current_user_uuid, p_challenge_type, p_title, p_description,
        COALESCE(p_mode, 'competition'),
        p_daily_target, p_total_target, p_target_unit,
        actual_start_date, actual_end_date, p_duration_days, 'pending', NOW()
    )
    RETURNING id INTO new_challenge_id;

    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create group challenge';
    END IF;

    -- Insert creator as accepted participant
    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', 'creator', NOW(),
        0, 0, 0, 0, TRUE
    );

    -- Insert each member as pending participant
    FOREACH member_id IN ARRAY p_member_ids LOOP
        member_uuid := member_id::UUID;
        
        -- Skip if member is the creator (shouldn't happen but be safe)
        IF member_uuid = current_user_uuid THEN
            CONTINUE;
        END IF;

        INSERT INTO challenge_participants (
            challenge_id, user_id, status, role, joined_at,
            total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
        ) VALUES (
            new_challenge_id, member_uuid, 'pending', 'member', NOW(),
            0, 0, 0, 0, TRUE
        );

        -- Queue push notification
        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                member_uuid,
                'challenge_invite',
                'Group Challenge Invite 🏆',
                COALESCE(creator_name, 'Someone') || ' invited you to "' || p_title || '"',
                jsonb_build_object(
                    'type', 'challenge_invite',
                    'challenge_id', new_challenge_id::TEXT,
                    'from_user_id', current_user_uuid::TEXT,
                    'from_user_name', COALESCE(creator_name, 'Someone'),
                    'challenge_type', p_challenge_type,
                    'challenge_title', p_title
                ),
                'pending',
                NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to queue notification for member %: %', member_uuid, SQLERRM;
        END;
    END LOOP;

    RETURN new_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_group_challenge(TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT, TEXT, TEXT, INT) TO authenticated;


-- ============================================================================
-- FUNCTION 3: respond_to_challenge
-- Accept or decline a challenge invitation.
-- ============================================================================
DROP FUNCTION IF EXISTS respond_to_challenge(TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION respond_to_challenge(
    p_challenge_id TEXT,
    p_accept BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    challenge_record RECORD;
    opponent_name TEXT;
    opponent_username TEXT;
    creator_id UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Get challenge info
    SELECT gc.*, cp.status as participant_status
    INTO challenge_record
    FROM group_challenges gc
    JOIN challenge_participants cp ON cp.challenge_id = gc.id AND cp.user_id = current_user_uuid
    WHERE gc.id = challenge_uuid;

    IF challenge_record IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or you are not a participant';
    END IF;

    IF challenge_record.participant_status != 'pending' THEN
        RAISE EXCEPTION 'You have already responded to this challenge';
    END IF;

    -- Get responder's name for notification
    SELECT name, username INTO opponent_name, opponent_username
    FROM user_profiles WHERE id = current_user_uuid;

    -- Get creator ID for notification (from group_challenges, NOT challenge_participants.role which doesn't exist)
    SELECT created_by INTO creator_id
    FROM group_challenges
    WHERE id = challenge_uuid;

    IF p_accept THEN
        -- Accept: update participant status
        UPDATE challenge_participants
        SET status = 'accepted'
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

        -- Check if ALL participants have accepted → activate the challenge
        IF NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = challenge_uuid AND status = 'pending'
        ) THEN
            UPDATE group_challenges
            SET status = 'active'
            WHERE id = challenge_uuid;
        END IF;

        -- Notify the creator that the challenge was accepted
        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                creator_id,
                'challenge_accepted',
                'Challenge Accepted! 🎉',
                COALESCE(opponent_name, opponent_username, 'Your opponent') || ' is ready for "' || challenge_record.title || '"',
                jsonb_build_object(
                    'type', 'challenge_accepted',
                    'challenge_id', challenge_uuid::TEXT,
                    'from_user_id', current_user_uuid::TEXT,
                    'from_user_name', COALESCE(opponent_name, opponent_username)
                ),
                'pending',
                NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to queue acceptance notification: %', SQLERRM;
        END;
    ELSE
        -- Decline: update participant status
        UPDATE challenge_participants
        SET status = 'declined'
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

        -- If only 2 participants and one declined, cancel the challenge
        IF (SELECT COUNT(*) FROM challenge_participants WHERE challenge_id = challenge_uuid) <= 2 THEN
            UPDATE group_challenges
            SET status = 'cancelled'
            WHERE id = challenge_uuid;
        END IF;

        -- Notify creator
        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                creator_id,
                'challenge_declined',
                'Challenge Declined',
                COALESCE(opponent_name, opponent_username, 'Your opponent') || ' passed on "' || challenge_record.title || '"',
                jsonb_build_object(
                    'type', 'challenge_declined',
                    'challenge_id', challenge_uuid::TEXT,
                    'from_user_id', current_user_uuid::TEXT,
                    'from_user_name', COALESCE(opponent_name, opponent_username)
                ),
                'pending',
                NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to queue decline notification: %', SQLERRM;
        END;
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION respond_to_challenge(TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- FUNCTION 4: cancel_challenge
-- Cancel a challenge (works for both pending and active).
-- ============================================================================
DROP FUNCTION IF EXISTS cancel_challenge(TEXT);

CREATE OR REPLACE FUNCTION cancel_challenge(
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
    challenge_record RECORD;
    participant RECORD;
    canceller_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Verify user is a participant
    SELECT gc.* INTO challenge_record
    FROM group_challenges gc
    JOIN challenge_participants cp ON cp.challenge_id = gc.id AND cp.user_id = current_user_uuid
    WHERE gc.id = challenge_uuid;

    IF challenge_record IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or you are not a participant';
    END IF;

    -- Get canceller name
    SELECT name INTO canceller_name FROM user_profiles WHERE id = current_user_uuid;

    -- Cancel the challenge
    UPDATE group_challenges
    SET status = 'cancelled'
    WHERE id = challenge_uuid;

    -- Notify all other participants
    FOR participant IN
        SELECT cp.user_id
        FROM challenge_participants cp
        WHERE cp.challenge_id = challenge_uuid
        AND cp.user_id != current_user_uuid
    LOOP
        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                participant.user_id,
                'challenge_cancelled',
                'Challenge Cancelled',
                COALESCE(canceller_name, 'Someone') || ' ended the "' || challenge_record.title || '" challenge',
                jsonb_build_object(
                    'type', 'challenge_cancelled',
                    'challenge_id', challenge_uuid::TEXT,
                    'from_user_id', current_user_uuid::TEXT
                ),
                'pending',
                NOW()
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Failed to queue cancellation notification: %', SQLERRM;
        END;
    END LOOP;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_challenge(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 5: log_challenge_progress
-- Log daily progress for a 1v1 challenge.
-- Uses UPSERT to handle duplicate entries for the same day.
-- Now accepts p_timezone so "today" is computed in the user's local timezone,
-- matching get_active_challenges which uses (NOW() AT TIME ZONE p_timezone)::DATE.
-- This prevents evening progress (after midnight UTC) from being stored under
-- the wrong date, which caused daily progress to not reset at midnight.
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
    -- This matches get_active_challenges which computes:
    --   today_date := (NOW() AT TIME ZONE p_timezone)::DATE
    -- NOTE: variable is named v_progress_date (not progress_date) to avoid
    -- ambiguity with the column challenge_daily_progress.progress_date.
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

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 6: get_pending_challenge_invites
-- Returns challenges sent TO the current user that are pending.
-- ============================================================================
DROP FUNCTION IF EXISTS get_pending_challenge_invites();

CREATE OR REPLACE FUNCTION get_pending_challenge_invites()
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    creator_id UUID,
    creator_name TEXT,
    creator_username TEXT,
    creator_photo_url TEXT,
    invited_at TIMESTAMPTZ
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
        gc.challenge_type,
        gc.title,
        gc.description,
        CASE 
            WHEN gc.challenge_type = 'steps' THEN '👟'
            WHEN gc.challenge_type = 'walk' THEN '🚶'
            WHEN gc.challenge_type = 'run' THEN '🏃'
            WHEN gc.challenge_type = 'lift' THEN '🏋️'
            WHEN gc.challenge_type = 'workout_streak' THEN '🔥'
            WHEN gc.challenge_type = 'active_minutes' THEN '⏱️'
            ELSE '🏆'
        END AS emoji,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        gc.created_by AS creator_id,
        up.name AS creator_name,
        up.username AS creator_username,
        up.profile_photo_url AS creator_photo_url,
        cp.joined_at AS invited_at
    FROM challenge_participants cp
    JOIN group_challenges gc ON gc.id = cp.challenge_id
    JOIN user_profiles up ON up.id = gc.created_by
    WHERE cp.user_id = current_user_uuid
    AND cp.status = 'pending'
    AND gc.status IN ('pending', 'active')
    ORDER BY cp.joined_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pending_challenge_invites() TO authenticated;


-- ============================================================================
-- FUNCTION 7: get_pending_sent_challenges
-- Returns challenges sent BY the current user that opponent hasn't accepted yet.
-- ============================================================================
DROP FUNCTION IF EXISTS get_pending_sent_challenges();

CREATE OR REPLACE FUNCTION get_pending_sent_challenges()
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    daily_target INT,
    total_target INT,
    target_unit TEXT,
    start_date TEXT,
    end_date TEXT,
    duration_days INT,
    opponent_id UUID,
    opponent_name TEXT,
    opponent_username TEXT,
    opponent_photo_url TEXT,
    sent_at TIMESTAMPTZ
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
        gc.challenge_type,
        gc.title,
        gc.description,
        CASE 
            WHEN gc.challenge_type = 'steps' THEN '👟'
            WHEN gc.challenge_type = 'walk' THEN '🚶'
            WHEN gc.challenge_type = 'run' THEN '🏃'
            WHEN gc.challenge_type = 'lift' THEN '🏋️'
            WHEN gc.challenge_type = 'workout_streak' THEN '🔥'
            WHEN gc.challenge_type = 'active_minutes' THEN '⏱️'
            ELSE '🏆'
        END AS emoji,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        opp.user_id AS opponent_id,
        up.name AS opponent_name,
        up.username AS opponent_username,
        up.profile_photo_url AS opponent_photo_url,
        gc.created_at AS sent_at
    FROM group_challenges gc
    -- Creator is the current user who created the challenge (no 'role' column exists)
    JOIN challenge_participants creator_cp ON creator_cp.challenge_id = gc.id 
        AND creator_cp.user_id = current_user_uuid AND creator_cp.status = 'accepted'
    JOIN challenge_participants opp ON opp.challenge_id = gc.id AND opp.user_id != current_user_uuid
    JOIN user_profiles up ON up.id = opp.user_id
    WHERE gc.status = 'pending'
    AND gc.created_by = current_user_uuid
    AND opp.status = 'pending'
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_pending_sent_challenges() TO authenticated;


-- ============================================================================
-- FUNCTION 8: get_active_challenges (1v1)
-- Returns active challenges with progress data for the challenge widget.
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
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Use timezone-aware current date
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

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
        GREATEST(0, (today_date - gc.start_date)::INT) AS days_elapsed,
        GREATEST(0, (gc.end_date - today_date)::INT) AS days_remaining,
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
    -- My participation
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    -- Opponent participation (only for 1v1 - max 2 participants)
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = gc.id AND opp_cp.user_id != current_user_uuid
    JOIN user_profiles opp_up ON opp_up.id = opp_cp.user_id
    -- My today's progress
    LEFT JOIN challenge_daily_progress my_today 
        ON my_today.challenge_id = gc.id 
        AND my_today.user_id = current_user_uuid 
        AND my_today.progress_date = today_date
    -- Opponent's today's progress
    LEFT JOIN challenge_daily_progress opp_today 
        ON opp_today.challenge_id = gc.id 
        AND opp_today.user_id = opp_cp.user_id 
        AND opp_today.progress_date = today_date
    WHERE gc.status = 'active'
    AND my_cp.status = 'accepted'
    -- Only 1v1 challenges (exactly 2 participants)
    -- Must qualify challenge_participants.challenge_id to avoid ambiguity with RETURNS TABLE column
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) = 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 9: get_active_group_challenges
-- Returns active group challenges (3+ participants) with member details.
-- Now accepts timezone parameter for correct "today" date calculation.
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

    -- Use timezone-aware current date (consistent with get_active_challenges)
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

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
-- FUNCTION 10: accept_group_challenge
-- Accept a group challenge invite. Returns true if all members have accepted.
-- ============================================================================
DROP FUNCTION IF EXISTS accept_group_challenge(TEXT);

CREATE OR REPLACE FUNCTION accept_group_challenge(
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
    all_accepted BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    UPDATE challenge_participants
    SET status = 'accepted'
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid AND status = 'pending';

    -- Check if all participants accepted
    all_accepted := NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND status = 'pending'
    );

    IF all_accepted THEN
        UPDATE group_challenges SET status = 'active' WHERE id = challenge_uuid;
    END IF;

    RETURN all_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_group_challenge(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 11: decline_group_challenge
-- ============================================================================
DROP FUNCTION IF EXISTS decline_group_challenge(TEXT);

CREATE OR REPLACE FUNCTION decline_group_challenge(
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
    remaining_count INT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    -- Remove the declining user
    DELETE FROM challenge_participants
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    -- Check remaining participants
    SELECT COUNT(*) INTO remaining_count
    FROM challenge_participants WHERE challenge_id = challenge_uuid;

    IF remaining_count <= 1 THEN
        -- Only creator left, cancel
        UPDATE group_challenges SET status = 'cancelled' WHERE id = challenge_uuid;
    ELSIF remaining_count = 2 THEN
        -- Exactly 2 left - it's now a 1v1, activate if both accepted
        IF NOT EXISTS (
            SELECT 1 FROM challenge_participants 
            WHERE challenge_id = challenge_uuid AND status = 'pending'
        ) THEN
            UPDATE group_challenges SET status = 'active' WHERE id = challenge_uuid;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION decline_group_challenge(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 12: leave_group_challenge
-- ============================================================================
DROP FUNCTION IF EXISTS leave_group_challenge(TEXT);

CREATE OR REPLACE FUNCTION leave_group_challenge(
    p_challenge_id TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    remaining_count INT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    DELETE FROM challenge_participants
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    SELECT COUNT(*) INTO remaining_count
    FROM challenge_participants WHERE challenge_id = challenge_uuid;

    IF remaining_count <= 1 THEN
        UPDATE group_challenges SET status = 'cancelled' WHERE id = challenge_uuid;
        RETURN 'cancelled';
    ELSIF remaining_count = 2 THEN
        -- Convert to 1v1
        RETURN 'converted';
    ELSE
        RETURN 'left';
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION leave_group_challenge(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 13: cancel_group_challenge
-- ============================================================================
DROP FUNCTION IF EXISTS cancel_group_challenge(TEXT);

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
    challenge_uuid := p_challenge_id::UUID;

    -- Only creator can cancel (check group_challenges.created_by, NOT role column)
    IF NOT EXISTS (
        SELECT 1 FROM group_challenges
        WHERE id = challenge_uuid AND created_by = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'Only the creator can cancel a group challenge';
    END IF;

    UPDATE group_challenges SET status = 'cancelled' WHERE id = challenge_uuid;
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_group_challenge(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 14: nudge_group_challenge_member
-- ============================================================================
DROP FUNCTION IF EXISTS nudge_group_challenge_member(TEXT, TEXT);

CREATE OR REPLACE FUNCTION nudge_group_challenge_member(
    p_challenge_id TEXT,
    p_recipient_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    recipient_uuid UUID;
    sender_name TEXT;
    challenge_title TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    recipient_uuid := p_recipient_id::UUID;

    -- Check if already nudged today
    IF EXISTS (
        SELECT 1 FROM group_challenge_nudges
        WHERE challenge_id = challenge_uuid 
        AND sender_id = current_user_uuid 
        AND recipient_id = recipient_uuid
        AND created_at > CURRENT_DATE
    ) THEN
        RETURN FALSE; -- Already nudged today
    END IF;

    -- Record the nudge (include group_challenge_id for backward compat with old schema)
    INSERT INTO group_challenge_nudges (challenge_id, group_challenge_id, sender_id, recipient_id, created_at)
    VALUES (challenge_uuid, challenge_uuid, current_user_uuid, recipient_uuid, NOW());

    -- Get names
    SELECT name INTO sender_name FROM user_profiles WHERE id = current_user_uuid;
    SELECT title INTO challenge_title FROM group_challenges WHERE id = challenge_uuid;

    -- Queue notification
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            recipient_uuid,
            'challenge_nudge',
            COALESCE(sender_name, 'Someone') || ' nudged you! 👊',
            'Don''t forget your "' || COALESCE(challenge_title, 'challenge') || '" goal today!',
            jsonb_build_object(
                'type', 'challenge_nudge',
                'challenge_id', challenge_uuid::TEXT,
                'from_user_id', current_user_uuid::TEXT
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Nudge recorded even if notification fails
    END;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION nudge_group_challenge_member(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 15: log_group_challenge_progress
-- Now accepts timezone parameter for correct "today" date calculation.
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
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;
    -- Use timezone-aware date (consistent with log_challenge_progress 1v1)
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Get daily target for target_hit tracking
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;
    
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
-- FUNCTION 16: get_challenge_details
-- ============================================================================
DROP FUNCTION IF EXISTS get_challenge_details(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_details(
    p_challenge_id TEXT
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
    status TEXT,
    created_at TIMESTAMPTZ,
    notify_on_opponent_complete BOOLEAN,
    participants JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid := p_challenge_id::UUID;

    RETURN QUERY
    SELECT
        gc.id,
        gc.challenge_type,
        gc.title,
        gc.description,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        gc.duration_days,
        gc.status,
        gc.created_at,
        my_cp.notify_on_opponent_complete,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', cp2.user_id,
                'name', up2.name,
                'username', up2.username,
                'photo_url', up2.profile_photo_url,
                'status', cp2.status,
                'total_progress', COALESCE(cp2.total_progress, 0),
                'days_completed', COALESCE(cp2.days_completed, 0),
                'current_streak', COALESCE(cp2.current_streak, 0),
                'best_streak', COALESCE(cp2.best_streak, 0),
                'is_creator', (cp2.user_id = gc.created_by),
                'daily_progress', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'date', cdp.progress_date::TEXT,
                        'value', cdp.progress_value,
                        'source', cdp.source
                    ) ORDER BY cdp.progress_date)
                    FROM challenge_daily_progress cdp
                    WHERE cdp.challenge_id = gc.id AND cdp.user_id = cp2.user_id
                )
            ))
            FROM challenge_participants cp2
            JOIN user_profiles up2 ON up2.id = cp2.user_id
            WHERE cp2.challenge_id = gc.id
        ) AS participants
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    WHERE gc.id = challenge_uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_details(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 17: toggle_challenge_notification_preference
-- ============================================================================
DROP FUNCTION IF EXISTS toggle_challenge_notification_preference(TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION toggle_challenge_notification_preference(
    p_challenge_id TEXT,
    p_notify BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    UPDATE challenge_participants
    SET notify_on_opponent_complete = p_notify
    WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_challenge_notification_preference(TEXT, BOOLEAN) TO authenticated;


-- ============================================================================
-- FUNCTION 18: get_challenges_with_friend
-- ============================================================================
DROP FUNCTION IF EXISTS get_challenges_with_friend(TEXT);

CREATE OR REPLACE FUNCTION get_challenges_with_friend(
    p_friend_id TEXT
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    status TEXT,
    start_date TEXT,
    end_date TEXT,
    my_progress INT,
    friend_progress INT,
    am_winning BOOLEAN,
    daily_target INT,
    target_unit TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    friend_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    friend_uuid := p_friend_id::UUID;

    RETURN QUERY
    SELECT
        gc.id AS challenge_id,
        gc.challenge_type,
        gc.title,
        gc.status,
        gc.start_date::TEXT,
        gc.end_date::TEXT,
        COALESCE(my_cp.total_progress, 0)::INT AS my_progress,
        COALESCE(friend_cp.total_progress, 0)::INT AS friend_progress,
        (COALESCE(my_cp.total_progress, 0) >= COALESCE(friend_cp.total_progress, 0)) AS am_winning,
        gc.daily_target,
        gc.target_unit
    FROM group_challenges gc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    JOIN challenge_participants friend_cp ON friend_cp.challenge_id = gc.id AND friend_cp.user_id = friend_uuid
    WHERE gc.status IN ('active', 'completed')
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenges_with_friend(TEXT) TO authenticated;


-- ============================================================================
-- FUNCTION 19: get_challenge_templates
-- ============================================================================
DROP FUNCTION IF EXISTS get_challenge_templates();

CREATE OR REPLACE FUNCTION get_challenge_templates()
RETURNS TABLE (
    id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    default_daily_target INT,
    default_duration_days INT,
    target_unit TEXT,
    is_featured BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- If challenge_templates table exists, return from it
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'challenge_templates') THEN
        RETURN QUERY
        SELECT 
            ct.id,
            ct.challenge_type,
            ct.title,
            ct.description,
            ct.emoji,
            ct.default_daily_target,
            ct.default_duration_days,
            ct.target_unit,
            ct.is_featured
        FROM challenge_templates ct
        ORDER BY ct.is_featured DESC, ct.title;
    ELSE
        -- Return hardcoded defaults if table doesn't exist
        RETURN QUERY
        SELECT * FROM (VALUES
            (gen_random_uuid(), 'steps'::TEXT, '10K Steps Daily'::TEXT, 'Walk 10,000 steps every day'::TEXT, '👟'::TEXT, 10000, 7, 'steps'::TEXT, TRUE),
            (gen_random_uuid(), 'run'::TEXT, '5K Runner'::TEXT, 'Run 5 kilometers'::TEXT, '🏃'::TEXT, 5, 7, 'km'::TEXT, TRUE),
            (gen_random_uuid(), 'lift'::TEXT, 'Gym Warrior'::TEXT, 'Hit the gym every day'::TEXT, '🏋️'::TEXT, 1, 7, 'workouts'::TEXT, TRUE),
            (gen_random_uuid(), 'active_minutes'::TEXT, '30 Min Active'::TEXT, '30 minutes of activity daily'::TEXT, '⏱️'::TEXT, 30, 7, 'minutes'::TEXT, FALSE),
            (gen_random_uuid(), 'walk'::TEXT, 'Daily Walker'::TEXT, 'Walk 30 minutes every day'::TEXT, '🚶'::TEXT, 30, 7, 'minutes'::TEXT, FALSE)
        ) AS t(id, challenge_type, title, description, emoji, default_daily_target, default_duration_days, target_unit, is_featured);
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_templates() TO authenticated;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ CHALLENGE RPC FUNCTIONS DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Functions created/updated:';
    RAISE NOTICE '   1.  create_challenge          - Create 1v1 challenge';
    RAISE NOTICE '   2.  create_group_challenge     - Create group challenge';
    RAISE NOTICE '   3.  respond_to_challenge       - Accept/decline challenge';
    RAISE NOTICE '   4.  cancel_challenge           - Cancel a challenge';
    RAISE NOTICE '   5.  log_challenge_progress     - Log daily progress';
    RAISE NOTICE '   6.  get_pending_challenge_invites - Get incoming invites';
    RAISE NOTICE '   7.  get_pending_sent_challenges   - Get sent challenges';
    RAISE NOTICE '   8.  get_active_challenges      - Get active 1v1 challenges';
    RAISE NOTICE '   9.  get_active_group_challenges- Get group challenges';
    RAISE NOTICE '   10. accept_group_challenge     - Accept group invite';
    RAISE NOTICE '   11. decline_group_challenge    - Decline group invite';
    RAISE NOTICE '   12. leave_group_challenge      - Leave group challenge';
    RAISE NOTICE '   13. cancel_group_challenge     - Cancel group challenge';
    RAISE NOTICE '   14. nudge_group_challenge_member - Nudge pending member';
    RAISE NOTICE '   15. log_group_challenge_progress - Log group progress';
    RAISE NOTICE '   16. get_challenge_details      - Get challenge details';
    RAISE NOTICE '   17. toggle_challenge_notification_preference';
    RAISE NOTICE '   18. get_challenges_with_friend - History with friend';
    RAISE NOTICE '   19. get_challenge_templates    - Get templates';
    RAISE NOTICE '';
    RAISE NOTICE '🔑 KEY FIX: create_challenge now properly inserts into';
    RAISE NOTICE '   group_challenges FIRST, then challenge_participants,';
    RAISE NOTICE '   preventing the FK constraint violation.';
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
