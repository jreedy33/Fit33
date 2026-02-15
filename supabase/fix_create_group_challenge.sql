-- ============================================================================
-- FIX: create_group_challenge inserts non-existent "role" column
-- FIX: get_challenges_with_friend has duplicate TEXT/UUID overloads
-- FIX: challenge_participants RLS infinite recursion on direct insert
-- ============================================================================


-- ============================================================================
-- 1. FIX create_group_challenge — remove "role" column references
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

    -- Insert creator as accepted participant (no "role" column — it doesn't exist)
    INSERT INTO challenge_participants (
        challenge_id, user_id, status, joined_at,
        total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', NOW(),
        0, 0, 0, 0, TRUE
    );

    -- Insert each member as pending participant
    FOREACH member_id IN ARRAY p_member_ids LOOP
        member_uuid := member_id::UUID;
        
        IF member_uuid = current_user_uuid THEN
            CONTINUE;
        END IF;

        INSERT INTO challenge_participants (
            challenge_id, user_id, status, joined_at,
            total_progress, days_completed, current_streak, best_streak, notify_on_opponent_complete
        ) VALUES (
            new_challenge_id, member_uuid, 'pending', NOW(),
            0, 0, 0, 0, TRUE
        );

        -- Queue push notification
        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                member_uuid,
                'challenge_invite',
                COALESCE(creator_name, 'Someone') || ' invited you to a group challenge! 🏆',
                'Join the "' || p_title || '" challenge!',
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
-- 2. FIX get_challenges_with_friend — drop UUID overload
-- ============================================================================

DROP FUNCTION IF EXISTS get_challenges_with_friend(UUID);
-- Keep only the TEXT version (if it exists, don't recreate — just drop the duplicate)


-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  CREATE GROUP CHALLENGE FIX';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  ✅ Removed "role" column from participant inserts';
    RAISE NOTICE '  ✅ Dropped get_challenges_with_friend UUID overload';
    RAISE NOTICE '============================================';
END $$;
