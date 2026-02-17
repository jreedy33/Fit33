-- ============================================================================
-- FIX: leave_group_challenge function overload ambiguity
-- ============================================================================
-- PostgREST error: "Could not choose the best candidate function between:
--   public.leave_group_challenge(p_challenge_id => text),
--   public.leave_group_challenge(p_challenge_id => uuid)"
--
-- Fix: Drop ALL versions and recreate only the TEXT version
-- (Swift client always sends UUID as TEXT string)
-- ============================================================================

-- Drop ALL overloaded versions
DROP FUNCTION IF EXISTS leave_group_challenge(TEXT);
DROP FUNCTION IF EXISTS leave_group_challenge(UUID);

-- Recreate with TEXT parameter only (matches Swift client)
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
-- Also fix cancel_group_challenge if it has the same issue
-- ============================================================================
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
    challenge_uuid := p_challenge_id::UUID;

    -- Only creator can cancel
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
DO $$
BEGIN
    RAISE NOTICE '✅ Fixed leave_group_challenge — removed UUID overload';
    RAISE NOTICE '✅ Fixed cancel_group_challenge — removed UUID overload';
    RAISE NOTICE '   PostgREST can now resolve the correct function';
END $$;
