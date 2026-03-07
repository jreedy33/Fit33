-- ============================================================================
-- FIX C-6: Race Condition in Challenge Creation (Non-Atomic)
-- ============================================================================
-- Date: March 6, 2026
-- Source: MASTER_TODO.md item C-6
--
-- ROOT CAUSE:
--   The create_challenge and create_group_challenge RPCs do NOT accept the
--   p_timezone parameter, but the iOS app sends it. PostgREST fails to match
--   the function signature, causing the RPC call to fail EVERY TIME. The app
--   then falls back to non-atomic direct table inserts (2-3 separate HTTP
--   requests). If the connection drops between requests, orphaned records are
--   created in group_challenges with no corresponding challenge_participants.
--
-- FIX:
--   1. Add p_timezone parameter to create_challenge and create_group_challenge
--      RPCs so they match the iOS client's call signature
--   2. Store the timezone as creator_timezone on the challenge row
--   3. Add orphan cleanup function as a safety net
--
-- RESULT:
--   The RPCs will now succeed (no parameter mismatch), so the app uses the
--   atomic plpgsql transaction path instead of the non-atomic fallback.
--   The fallback still exists as a safety net but should rarely trigger.
--
-- RUN IN: Supabase Dashboard → SQL Editor
-- ============================================================================


-- ============================================================================
-- PART 1: Fix create_challenge — Add p_timezone parameter
-- ============================================================================
-- Drop old signatures to avoid overload conflicts
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
        actual_start_date := CURRENT_DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    SELECT name, username INTO creator_name, creator_username
    FROM user_profiles
    WHERE id = current_user_uuid;

    INSERT INTO group_challenges (
        id, created_by, challenge_type, title, description, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, creator_timezone, created_at
    ) VALUES (
        gen_random_uuid(), current_user_uuid, p_challenge_type, p_title, p_description,
        CASE WHEN p_title LIKE '🤝%' THEN 'accountability' ELSE 'competition' END,
        p_daily_target, p_total_target, p_target_unit,
        actual_start_date, actual_end_date, p_duration_days, 'pending',
        COALESCE(p_timezone, 'UTC'), NOW()
    )
    RETURNING id INTO new_challenge_id;

    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create challenge record';
    END IF;

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak,
        notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', 'creator', NOW(),
        0, 0, 0, 0, TRUE
    );

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak,
        notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, opponent_uuid, 'pending', 'opponent', NOW(),
        0, 0, 0, 0, TRUE
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
-- PART 2: Fix create_group_challenge — Add p_timezone parameter
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
        actual_start_date := CURRENT_DATE;
    END IF;
    actual_end_date := actual_start_date + (p_duration_days || ' days')::INTERVAL;

    SELECT name INTO creator_name FROM user_profiles WHERE id = current_user_uuid;

    INSERT INTO group_challenges (
        id, created_by, challenge_type, title, description, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, creator_timezone, created_at
    ) VALUES (
        gen_random_uuid(), current_user_uuid, p_challenge_type, p_title, p_description,
        COALESCE(p_mode, 'competition'),
        p_daily_target, p_total_target, p_target_unit,
        actual_start_date, actual_end_date, p_duration_days, 'pending',
        COALESCE(p_timezone, 'UTC'), NOW()
    )
    RETURNING id INTO new_challenge_id;

    IF new_challenge_id IS NULL THEN
        RAISE EXCEPTION 'Failed to create group challenge';
    END IF;

    INSERT INTO challenge_participants (
        challenge_id, user_id, status, role, joined_at,
        total_progress, days_completed, current_streak, best_streak,
        notify_on_opponent_complete
    ) VALUES (
        new_challenge_id, current_user_uuid, 'accepted', 'creator', NOW(),
        0, 0, 0, 0, TRUE
    );

    FOREACH member_id IN ARRAY p_member_ids LOOP
        member_uuid := member_id::UUID;
        IF member_uuid = current_user_uuid THEN
            CONTINUE;
        END IF;

        INSERT INTO challenge_participants (
            challenge_id, user_id, status, role, joined_at,
            total_progress, days_completed, current_streak, best_streak,
            notify_on_opponent_complete
        ) VALUES (
            new_challenge_id, member_uuid, 'pending', 'member', NOW(),
            0, 0, 0, 0, TRUE
        );

        BEGIN
            INSERT INTO push_notification_queue (
                recipient_user_id, notification_type, title, body, data, status, created_at
            ) VALUES (
                member_uuid, 'challenge_invite',
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
-- PART 3: Orphan Cleanup Function
-- ============================================================================
-- Safety net: finds and removes group_challenges rows that have no
-- corresponding challenge_participants. These are orphans created by
-- failed non-atomic direct inserts (connection drop after challenge INSERT
-- but before participants INSERT).
--
-- Can be called manually or scheduled as a cron job.
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_orphaned_challenges()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INT;
BEGIN
    WITH orphans AS (
        DELETE FROM group_challenges gc
        WHERE NOT EXISTS (
            SELECT 1 FROM challenge_participants cp
            WHERE cp.challenge_id = gc.id
        )
        AND gc.created_at < NOW() - INTERVAL '5 minutes'
        RETURNING gc.id
    )
    SELECT COUNT(*) INTO deleted_count FROM orphans;

    IF deleted_count > 0 THEN
        RAISE NOTICE 'Cleaned up % orphaned challenge(s)', deleted_count;
    END IF;

    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_orphaned_challenges() TO service_role;


-- ============================================================================
-- PART 4: Verification
-- ============================================================================

DO $$
DECLARE
    v_create_challenge_params TEXT;
    v_create_group_params TEXT;
    v_cleanup_exists BOOLEAN;
BEGIN
    SELECT string_agg(p.parameter_name, ', ' ORDER BY p.ordinal_position)
    INTO v_create_challenge_params
    FROM information_schema.parameters p
    WHERE p.specific_schema = 'public'
      AND p.specific_name LIKE 'create_challenge%'
      AND p.parameter_mode = 'IN'
      AND p.parameter_name IS NOT NULL;

    SELECT string_agg(p.parameter_name, ', ' ORDER BY p.ordinal_position)
    INTO v_create_group_params
    FROM information_schema.parameters p
    WHERE p.specific_schema = 'public'
      AND p.specific_name LIKE 'create_group_challenge%'
      AND p.parameter_mode = 'IN'
      AND p.parameter_name IS NOT NULL;

    SELECT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'cleanup_orphaned_challenges'
    ) INTO v_cleanup_exists;

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  C-6 ATOMICITY FIX — VERIFICATION';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '  create_challenge params: %', v_create_challenge_params;
    RAISE NOTICE '  create_group_challenge params: %', v_create_group_params;
    RAISE NOTICE '';

    IF v_create_challenge_params LIKE '%p_timezone%' THEN
        RAISE NOTICE '  ✅ create_challenge accepts p_timezone';
    ELSE
        RAISE NOTICE '  ❌ create_challenge MISSING p_timezone';
    END IF;

    IF v_create_group_params LIKE '%p_timezone%' THEN
        RAISE NOTICE '  ✅ create_group_challenge accepts p_timezone';
    ELSE
        RAISE NOTICE '  ❌ create_group_challenge MISSING p_timezone';
    END IF;

    IF v_cleanup_exists THEN
        RAISE NOTICE '  ✅ cleanup_orphaned_challenges function exists';
    ELSE
        RAISE NOTICE '  ❌ cleanup_orphaned_challenges not found';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '  iOS RPCs will now match → atomic path used → no orphans';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
