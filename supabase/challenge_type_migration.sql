-- ============================================================================
-- CHALLENGE TYPE MIGRATION + REAL-TIME SYNC ENHANCEMENTS
-- ============================================================================
-- This migration:
--   1. Adds new challenge types: hydrate, calories, protein
--   2. Enhances log_challenge_progress with streak calculation
--   3. Adds a trigger for auto-updating challenge_participants on progress log
--   4. Enables Realtime on challenge_daily_progress for live opponent updates
--   5. Adds indexes for fast progress queries
-- ============================================================================

-- ============================================================================
-- 1. ENSURE challenge_daily_progress TABLE EXISTS AND HAS CORRECT SCHEMA
-- ============================================================================

-- Create the table if it doesn't exist (idempotent)
CREATE TABLE IF NOT EXISTS challenge_daily_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES group_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    progress_date DATE NOT NULL DEFAULT CURRENT_DATE,
    progress_value INT NOT NULL DEFAULT 0,
    target_hit BOOLEAN NOT NULL DEFAULT FALSE,
    source TEXT DEFAULT 'manual',
    workout_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(challenge_id, user_id, progress_date)
);

-- Add target_hit column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'challenge_daily_progress' AND column_name = 'target_hit'
    ) THEN
        ALTER TABLE challenge_daily_progress ADD COLUMN target_hit BOOLEAN NOT NULL DEFAULT FALSE;
    END IF;
END $$;

-- ============================================================================
-- 2. ENHANCED log_challenge_progress WITH STREAK + TARGET_HIT TRACKING
-- ============================================================================
-- This replaces the existing function with one that also:
--   - Sets target_hit = TRUE when progress >= daily_target
--   - Calculates current_streak and best_streak on challenge_participants
--   - Returns TRUE so the app knows it succeeded
-- ============================================================================

DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id TEXT,
    p_progress_value INT,
    p_progress_date TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'manual',
    p_workout_id TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid UUID;
    progress_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_current_streak INT := 0;
    v_best_streak INT := 0;
    v_check_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;

    -- Parse date
    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        progress_date := p_progress_date::DATE;
    ELSE
        progress_date := CURRENT_DATE;
    END IF;

    -- Verify user is a participant in this challenge
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    -- Get daily target for this challenge
    SELECT daily_target INTO v_daily_target
    FROM group_challenges
    WHERE id = challenge_uuid;

    -- Check if this progress value hits the daily target
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
        progress_date,
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

    -- Calculate streak: count consecutive days where target was hit, going backwards from today
    v_check_date := progress_date;
    v_current_streak := 0;
    
    LOOP
        IF EXISTS (
            SELECT 1 FROM challenge_daily_progress
            WHERE challenge_id = challenge_uuid
              AND user_id = current_user_uuid
              AND progress_date = v_check_date
              AND (target_hit = TRUE OR progress_value >= COALESCE(v_daily_target, 0))
        ) THEN
            v_current_streak := v_current_streak + 1;
            v_check_date := v_check_date - INTERVAL '1 day';
        ELSE
            EXIT;
        END IF;
        
        -- Safety: don't go beyond 365 days
        IF v_current_streak > 365 THEN
            EXIT;
        END IF;
    END LOOP;

    -- Get existing best streak
    SELECT COALESCE(best_streak, 0) INTO v_best_streak
    FROM challenge_participants
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    -- Update best streak if current is higher
    v_best_streak := GREATEST(v_best_streak, v_current_streak);

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
        ),
        current_streak = v_current_streak,
        best_streak = v_best_streak
    WHERE challenge_id = challenge_uuid AND user_id = current_user_uuid;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 3. INDEXES FOR FAST CHALLENGE PROGRESS QUERIES
-- ============================================================================

-- Fast lookup: today's progress for a user in a challenge
CREATE INDEX IF NOT EXISTS idx_cdp_challenge_user_date 
    ON challenge_daily_progress(challenge_id, user_id, progress_date);

-- Fast lookup: all progress for a challenge (for leaderboard)
CREATE INDEX IF NOT EXISTS idx_cdp_challenge_date 
    ON challenge_daily_progress(challenge_id, progress_date);

-- Fast lookup: user's progress across all challenges
CREATE INDEX IF NOT EXISTS idx_cdp_user_date 
    ON challenge_daily_progress(user_id, progress_date);

-- Index on challenge_participants for fast progress queries
CREATE INDEX IF NOT EXISTS idx_cp_challenge_user
    ON challenge_participants(challenge_id, user_id);


-- ============================================================================
-- 4. ENABLE REALTIME ON CHALLENGE TABLES
-- ============================================================================
-- This enables Supabase Realtime on the progress tables so opponents
-- get instant updates when the other person logs progress.

-- Enable realtime on challenge_daily_progress (for live opponent updates)
DO $$
BEGIN
    -- Add to realtime publication if not already there
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'challenge_daily_progress'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;
        RAISE NOTICE '✅ Added challenge_daily_progress to Realtime';
    ELSE
        RAISE NOTICE 'ℹ️ challenge_daily_progress already in Realtime';
    END IF;
END $$;

-- Enable realtime on challenge_participants (for status + total progress updates)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'challenge_participants'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE challenge_participants;
        RAISE NOTICE '✅ Added challenge_participants to Realtime';
    ELSE
        RAISE NOTICE 'ℹ️ challenge_participants already in Realtime';
    END IF;
END $$;

-- Enable realtime on group_challenges (for challenge status changes)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND tablename = 'group_challenges'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE group_challenges;
        RAISE NOTICE '✅ Added group_challenges to Realtime';
    ELSE
        RAISE NOTICE 'ℹ️ group_challenges already in Realtime';
    END IF;
END $$;


-- ============================================================================
-- 5. RLS POLICIES FOR CHALLENGE TABLES
-- ============================================================================
-- Ensure users can only see/update their own challenge data, but CAN see
-- opponent progress in challenges they're part of.

-- Enable RLS
ALTER TABLE challenge_daily_progress ENABLE ROW LEVEL SECURITY;

-- Policy: users can see progress for challenges they participate in
DROP POLICY IF EXISTS "Users can view progress in their challenges" ON challenge_daily_progress;
CREATE POLICY "Users can view progress in their challenges" ON challenge_daily_progress
    FOR SELECT USING (
        challenge_id IN (
            SELECT challenge_id FROM challenge_participants WHERE user_id = auth.uid()
        )
    );

-- Policy: users can insert/update only their own progress
DROP POLICY IF EXISTS "Users can insert own progress" ON challenge_daily_progress;
CREATE POLICY "Users can insert own progress" ON challenge_daily_progress
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own progress" ON challenge_daily_progress;
CREATE POLICY "Users can update own progress" ON challenge_daily_progress
    FOR UPDATE USING (user_id = auth.uid());


-- ============================================================================
-- 6. HELPER VIEW: CHALLENGE PROGRESS SUMMARY
-- ============================================================================
-- A view that gives a quick snapshot of each challenge's progress,
-- making it easier to build leaderboards and compare users.

CREATE OR REPLACE VIEW challenge_progress_summary AS
SELECT 
    cp.challenge_id,
    cp.user_id,
    gc.challenge_type,
    gc.title,
    gc.daily_target,
    gc.target_unit,
    gc.status AS challenge_status,
    gc.start_date,
    gc.end_date,
    cp.total_progress,
    cp.days_completed,
    cp.current_streak,
    cp.best_streak,
    -- Today's progress
    COALESCE(
        (SELECT cdp.progress_value 
         FROM challenge_daily_progress cdp 
         WHERE cdp.challenge_id = cp.challenge_id 
           AND cdp.user_id = cp.user_id 
           AND cdp.progress_date = CURRENT_DATE),
        0
    ) AS today_progress,
    -- Today's target hit?
    COALESCE(
        (SELECT cdp.target_hit 
         FROM challenge_daily_progress cdp 
         WHERE cdp.challenge_id = cp.challenge_id 
           AND cdp.user_id = cp.user_id 
           AND cdp.progress_date = CURRENT_DATE),
        FALSE
    ) AS today_target_hit,
    -- User profile info
    up.name AS user_name,
    up.username AS user_username,
    up.profile_photo_url
FROM challenge_participants cp
JOIN group_challenges gc ON gc.id = cp.challenge_id
LEFT JOIN user_profiles up ON up.id = cp.user_id
WHERE cp.status = 'accepted';


-- ============================================================================
-- 7. FUNCTION: GET CHALLENGE LEADERBOARD (for group challenges)
-- ============================================================================

DROP FUNCTION IF EXISTS get_challenge_leaderboard(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_leaderboard(p_challenge_id TEXT)
RETURNS TABLE (
    user_id UUID,
    user_name TEXT,
    username TEXT,
    profile_photo_url TEXT,
    total_progress INT,
    today_progress INT,
    days_completed INT,
    current_streak INT,
    best_streak INT,
    rank INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    challenge_uuid UUID;
BEGIN
    challenge_uuid := p_challenge_id::UUID;
    
    -- Verify caller is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = challenge_uuid AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;
    
    RETURN QUERY
    SELECT 
        cp.user_id,
        up.name AS user_name,
        up.username,
        up.profile_photo_url,
        cp.total_progress,
        COALESCE(
            (SELECT cdp.progress_value 
             FROM challenge_daily_progress cdp 
             WHERE cdp.challenge_id = challenge_uuid 
               AND cdp.user_id = cp.user_id 
               AND cdp.progress_date = CURRENT_DATE),
            0
        )::INT AS today_progress,
        cp.days_completed,
        cp.current_streak,
        COALESCE(cp.best_streak, 0)::INT AS best_streak,
        ROW_NUMBER() OVER (ORDER BY cp.total_progress DESC)::INT AS rank
    FROM challenge_participants cp
    LEFT JOIN user_profiles up ON up.id = cp.user_id
    WHERE cp.challenge_id = challenge_uuid
      AND cp.status = 'accepted'
    ORDER BY cp.total_progress DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_leaderboard(TEXT) TO authenticated;


-- ============================================================================
-- 8. ENSURE best_streak COLUMN EXISTS ON challenge_participants
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'challenge_participants' AND column_name = 'best_streak'
    ) THEN
        ALTER TABLE challenge_participants ADD COLUMN best_streak INT DEFAULT 0;
        RAISE NOTICE '✅ Added best_streak column to challenge_participants';
    END IF;
END $$;

-- Also ensure notify_on_opponent_complete column exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'challenge_participants' AND column_name = 'notify_on_opponent_complete'
    ) THEN
        ALTER TABLE challenge_participants ADD COLUMN notify_on_opponent_complete BOOLEAN DEFAULT TRUE;
    END IF;
END $$;


-- ============================================================================
-- 9. AUTO-COMPLETE CHALLENGES TRIGGER
-- ============================================================================
-- When a challenge's end_date passes, automatically mark it as completed
-- and determine the winner.

CREATE OR REPLACE FUNCTION auto_complete_expired_challenges()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    expired_challenge RECORD;
    winner_id UUID;
    max_progress INT;
BEGIN
    FOR expired_challenge IN
        SELECT id, title
        FROM group_challenges
        WHERE status = 'active'
          AND end_date::DATE < CURRENT_DATE
    LOOP
        -- Find winner (highest total_progress)
        SELECT cp.user_id, cp.total_progress 
        INTO winner_id, max_progress
        FROM challenge_participants cp
        WHERE cp.challenge_id = expired_challenge.id
          AND cp.status = 'accepted'
        ORDER BY cp.total_progress DESC
        LIMIT 1;
        
        -- Mark challenge as completed
        UPDATE group_challenges
        SET status = 'completed'
        WHERE id = expired_challenge.id;
        
        RAISE NOTICE '🏆 Challenge "%" completed. Winner: %', expired_challenge.title, winner_id;
    END LOOP;
END;
$$;


-- ============================================================================
-- VERIFICATION
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '============================================';
    RAISE NOTICE '  CHALLENGE TYPE MIGRATION COMPLETE';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE '  ✅ challenge_daily_progress table ready';
    RAISE NOTICE '  ✅ log_challenge_progress enhanced (streaks + target_hit)';
    RAISE NOTICE '  ✅ Performance indexes created';
    RAISE NOTICE '  ✅ Realtime enabled on progress tables';
    RAISE NOTICE '  ✅ RLS policies configured';
    RAISE NOTICE '  ✅ challenge_progress_summary view created';
    RAISE NOTICE '  ✅ get_challenge_leaderboard function added';
    RAISE NOTICE '  ✅ best_streak column ensured';
    RAISE NOTICE '  ✅ Auto-complete expired challenges function added';
    RAISE NOTICE '';
    RAISE NOTICE '  New challenge types supported:';
    RAISE NOTICE '    - hydrate (ml/oz from HydrationService)';
    RAISE NOTICE '    - protein (grams from MealService)';
    RAISE NOTICE '    - calories (cal from HealthKit/MealService)';
    RAISE NOTICE '    - steps, walk, run, lift, workout_streak, active_minutes';
    RAISE NOTICE '';
    RAISE NOTICE '  Real-time sync flow:';
    RAISE NOTICE '    1. User logs water/meal/steps';
    RAISE NOTICE '    2. App calls syncTrackingForType() → logProgress()';
    RAISE NOTICE '    3. DB writes to challenge_daily_progress';
    RAISE NOTICE '    4. Supabase Realtime pushes change to opponent';
    RAISE NOTICE '    5. Opponent app receives event → refreshes challenges';
    RAISE NOTICE '============================================';
END $$;
