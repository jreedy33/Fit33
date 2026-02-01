-- ============================================================================
-- CHALLENGE CLEANUP AND LIMITS
-- Run this to clear existing challenges and enforce new constraints
-- ============================================================================

-- 1. CLEAR ALL EXISTING CHALLENGE DATA
-- ============================================================================

-- Delete in order to respect foreign key constraints
DELETE FROM challenge_daily_progress;
DELETE FROM challenge_participants;
DELETE FROM friend_challenges;

SELECT 'All challenge data cleared!' AS status;

-- 2. ADD CONSTRAINT: Only 1 active/pending challenge between same two friends
-- ============================================================================

-- Create a function to check for duplicate challenges between friends
CREATE OR REPLACE FUNCTION check_duplicate_challenge()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_count INT;
    v_other_user_id UUID;
BEGIN
    -- Get the other participant
    SELECT user_id INTO v_other_user_id
    FROM challenge_participants
    WHERE challenge_id = NEW.challenge_id
    AND user_id != NEW.user_id
    LIMIT 1;
    
    -- If no other participant yet (first insert), allow it
    IF v_other_user_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Check if there's already an active/pending challenge between these two users
    SELECT COUNT(*) INTO v_existing_count
    FROM friend_challenges fc
    JOIN challenge_participants cp1 ON cp1.challenge_id = fc.id
    JOIN challenge_participants cp2 ON cp2.challenge_id = fc.id AND cp2.user_id != cp1.user_id
    WHERE fc.status IN ('active', 'pending')
    AND fc.id != NEW.challenge_id  -- Exclude the current challenge being created
    AND (
        (cp1.user_id = NEW.user_id AND cp2.user_id = v_other_user_id)
        OR (cp1.user_id = v_other_user_id AND cp2.user_id = NEW.user_id)
    );
    
    IF v_existing_count > 0 THEN
        RAISE EXCEPTION 'You already have an active challenge with this friend. Complete or cancel it first.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS check_duplicate_challenge_trigger ON challenge_participants;

-- Create trigger on challenge_participants
CREATE TRIGGER check_duplicate_challenge_trigger
    BEFORE INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION check_duplicate_challenge();

-- 3. ADD CONSTRAINT: Max 3 active/pending challenges per user
-- ============================================================================

CREATE OR REPLACE FUNCTION check_max_challenges_per_user()
RETURNS TRIGGER AS $$
DECLARE
    v_active_count INT;
BEGIN
    -- Count active/pending challenges for this user
    SELECT COUNT(*) INTO v_active_count
    FROM challenge_participants cp
    JOIN friend_challenges fc ON fc.id = cp.challenge_id
    WHERE cp.user_id = NEW.user_id
    AND fc.status IN ('active', 'pending')
    AND fc.id != NEW.challenge_id;  -- Exclude current challenge
    
    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'You can only have up to 3 active challenges at a time.';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS check_max_challenges_trigger ON challenge_participants;

-- Create trigger
CREATE TRIGGER check_max_challenges_trigger
    BEFORE INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION check_max_challenges_per_user();

-- 4. UPDATE create_challenge FUNCTION to include validation
-- ============================================================================

CREATE OR REPLACE FUNCTION create_challenge(
    p_friend_id UUID,
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_daily_target INT DEFAULT NULL,
    p_total_target INT DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL,
    p_duration_days INT DEFAULT 7
)
RETURNS UUID AS $$
DECLARE
    v_challenge_id UUID;
    v_user_id UUID;
    v_existing_count INT;
    v_user_challenge_count INT;
    v_friend_challenge_count INT;
    v_actual_end_date DATE;
BEGIN
    v_user_id := auth.uid();
    
    -- Calculate end date if not provided
    v_actual_end_date := COALESCE(p_end_date, p_start_date + (p_duration_days - 1));
    
    -- CHECK 1: Verify they are actually friends
    IF NOT EXISTS (
        SELECT 1 FROM friendships 
        WHERE status = 'accepted'
        AND ((user_id = v_user_id AND friend_id = p_friend_id)
             OR (user_id = p_friend_id AND friend_id = v_user_id))
    ) THEN
        RAISE EXCEPTION 'You can only challenge your friends';
    END IF;
    
    -- CHECK 2: No existing active/pending challenge between these two users
    SELECT COUNT(*) INTO v_existing_count
    FROM friend_challenges fc
    JOIN challenge_participants cp1 ON cp1.challenge_id = fc.id
    JOIN challenge_participants cp2 ON cp2.challenge_id = fc.id AND cp2.user_id != cp1.user_id
    WHERE fc.status IN ('active', 'pending')
    AND (
        (cp1.user_id = v_user_id AND cp2.user_id = p_friend_id)
        OR (cp1.user_id = p_friend_id AND cp2.user_id = v_user_id)
    );
    
    IF v_existing_count > 0 THEN
        RAISE EXCEPTION 'You already have an active challenge with this friend. Complete or cancel it first.';
    END IF;
    
    -- CHECK 3: User hasn't exceeded max 3 challenges
    SELECT COUNT(*) INTO v_user_challenge_count
    FROM challenge_participants cp
    JOIN friend_challenges fc ON fc.id = cp.challenge_id
    WHERE cp.user_id = v_user_id
    AND fc.status IN ('active', 'pending');
    
    IF v_user_challenge_count >= 3 THEN
        RAISE EXCEPTION 'You can only have up to 3 active challenges at a time.';
    END IF;
    
    -- CHECK 4: Friend hasn't exceeded max 3 challenges
    SELECT COUNT(*) INTO v_friend_challenge_count
    FROM challenge_participants cp
    JOIN friend_challenges fc ON fc.id = cp.challenge_id
    WHERE cp.user_id = p_friend_id
    AND fc.status IN ('active', 'pending');
    
    IF v_friend_challenge_count >= 3 THEN
        RAISE EXCEPTION 'Your friend already has 3 active challenges.';
    END IF;
    
    -- Create the challenge
    INSERT INTO friend_challenges (
        challenge_type,
        title,
        description,
        daily_target,
        total_target,
        target_unit,
        start_date,
        end_date,
        status,
        created_by
    ) VALUES (
        p_challenge_type,
        p_title,
        p_description,
        p_daily_target,
        p_total_target,
        p_target_unit,
        p_start_date,
        v_actual_end_date,
        'pending',
        v_user_id
    ) RETURNING id INTO v_challenge_id;
    
    -- Add creator as accepted participant
    INSERT INTO challenge_participants (challenge_id, user_id, status)
    VALUES (v_challenge_id, v_user_id, 'accepted');
    
    -- Add friend as pending participant (this triggers the notification)
    INSERT INTO challenge_participants (challenge_id, user_id, status)
    VALUES (v_challenge_id, p_friend_id, 'pending');
    
    RETURN v_challenge_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT 'Challenge constraints added:' AS status;
SELECT '- Max 1 active challenge between same two friends' AS constraint1;
SELECT '- Max 3 active challenges per user' AS constraint2;
SELECT '- All existing challenges cleared' AS cleanup;
