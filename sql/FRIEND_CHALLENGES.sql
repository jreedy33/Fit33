-- ============================================================================
-- FRIEND CHALLENGES SYSTEM
-- Enables users to create and participate in fitness challenges with friends
-- Supports: Step, Walk, Run, Lift challenges with daily/weekly progress tracking
-- ============================================================================

-- ============================================================================
-- 1. MAIN CHALLENGE TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS friend_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Challenge creator
    creator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Challenge details
    challenge_type TEXT NOT NULL CHECK (challenge_type IN ('steps', 'walk', 'run', 'lift', 'workout_streak', 'active_minutes')),
    title TEXT NOT NULL,
    description TEXT,
    
    -- Challenge goals (flexible based on type)
    daily_target INTEGER, -- e.g., 10000 steps, 30 active minutes
    total_target INTEGER, -- e.g., total steps for entire challenge
    target_unit TEXT NOT NULL DEFAULT 'count', -- 'count', 'minutes', 'miles', 'km', 'workouts'
    
    -- Duration
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed', 'cancelled')),
    
    -- For lift challenges: optional program link
    program_id UUID, -- Reference to a workout program if applicable
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT valid_dates CHECK (end_date >= start_date),
    CONSTRAINT valid_duration CHECK ((end_date - start_date) <= 365) -- Max 1 year
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_challenges_creator ON friend_challenges(creator_id);
CREATE INDEX IF NOT EXISTS idx_challenges_status ON friend_challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_dates ON friend_challenges(start_date, end_date);

-- ============================================================================
-- 2. CHALLENGE PARTICIPANTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    challenge_id UUID NOT NULL REFERENCES friend_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Participant status
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'left')),
    
    -- Aggregate progress (updated as daily progress is logged)
    total_progress INTEGER DEFAULT 0, -- Cumulative progress (steps, minutes, etc.)
    days_completed INTEGER DEFAULT 0, -- Number of days target was hit
    current_streak INTEGER DEFAULT 0, -- Consecutive days hitting target
    best_streak INTEGER DEFAULT 0,
    
    -- Timestamps
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    joined_at TIMESTAMPTZ,
    
    UNIQUE(challenge_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_participants_challenge ON challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_participants_user ON challenge_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_participants_status ON challenge_participants(status);

-- ============================================================================
-- 3. DAILY PROGRESS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS challenge_daily_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    challenge_id UUID NOT NULL REFERENCES friend_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Progress for a specific day
    progress_date DATE NOT NULL,
    progress_value INTEGER NOT NULL DEFAULT 0, -- Steps, minutes, etc.
    target_hit BOOLEAN DEFAULT false, -- Calculated on insert/update via trigger
    
    -- For workout challenges: link to completed workout
    workout_id UUID, -- Reference to completed_workouts if applicable
    
    -- Sync source (for transparency)
    source TEXT DEFAULT 'manual' CHECK (source IN ('manual', 'healthkit', 'strava', 'fitbit')),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(challenge_id, user_id, progress_date)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_daily_progress_challenge ON challenge_daily_progress(challenge_id);
CREATE INDEX IF NOT EXISTS idx_daily_progress_user ON challenge_daily_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_progress_date ON challenge_daily_progress(progress_date);

-- ============================================================================
-- 3.1 TRIGGER: Auto-calculate target_hit on insert/update
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_target_hit()
RETURNS TRIGGER AS $$
DECLARE
    v_daily_target INTEGER;
BEGIN
    -- Get the daily target from the challenge
    SELECT daily_target INTO v_daily_target 
    FROM friend_challenges 
    WHERE id = NEW.challenge_id;
    
    -- Calculate if target was hit
    NEW.target_hit := NEW.progress_value >= COALESCE(v_daily_target, 0);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_calculate_target_hit ON challenge_daily_progress;
CREATE TRIGGER trigger_calculate_target_hit
    BEFORE INSERT OR UPDATE ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION calculate_target_hit();

-- ============================================================================
-- 4. CHALLENGE TEMPLATES (PRELOADED CHALLENGES)
-- ============================================================================

CREATE TABLE IF NOT EXISTS challenge_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    challenge_type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    emoji TEXT DEFAULT '🏆',
    
    -- Default values
    default_daily_target INTEGER,
    default_duration_days INTEGER NOT NULL DEFAULT 7,
    target_unit TEXT NOT NULL DEFAULT 'count',
    
    -- UI ordering
    display_order INTEGER DEFAULT 0,
    is_featured BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert preloaded challenge templates
INSERT INTO challenge_templates (challenge_type, title, description, emoji, default_daily_target, default_duration_days, target_unit, display_order, is_featured) VALUES
-- Step Challenges
('steps', '10K Steps Daily', 'Hit 10,000 steps every day', '👟', 10000, 7, 'steps', 1, true),
('steps', '7K Steps Challenge', 'Perfect for beginners - 7,000 steps daily', '🚶', 7000, 7, 'steps', 2, false),
('steps', '15K Step Warrior', 'For the serious stepper - 15,000 daily', '🦶', 15000, 7, 'steps', 3, false),
('steps', 'Step Marathon Month', '10K steps every day for 30 days', '🏃', 10000, 30, 'steps', 4, true),

-- Walk Challenges
('walk', '30-Min Daily Walk', 'Walk for at least 30 minutes daily', '🌅', 30, 7, 'minutes', 10, true),
('walk', 'Morning Walker', '20-minute walk every morning for 2 weeks', '☀️', 20, 14, 'minutes', 11, false),
('walk', 'Walk & Talk Week', '45-minute daily walks for connection', '💬', 45, 7, 'minutes', 12, false),

-- Run Challenges
('run', 'Couch to 5K Buddy', 'Train together for your first 5K', '🏅', 1, 28, 'workouts', 20, true),
('run', 'Run Streak', 'Run at least 1 mile every day', '🔥', 1, 7, 'miles', 21, true),
('run', '20-Min Run Club', 'Run for 20+ minutes daily', '⚡', 20, 14, 'minutes', 22, false),

-- Workout/Lift Challenges
('lift', 'Gym Partner Challenge', 'Complete workouts together for a week', '💪', 1, 7, 'workouts', 30, true),
('lift', '21-Day Transformation', '3 weeks of consistent training', '🔄', 1, 21, 'workouts', 31, true),
('lift', 'No Skip January', 'Hit the gym every day in January', '📅', 1, 31, 'workouts', 32, false),

-- Workout Streak
('workout_streak', '7-Day Streak Battle', 'Who can maintain a workout streak longer?', '🔥', 1, 7, 'workouts', 40, true),
('workout_streak', '30-Day Consistency', 'Build the habit together', '📈', 1, 30, 'workouts', 41, false),

-- Active Minutes
('active_minutes', '30 Active Minutes', 'Stay active for 30+ minutes daily', '⏱️', 30, 7, 'minutes', 50, true),
('active_minutes', 'Hour of Power', '60 active minutes every day', '💥', 60, 7, 'minutes', 51, false)

ON CONFLICT DO NOTHING;

-- ============================================================================
-- 5. ROW LEVEL SECURITY POLICIES
-- ============================================================================

ALTER TABLE friend_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_daily_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_templates ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid conflicts on re-run)
DROP POLICY IF EXISTS "Users can view own challenges" ON friend_challenges;
DROP POLICY IF EXISTS "Users can create challenges" ON friend_challenges;
DROP POLICY IF EXISTS "Creators can update own challenges" ON friend_challenges;
DROP POLICY IF EXISTS "Creators can delete own challenges" ON friend_challenges;
DROP POLICY IF EXISTS "View participants of joined challenges" ON challenge_participants;
DROP POLICY IF EXISTS "Challenge creator can invite participants" ON challenge_participants;
DROP POLICY IF EXISTS "Users can update own participation" ON challenge_participants;
DROP POLICY IF EXISTS "View progress of joined challenges" ON challenge_daily_progress;
DROP POLICY IF EXISTS "Users can log own progress" ON challenge_daily_progress;
DROP POLICY IF EXISTS "Users can update own progress" ON challenge_daily_progress;
DROP POLICY IF EXISTS "Anyone can view templates" ON challenge_templates;

-- Challenges: Users can see challenges they created or participate in
CREATE POLICY "Users can view own challenges" ON friend_challenges
    FOR SELECT USING (
        creator_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = friend_challenges.id AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can create challenges" ON friend_challenges
    FOR INSERT WITH CHECK (creator_id = auth.uid());

CREATE POLICY "Creators can update own challenges" ON friend_challenges
    FOR UPDATE USING (creator_id = auth.uid());

CREATE POLICY "Creators can delete own challenges" ON friend_challenges
    FOR DELETE USING (creator_id = auth.uid());

-- Participants: Users can see participants of challenges they're in
CREATE POLICY "View participants of joined challenges" ON challenge_participants
    FOR SELECT USING (
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM challenge_participants cp
            WHERE cp.challenge_id = challenge_participants.challenge_id AND cp.user_id = auth.uid()
        )
    );

CREATE POLICY "Challenge creator can invite participants" ON challenge_participants
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM friend_challenges
            WHERE id = challenge_id AND creator_id = auth.uid()
        ) OR user_id = auth.uid()
    );

CREATE POLICY "Users can update own participation" ON challenge_participants
    FOR UPDATE USING (user_id = auth.uid());

-- Daily Progress: Users can see progress of challenges they're in
CREATE POLICY "View progress of joined challenges" ON challenge_daily_progress
    FOR SELECT USING (
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = challenge_daily_progress.challenge_id AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can log own progress" ON challenge_daily_progress
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own progress" ON challenge_daily_progress
    FOR UPDATE USING (user_id = auth.uid());

-- Templates: Everyone can read
CREATE POLICY "Anyone can view templates" ON challenge_templates
    FOR SELECT USING (true);

-- ============================================================================
-- 6. DATABASE FUNCTIONS
-- ============================================================================

-- Function: Create a new challenge
CREATE OR REPLACE FUNCTION create_challenge(
    p_opponent_id UUID,
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_daily_target INTEGER DEFAULT NULL,
    p_total_target INTEGER DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date DATE DEFAULT CURRENT_DATE + 1,
    p_duration_days INTEGER DEFAULT 7
)
RETURNS UUID AS $$
DECLARE
    v_challenge_id UUID;
    v_end_date DATE;
BEGIN
    v_end_date := p_start_date + (p_duration_days - 1);
    
    -- Create the challenge
    INSERT INTO friend_challenges (
        creator_id, challenge_type, title, description,
        daily_target, total_target, target_unit,
        start_date, end_date, status
    ) VALUES (
        auth.uid(), p_challenge_type, p_title, p_description,
        p_daily_target, p_total_target, p_target_unit,
        p_start_date, v_end_date, 'pending'
    )
    RETURNING id INTO v_challenge_id;
    
    -- Add creator as participant (auto-accepted)
    INSERT INTO challenge_participants (challenge_id, user_id, status, responded_at, joined_at)
    VALUES (v_challenge_id, auth.uid(), 'accepted', NOW(), NOW());
    
    -- Invite opponent
    INSERT INTO challenge_participants (challenge_id, user_id, status)
    VALUES (v_challenge_id, p_opponent_id, 'pending');
    
    RETURN v_challenge_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_challenge(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, DATE, INTEGER) TO authenticated;

-- Function: Respond to challenge invite
CREATE OR REPLACE FUNCTION respond_to_challenge(
    p_challenge_id UUID,
    p_accept BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_challenge_status TEXT;
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
    
    -- If accepted, check if challenge should start
    IF p_accept THEN
        -- If all participants accepted and start date is today or past, activate
        IF NOT EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = p_challenge_id AND status = 'pending'
        ) THEN
            UPDATE friend_challenges
            SET status = 'active', updated_at = NOW()
            WHERE id = p_challenge_id AND start_date <= CURRENT_DATE;
        END IF;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION respond_to_challenge(UUID, BOOLEAN) TO authenticated;

-- Function: Log daily progress
CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id UUID,
    p_progress_value INTEGER,
    p_progress_date DATE DEFAULT CURRENT_DATE,
    p_source TEXT DEFAULT 'manual',
    p_workout_id UUID DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
    v_daily_target INTEGER;
    v_was_target_hit BOOLEAN;
BEGIN
    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
        WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'User is not a participant';
    END IF;
    
    -- Get daily target
    SELECT daily_target INTO v_daily_target FROM friend_challenges WHERE id = p_challenge_id;
    v_was_target_hit := p_progress_value >= COALESCE(v_daily_target, 0);
    
    -- Insert or update daily progress (target_hit is calculated by trigger)
    INSERT INTO challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, source, workout_id
    ) VALUES (
        p_challenge_id, v_current_user_id, p_progress_date, p_progress_value, p_source, p_workout_id
    )
    ON CONFLICT (challenge_id, user_id, progress_date) 
    DO UPDATE SET 
        progress_value = EXCLUDED.progress_value,
        source = EXCLUDED.source,
        workout_id = COALESCE(EXCLUDED.workout_id, challenge_daily_progress.workout_id),
        updated_at = NOW();
    
    -- Update participant aggregate stats
    UPDATE challenge_participants
    SET 
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM challenge_daily_progress
            WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM challenge_daily_progress
            WHERE challenge_id = p_challenge_id 
            AND user_id = v_current_user_id
            AND target_hit = true
        )
    WHERE challenge_id = p_challenge_id AND user_id = v_current_user_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION log_challenge_progress(UUID, INTEGER, DATE, TEXT, UUID) TO authenticated;

-- Function: Get pending challenge invites
CREATE OR REPLACE FUNCTION get_pending_challenge_invites()
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT,
    start_date DATE,
    end_date DATE,
    duration_days INTEGER,
    creator_id UUID,
    creator_name TEXT,
    creator_username TEXT,
    creator_photo_url TEXT,
    invited_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.id as challenge_id,
        fc.challenge_type,
        fc.title,
        fc.description,
        COALESCE(ct.emoji, '🏆') as emoji,
        fc.daily_target,
        fc.total_target,
        fc.target_unit,
        fc.start_date,
        fc.end_date,
        (fc.end_date - fc.start_date + 1)::INTEGER as duration_days,
        fc.creator_id,
        up.name as creator_name,
        up.username as creator_username,
        up.profile_photo_url as creator_photo_url,
        cp.invited_at
    FROM challenge_participants cp
    JOIN friend_challenges fc ON fc.id = cp.challenge_id
    LEFT JOIN user_profiles up ON up.id::TEXT = fc.creator_id::TEXT
    LEFT JOIN challenge_templates ct ON ct.challenge_type = fc.challenge_type AND ct.title = fc.title
    WHERE cp.user_id = auth.uid()
    AND cp.status = 'pending'
    AND fc.status IN ('pending', 'active')
    ORDER BY cp.invited_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_pending_challenge_invites() TO authenticated;

-- Function: Get active challenges with progress
CREATE OR REPLACE FUNCTION get_active_challenges()
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT,
    start_date DATE,
    end_date DATE,
    duration_days INTEGER,
    days_elapsed INTEGER,
    days_remaining INTEGER,
    status TEXT,
    my_total_progress INTEGER,
    my_days_completed INTEGER,
    my_current_streak INTEGER,
    opponent_id UUID,
    opponent_name TEXT,
    opponent_username TEXT,
    opponent_photo_url TEXT,
    opponent_total_progress INTEGER,
    opponent_days_completed INTEGER,
    am_winning BOOLEAN
) AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        fc.id as challenge_id,
        fc.challenge_type,
        fc.title,
        fc.description,
        fc.daily_target,
        fc.total_target,
        fc.target_unit,
        fc.start_date,
        fc.end_date,
        (fc.end_date - fc.start_date + 1)::INTEGER as duration_days,
        GREATEST(0, CURRENT_DATE - fc.start_date)::INTEGER as days_elapsed,
        GREATEST(0, fc.end_date - CURRENT_DATE)::INTEGER as days_remaining,
        fc.status,
        my_cp.total_progress as my_total_progress,
        my_cp.days_completed as my_days_completed,
        my_cp.current_streak as my_current_streak,
        opp_cp.user_id as opponent_id,
        opp_up.name as opponent_name,
        opp_up.username as opponent_username,
        opp_up.profile_photo_url as opponent_photo_url,
        opp_cp.total_progress as opponent_total_progress,
        opp_cp.days_completed as opponent_days_completed,
        (my_cp.total_progress > opp_cp.total_progress) as am_winning
    FROM friend_challenges fc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = fc.id AND my_cp.user_id = v_current_user_id
    JOIN challenge_participants opp_cp ON opp_cp.challenge_id = fc.id AND opp_cp.user_id != v_current_user_id
    LEFT JOIN user_profiles opp_up ON opp_up.id::TEXT = opp_cp.user_id::TEXT
    WHERE my_cp.status = 'accepted'
    AND fc.status IN ('active', 'pending')
    ORDER BY fc.start_date ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_active_challenges() TO authenticated;

-- Function: Get challenge details with daily breakdown
CREATE OR REPLACE FUNCTION get_challenge_details(p_challenge_id UUID)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT,
    start_date DATE,
    end_date DATE,
    duration_days INTEGER,
    status TEXT,
    created_at TIMESTAMPTZ,
    -- Participants as JSON array
    participants JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.id,
        fc.challenge_type,
        fc.title,
        fc.description,
        fc.daily_target,
        fc.total_target,
        fc.target_unit,
        fc.start_date,
        fc.end_date,
        (fc.end_date - fc.start_date + 1)::INTEGER as duration_days,
        fc.status,
        fc.created_at,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', cp.user_id,
                'name', up.name,
                'username', up.username,
                'photo_url', up.profile_photo_url,
                'status', cp.status,
                'total_progress', cp.total_progress,
                'days_completed', cp.days_completed,
                'current_streak', cp.current_streak,
                'best_streak', cp.best_streak,
                'is_creator', cp.user_id = fc.creator_id,
                'daily_progress', (
                    SELECT jsonb_agg(jsonb_build_object(
                        'date', cdp.progress_date,
                        'value', cdp.progress_value,
                        'source', cdp.source
                    ) ORDER BY cdp.progress_date)
                    FROM challenge_daily_progress cdp
                    WHERE cdp.challenge_id = fc.id AND cdp.user_id = cp.user_id
                )
            ))
            FROM challenge_participants cp
            LEFT JOIN user_profiles up ON up.id::TEXT = cp.user_id::TEXT
            WHERE cp.challenge_id = fc.id
        ) as participants
    FROM friend_challenges fc
    WHERE fc.id = p_challenge_id
    AND (
        fc.creator_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM challenge_participants
            WHERE challenge_id = fc.id AND user_id = auth.uid()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_challenge_details(UUID) TO authenticated;

-- Function: Get challenges with a specific friend
CREATE OR REPLACE FUNCTION get_challenges_with_friend(p_friend_id UUID)
RETURNS TABLE (
    challenge_id UUID,
    challenge_type TEXT,
    title TEXT,
    status TEXT,
    start_date DATE,
    end_date DATE,
    my_progress INTEGER,
    friend_progress INTEGER,
    am_winning BOOLEAN,
    daily_target INTEGER,
    target_unit TEXT
) AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        fc.id as challenge_id,
        fc.challenge_type,
        fc.title,
        fc.status,
        fc.start_date,
        fc.end_date,
        my_cp.total_progress as my_progress,
        friend_cp.total_progress as friend_progress,
        (my_cp.total_progress > friend_cp.total_progress) as am_winning,
        fc.daily_target,
        fc.target_unit
    FROM friend_challenges fc
    JOIN challenge_participants my_cp ON my_cp.challenge_id = fc.id AND my_cp.user_id = v_current_user_id
    JOIN challenge_participants friend_cp ON friend_cp.challenge_id = fc.id AND friend_cp.user_id = p_friend_id
    WHERE my_cp.status = 'accepted'
    ORDER BY 
        CASE fc.status 
            WHEN 'active' THEN 1 
            WHEN 'pending' THEN 2 
            ELSE 3 
        END,
        fc.start_date DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_challenges_with_friend(UUID) TO authenticated;

-- Function: Get challenge templates
CREATE OR REPLACE FUNCTION get_challenge_templates()
RETURNS TABLE (
    id UUID,
    challenge_type TEXT,
    title TEXT,
    description TEXT,
    emoji TEXT,
    default_daily_target INTEGER,
    default_duration_days INTEGER,
    target_unit TEXT,
    is_featured BOOLEAN
) AS $$
BEGIN
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
    ORDER BY ct.display_order ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_challenge_templates() TO authenticated;

-- ============================================================================
-- 7. TRIGGER: Queue push notification when challenge invite is sent
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_challenge_invite_notification()
RETURNS TRIGGER AS $$
DECLARE
    v_sender_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Only queue notification for new pending invites (not the creator's auto-accepted entry)
    IF NEW.status = 'pending' THEN
        -- Get sender (challenge creator) name
        SELECT COALESCE(up.name, 'Someone') INTO v_sender_name
        FROM friend_challenges fc
        JOIN user_profiles up ON up.id::TEXT = fc.creator_id::TEXT
        WHERE fc.id = NEW.challenge_id;
        
        -- Get challenge title
        SELECT title INTO v_challenge_title
        FROM friend_challenges
        WHERE id = NEW.challenge_id;
        
        -- Insert into notification queue
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data
        ) VALUES (
            NEW.user_id,
            'challenge_invite',
            v_sender_name || ' wants to challenge you! 🏆',
            'Tap to check out "' || COALESCE(v_challenge_title, 'New Challenge') || '" and accept the challenge.',
            jsonb_build_object(
                'challenge_id', NEW.challenge_id::TEXT,
                'sender_name', v_sender_name,
                'challenge_title', v_challenge_title,
                'type', 'challenge_invite'
            )
        );
        
        -- Trigger the edge function via pg_notify
        PERFORM pg_notify('push_notification', json_build_object(
            'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::TEXT,
            'type', 'challenge_invite'
        )::TEXT);
        
        RAISE NOTICE 'Challenge invite notification queued for user %', NEW.user_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_challenge_invite ON challenge_participants;
CREATE TRIGGER on_challenge_invite
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION queue_challenge_invite_notification();

-- ============================================================================
-- 8. TRIGGER: Auto-activate challenges on start date
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
            -- Activate if start date is today or past
            UPDATE friend_challenges
            SET status = 'active', updated_at = NOW()
            WHERE id = NEW.challenge_id 
            AND status = 'pending'
            AND start_date <= CURRENT_DATE;
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
-- 9. TRIGGER: Notify opponent when daily challenge is completed
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_opponent_daily_complete()
RETURNS TRIGGER AS $$
DECLARE
    v_user_name TEXT;
    v_challenge_title TEXT;
    v_opponent_id UUID;
    v_challenge_type TEXT;
BEGIN
    -- Only notify when target_hit changes from false to true (or NULL to true)
    IF NEW.target_hit = TRUE AND (OLD.target_hit IS NULL OR OLD.target_hit = FALSE) THEN
        
        -- Get the user's name who completed the challenge
        SELECT COALESCE(up.name, 'Your opponent') INTO v_user_name
        FROM user_profiles up
        WHERE up.id::TEXT = NEW.user_id::TEXT;
        
        -- Get challenge details
        SELECT fc.title, fc.challenge_type INTO v_challenge_title, v_challenge_type
        FROM friend_challenges fc
        WHERE fc.id = NEW.challenge_id;
        
        -- Find opponent(s) in this challenge
        FOR v_opponent_id IN 
            SELECT cp.user_id 
            FROM challenge_participants cp
            WHERE cp.challenge_id = NEW.challenge_id 
            AND cp.user_id != NEW.user_id
            AND cp.status = 'accepted'
        LOOP
            -- Queue push notification for the opponent
            INSERT INTO push_notification_queue (
                recipient_user_id,
                notification_type,
                title,
                body,
                data
            ) VALUES (
                v_opponent_id,
                'challenge_progress',
                v_user_name || ' completed their daily challenge! 🔥',
                'They hit their target for "' || COALESCE(v_challenge_title, 'Challenge') || '". Don''t fall behind!',
                jsonb_build_object(
                    'challenge_id', NEW.challenge_id::TEXT,
                    'user_name', v_user_name,
                    'challenge_title', v_challenge_title,
                    'challenge_type', v_challenge_type,
                    'type', 'challenge_progress'
                )
            );
            
            -- Trigger the edge function via pg_notify
            PERFORM pg_notify('push_notification', json_build_object(
                'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::TEXT,
                'type', 'challenge_progress'
            )::TEXT);
            
            RAISE NOTICE 'Daily challenge completion notification queued for opponent %', v_opponent_id;
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_daily_challenge_complete ON challenge_daily_progress;
CREATE TRIGGER on_daily_challenge_complete
    AFTER INSERT OR UPDATE ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION notify_opponent_daily_complete();

-- ============================================================================
-- 10. FUNCTION: Auto-complete challenges at end date (call via cron)
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_complete_challenges()
RETURNS void AS $$
BEGIN
    UPDATE friend_challenges
    SET status = 'completed', updated_at = NOW()
    WHERE status = 'active'
    AND end_date < CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 10. CANCEL CHALLENGE
-- ============================================================================

CREATE OR REPLACE FUNCTION cancel_challenge(
    p_challenge_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID;
    v_challenge RECORD;
    v_canceller_name TEXT;
    v_opponent_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    -- Get challenge details
    SELECT fc.*, cp.user_id as participant_id
    INTO v_challenge
    FROM friend_challenges fc
    JOIN challenge_participants cp ON cp.challenge_id = fc.id
    WHERE fc.id = p_challenge_id
    AND cp.user_id = v_user_id
    AND fc.status IN ('active', 'pending');
    
    IF v_challenge IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or you are not a participant';
    END IF;
    
    -- Get canceller's name
    SELECT COALESCE(name, 'Your friend') INTO v_canceller_name
    FROM user_profiles
    WHERE id = v_user_id;
    
    -- Get opponent's user_id
    SELECT user_id INTO v_opponent_id
    FROM challenge_participants
    WHERE challenge_id = p_challenge_id
    AND user_id != v_user_id
    LIMIT 1;
    
    -- Update challenge status to cancelled
    UPDATE friend_challenges
    SET status = 'cancelled', updated_at = NOW()
    WHERE id = p_challenge_id;
    
    -- Update participant statuses
    UPDATE challenge_participants
    SET status = 'cancelled', updated_at = NOW()
    WHERE challenge_id = p_challenge_id;
    
    -- Queue notification to opponent if they exist
    IF v_opponent_id IS NOT NULL THEN
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data
        ) VALUES (
            v_opponent_id,
            'challenge_cancelled',
            v_canceller_name || ' cancelled the challenge 😔',
            'The "' || v_challenge.title || '" challenge has been cancelled.',
            jsonb_build_object(
                'challenge_id', p_challenge_id::TEXT,
                'canceller_name', v_canceller_name,
                'challenge_title', v_challenge.title,
                'type', 'challenge_cancelled'
            )
        );
        
        -- Trigger the edge function via pg_notify
        PERFORM pg_notify('push_notification', json_build_object(
            'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::TEXT,
            'type', 'challenge_cancelled'
        )::TEXT);
        
        RAISE NOTICE 'Challenge cancelled notification queued for opponent %', v_opponent_id;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT 'Friend Challenges system created!' AS status;
SELECT '- friend_challenges: Main challenge table' AS table1;
SELECT '- challenge_participants: Track participants and progress' AS table2;
SELECT '- challenge_daily_progress: Daily progress entries' AS table3;
SELECT '- challenge_templates: Preloaded challenge templates' AS table4;
SELECT 'Functions:' AS functions_header;
SELECT '- create_challenge()' AS func1;
SELECT '- respond_to_challenge()' AS func2;
SELECT '- log_challenge_progress()' AS func3;
SELECT '- get_pending_challenge_invites()' AS func4;
SELECT '- get_active_challenges()' AS func5;
SELECT '- get_challenge_details()' AS func6;
SELECT '- get_challenges_with_friend()' AS func7;
SELECT '- get_challenge_templates()' AS func8;
SELECT '- cancel_challenge()' AS func9;