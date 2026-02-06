-- ============================================================================
-- CLEANUP OLD TEST CHALLENGES
-- Remove stale pending challenges from testing
-- ============================================================================

-- 1. First, let's see what pending challenges exist
SELECT 
    fc.id,
    fc.title,
    fc.status,
    fc.challenge_type,
    fc.created_at,
    fc.start_date,
    fc.end_date,
    creator.name AS creator_name,
    opponent.name AS opponent_name,
    cp.status AS participant_status
FROM friend_challenges fc
LEFT JOIN user_profiles creator ON creator.id = fc.creator_id
LEFT JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id != fc.creator_id
LEFT JOIN user_profiles opponent ON opponent.id = cp.user_id
ORDER BY fc.created_at DESC;

-- 2. See specifically the "pending" ones (participants haven't accepted)
SELECT 
    fc.id,
    fc.title,
    fc.status AS challenge_status,
    fc.created_at,
    cp.status AS participant_status,
    opponent.name AS waiting_for
FROM friend_challenges fc
JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id != fc.creator_id
LEFT JOIN user_profiles opponent ON opponent.id = cp.user_id
WHERE cp.status = 'pending'
ORDER BY fc.created_at DESC;

-- ============================================================================
-- 3. CLEANUP: Cancel all old pending challenges (older than 7 days)
-- ============================================================================

-- Update challenge status to cancelled for old pending ones
UPDATE friend_challenges
SET status = 'cancelled', updated_at = NOW()
WHERE id IN (
    SELECT fc.id 
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id != fc.creator_id
    WHERE cp.status = 'pending'
    AND fc.created_at < NOW() - INTERVAL '7 days'
);

-- Update participant status to 'left' for those cancelled challenges
UPDATE challenge_participants
SET status = 'left', updated_at = NOW()
WHERE challenge_id IN (
    SELECT id FROM friend_challenges WHERE status = 'cancelled'
)
AND status = 'pending';

-- ============================================================================
-- 4. AGGRESSIVE CLEANUP: Cancel ALL pending challenges (use if needed)
-- Uncomment to run
-- ============================================================================

/*
-- Cancel ALL pending challenges
UPDATE friend_challenges
SET status = 'cancelled', updated_at = NOW()
WHERE id IN (
    SELECT fc.id 
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id != fc.creator_id
    WHERE cp.status = 'pending'
);

-- Update all pending participant statuses
UPDATE challenge_participants
SET status = 'left', updated_at = NOW()
WHERE status = 'pending';
*/

-- ============================================================================
-- 5. Verify cleanup - show remaining pending
-- ============================================================================

SELECT 
    'Remaining pending challenges:' AS info,
    COUNT(*) AS count
FROM friend_challenges fc
JOIN challenge_participants cp ON cp.challenge_id = fc.id AND cp.user_id != fc.creator_id
WHERE cp.status = 'pending';
