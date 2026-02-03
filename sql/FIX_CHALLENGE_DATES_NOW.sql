-- ============================================================================
-- FIX CHALLENGE DATES - URGENT
-- Fixes existing challenges to start today and use UTC dates consistently
-- ============================================================================

-- 1. Update all pending challenges to start today
UPDATE friend_challenges
SET 
    start_date = CURRENT_DATE,
    end_date = CURRENT_DATE + (end_date - start_date),  -- Preserve duration
    updated_at = NOW()
WHERE status = 'pending'
AND start_date > CURRENT_DATE;

-- 2. Activate any pending challenges where all participants have accepted
UPDATE friend_challenges fc
SET 
    status = 'active',
    start_date = CURRENT_DATE,
    end_date = CURRENT_DATE + (fc.end_date - fc.start_date),
    updated_at = NOW()
WHERE fc.status = 'pending'
AND NOT EXISTS (
    SELECT 1 FROM challenge_participants cp
    WHERE cp.challenge_id = fc.id AND cp.status = 'pending'
);

-- 3. Update respond_to_challenge to use CURRENT_DATE consistently
DROP FUNCTION IF EXISTS respond_to_challenge(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION respond_to_challenge(
    p_challenge_id UUID,
    p_accept BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_all_accepted BOOLEAN;
BEGIN
    -- Verify user is a pending participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'No pending invite found';
    END IF;
    
    -- Update participant status
    UPDATE challenge_participants
    SET 
        status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
        responded_at = NOW(),
        joined_at = CASE WHEN p_accept THEN NOW() ELSE NULL END
    WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id;
    
    -- If accepted, activate challenge immediately when both users have accepted
    IF p_accept THEN
        -- Check if all participants have accepted
        SELECT NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = p_challenge_id AND status = 'pending'
        ) INTO v_all_accepted;
        
        -- If everyone accepted, activate immediately and set start date to today (UTC)
        IF v_all_accepted THEN
            UPDATE friend_challenges
            SET 
                status = 'active',
                start_date = CURRENT_DATE,  -- Today in UTC
                end_date = CURRENT_DATE + (end_date - start_date),  -- Preserve duration
                updated_at = NOW()
            WHERE id = p_challenge_id 
            AND status = 'pending';
            
            RAISE NOTICE 'Challenge activated! Start: % (UTC CURRENT_DATE)', CURRENT_DATE;
        END IF;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION respond_to_challenge(UUID, BOOLEAN) TO authenticated;

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT '✅ Updated pending challenges to start today' AS fix1;
SELECT '✅ Activated challenges where all users accepted' AS fix2;
SELECT '✅ Fixed respond_to_challenge to use CURRENT_DATE (UTC)' AS fix3;
SELECT 'All challenges should now use UTC dates consistently' AS note;
