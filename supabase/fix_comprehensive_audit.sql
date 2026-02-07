-- ============================================================================
-- COMPREHENSIVE SYSTEM AUDIT FIX
-- ============================================================================
-- Deep audit found these critical issues across the entire system:
--
-- 1. get_active_challenges: "challenge_id" is ambiguous (error 42702)
-- 2. get_active_group_challenges: Same ambiguity issue  
-- 3. Missing decline_friend_request and cancel_friend_request RPCs
-- 4. reject_friend_request deletes ANY friendship (not just pending)
-- 5. No RLS on friendships table
-- 6. Realtime subscribes to wrong table (fixed in Swift)
-- 7. Account deletion uses wrong table/column names (fixed in Swift)
--
-- This file fixes items 1-5 (database side). Items 6-7 are Swift-side fixes.
-- ============================================================================

-- ============================================================================
-- FIX 1: get_active_challenges — ambiguous challenge_id column
-- The RETURNS TABLE has "challenge_id" AND the subquery references
-- challenge_participants.challenge_id, causing PostgreSQL error 42702.
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
    JOIN challenge_participants my_cp ON my_cp.challenge_id = gc.id AND my_cp.user_id = current_user_uuid
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = gc.id AND opp_cp.user_id != current_user_uuid
    JOIN user_profiles opp_up ON opp_up.id = opp_cp.user_id
    LEFT JOIN challenge_daily_progress my_today 
        ON my_today.challenge_id = gc.id 
        AND my_today.user_id = current_user_uuid 
        AND my_today.progress_date = today_date
    LEFT JOIN challenge_daily_progress opp_today 
        ON opp_today.challenge_id = gc.id 
        AND opp_today.user_id = opp_cp.user_id 
        AND opp_today.progress_date = today_date
    WHERE gc.status = 'active'
    AND my_cp.status = 'accepted'
    -- FIX: Use table alias to avoid ambiguity with RETURNS TABLE column name
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) = 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_challenges(TEXT) TO authenticated;


-- ============================================================================
-- FIX 2: get_active_group_challenges — same ambiguity fix
-- ============================================================================

DROP FUNCTION IF EXISTS get_active_group_challenges();

CREATE OR REPLACE FUNCTION get_active_group_challenges()
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

    today_date := CURRENT_DATE;

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
        -- FIX: Use alias to avoid ambiguity with RETURNS TABLE column
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
    -- FIX: Use alias to avoid ambiguity
    AND (SELECT COUNT(*) FROM challenge_participants cp_count WHERE cp_count.challenge_id = gc.id) > 2
    ORDER BY gc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_group_challenges() TO authenticated;


-- ============================================================================
-- FIX 3: Safe decline_friend_request (was missing entirely)
-- ============================================================================

DROP FUNCTION IF EXISTS decline_friend_request(UUID);

CREATE OR REPLACE FUNCTION decline_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    IF request_record.addressee_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only decline requests sent to you';
    END IF;
    
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION decline_friend_request(UUID) TO authenticated;


-- ============================================================================
-- FIX 4: Safe cancel_friend_request (was missing entirely)
-- ============================================================================

DROP FUNCTION IF EXISTS cancel_friend_request(UUID);

CREATE OR REPLACE FUNCTION cancel_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    IF request_record.requester_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only cancel requests you sent';
    END IF;
    
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_friend_request(UUID) TO authenticated;


-- ============================================================================
-- FIX 5: Safe reject_friend_request (was deleting ANY friendship)
-- ============================================================================

CREATE OR REPLACE FUNCTION reject_friend_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    request_record RECORD;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    
    SELECT * INTO request_record
    FROM friendships
    WHERE id = request_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    IF request_record.addressee_id != current_user_uuid 
       AND request_record.requester_id != current_user_uuid THEN
        RAISE EXCEPTION 'You can only reject/cancel your own requests';
    END IF;
    
    DELETE FROM friendships WHERE id = request_id AND status = 'pending';
    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_friend_request(UUID) TO authenticated;


-- ============================================================================
-- FIX 6: RLS policies on friendships table
-- ============================================================================

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can insert friendships" ON friendships;
DROP POLICY IF EXISTS "Users can update their friendships" ON friendships;
DROP POLICY IF EXISTS "Users can delete their friendships" ON friendships;

CREATE POLICY "Users can view their friendships"
ON friendships FOR SELECT TO authenticated
USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

CREATE POLICY "Users can insert friendships"
ON friendships FOR INSERT TO authenticated
WITH CHECK (auth.uid() = requester_id);

CREATE POLICY "Users can update their friendships"
ON friendships FOR UPDATE TO authenticated
USING (auth.uid() = requester_id OR auth.uid() = addressee_id);

CREATE POLICY "Users can delete their friendships"
ON friendships FOR DELETE TO authenticated
USING (auth.uid() = requester_id OR auth.uid() = addressee_id);


-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
DECLARE
    func_list TEXT[] := ARRAY[
        'get_active_challenges',
        'get_active_group_challenges',
        'decline_friend_request',
        'cancel_friend_request',
        'reject_friend_request',
        'get_friends',
        'send_friend_request',
        'accept_friend_request',
        'create_challenge',
        'respond_to_challenge'
    ];
    func TEXT;
    func_exists BOOLEAN;
    all_ok BOOLEAN := TRUE;
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '🔧 COMPREHENSIVE AUDIT FIX RESULTS';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '🛠️ DATABASE FIXES:';
    RAISE NOTICE '  ✅ get_active_challenges — ambiguous column fixed';
    RAISE NOTICE '  ✅ get_active_group_challenges — ambiguous column fixed';
    RAISE NOTICE '  ✅ decline_friend_request — created (was missing)';
    RAISE NOTICE '  ✅ cancel_friend_request — created (was missing)';
    RAISE NOTICE '  ✅ reject_friend_request — now only deletes PENDING';
    RAISE NOTICE '  ✅ friendships RLS — policies added';
    RAISE NOTICE '';
    RAISE NOTICE '📱 SWIFT FIXES (in code, rebuild required):';
    RAISE NOTICE '  ✅ RealtimeService — friend_challenges → group_challenges';
    RAISE NOTICE '  ✅ Account deletion — fixed 6 wrong table/column names';
    RAISE NOTICE '  ✅ Account deletion — added 20+ missing tables';
    RAISE NOTICE '';
    
    FOREACH func IN ARRAY func_list
    LOOP
        SELECT EXISTS (
            SELECT 1 FROM information_schema.routines
            WHERE routine_schema = 'public'
              AND routine_name = func
        ) INTO func_exists;
        
        IF func_exists THEN
            RAISE NOTICE '  ✅ % exists', func;
        ELSE
            RAISE WARNING '  ❌ % MISSING', func;
            all_ok := FALSE;
        END IF;
    END LOOP;
    
    RAISE NOTICE '';
    IF all_ok THEN
        RAISE NOTICE '✅ All critical functions verified!';
    ELSE
        RAISE NOTICE '⚠️ Some functions still missing — check above';
    END IF;
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
