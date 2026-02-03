-- ============================================================================
-- ACTIVATE CHALLENGES IMMEDIATELY ON ACCEPT
-- Changes challenge behavior to start the day both users accept
-- ============================================================================

-- Update respond_to_challenge to immediately activate and set start_date to today
DROP FUNCTION IF EXISTS respond_to_challenge(UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION respond_to_challenge(
    p_challenge_id UUID,
    p_accept BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_challenge_status TEXT;
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
    
    -- If accepted, check if challenge should activate immediately
    IF p_accept THEN
        -- Check if all participants have accepted
        SELECT NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = p_challenge_id AND status = 'pending'
        ) INTO v_all_accepted;
        
        -- If everyone accepted, activate immediately and set start date to today
        IF v_all_accepted THEN
            UPDATE friend_challenges
            SET 
                status = 'active',
                start_date = CURRENT_DATE,  -- Start today!
                end_date = CURRENT_DATE + (end_date - start_date),  -- Preserve duration
                updated_at = NOW()
            WHERE id = p_challenge_id 
            AND status = 'pending';
            
            RAISE NOTICE 'Challenge activated immediately - starts today!';
        END IF;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION respond_to_challenge(UUID, BOOLEAN) TO authenticated;

-- ============================================================================
-- Update the auto-activate trigger (no longer needed since we activate on accept)
-- But keep it for edge cases where start_date was manually set
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_activate_challenges()
RETURNS TRIGGER AS $$
BEGIN
    -- When a participant accepts, check if challenge should activate
    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
        -- Check if all participants have accepted
        IF NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = NEW.challenge_id AND status = 'pending'
        ) THEN
            -- Activate and update start date to today if it's in the past or today
            UPDATE friend_challenges
            SET 
                status = 'active',
                start_date = CASE 
                    WHEN start_date < CURRENT_DATE THEN CURRENT_DATE
                    ELSE start_date
                END,
                updated_at = NOW()
            WHERE id = NEW.challenge_id 
            AND status = 'pending';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_auto_activate_challenge ON challenge_participants;
CREATE TRIGGER trigger_auto_activate_challenge
    AFTER UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION auto_activate_challenges();

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT '✅ Challenges now activate immediately when both users accept' AS change1;
SELECT '✅ Start date automatically set to today when activated' AS change2;
SELECT '✅ Challenge duration preserved (end_date adjusted accordingly)' AS change3;
