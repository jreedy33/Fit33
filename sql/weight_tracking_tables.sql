-- Weight Tracking Tables for Fit33
-- Run this migration to add weight tracking functionality

-- =====================================================
-- 1. WEIGHT LOGS TABLE
-- Stores individual weight entries
-- =====================================================
CREATE TABLE IF NOT EXISTS weight_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    weight_kg DECIMAL(6,2) NOT NULL,  -- Supports up to 9999.99 kg
    weight_lbs DECIMAL(6,2) NOT NULL, -- Supports up to 9999.99 lbs (e.g., 121.4)
    logged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    source TEXT NOT NULL DEFAULT 'manual', -- 'manual', 'apple_health', etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT weight_kg_positive CHECK (weight_kg > 0),
    CONSTRAINT weight_lbs_positive CHECK (weight_lbs > 0)
);

-- Index for efficient user queries
CREATE INDEX IF NOT EXISTS idx_weight_logs_user_date 
ON weight_logs(user_id, logged_at DESC);

-- Enable RLS
ALTER TABLE weight_logs ENABLE ROW LEVEL SECURITY;

-- Users can only access their own weight logs
CREATE POLICY "Users can view own weight logs"
ON weight_logs FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own weight logs"
ON weight_logs FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own weight logs"
ON weight_logs FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own weight logs"
ON weight_logs FOR DELETE
USING (auth.uid() = user_id);


-- =====================================================
-- 2. WEIGHT GOALS TABLE
-- Stores user's weight goals
-- =====================================================
CREATE TABLE IF NOT EXISTS weight_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    target_weight DECIMAL(6,2) NOT NULL, -- Supports decimals like 121.4 lbs
    target_date DATE,
    goal_type TEXT NOT NULL DEFAULT 'lose', -- 'lose', 'gain', 'maintain'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT target_weight_positive CHECK (target_weight > 0),
    CONSTRAINT valid_goal_type CHECK (goal_type IN ('lose', 'gain', 'maintain'))
);

-- Enable RLS
ALTER TABLE weight_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own weight goals"
ON weight_goals FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own weight goals"
ON weight_goals FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own weight goals"
ON weight_goals FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own weight goals"
ON weight_goals FOR DELETE
USING (auth.uid() = user_id);


-- =====================================================
-- 3. WEIGHT STATISTICS VIEW
-- Computed statistics for each user (materialized for performance)
-- =====================================================
CREATE OR REPLACE VIEW weight_statistics AS
SELECT 
    user_id,
    -- Current weight (most recent)
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at DESC LIMIT 1) as current_weight,
    
    -- Starting weight (first entry)
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at ASC LIMIT 1) as starting_weight,
    
    -- Lowest and highest
    MIN(weight_kg) as lowest_weight,
    MAX(weight_kg) as highest_weight,
    
    -- Total change
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at DESC LIMIT 1) -
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at ASC LIMIT 1) as total_change,
    
    -- Weekly change (current - 7 days ago)
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at DESC LIMIT 1) -
    COALESCE(
        (SELECT weight_kg FROM weight_logs wl2 
         WHERE wl2.user_id = wl.user_id 
         AND logged_at <= NOW() - INTERVAL '7 days'
         ORDER BY logged_at DESC LIMIT 1),
        (SELECT weight_kg FROM weight_logs wl2 
         WHERE wl2.user_id = wl.user_id 
         ORDER BY logged_at DESC LIMIT 1)
    ) as weekly_change,
    
    -- Monthly change (current - 30 days ago)
    (SELECT weight_kg FROM weight_logs wl2 
     WHERE wl2.user_id = wl.user_id 
     ORDER BY logged_at DESC LIMIT 1) -
    COALESCE(
        (SELECT weight_kg FROM weight_logs wl2 
         WHERE wl2.user_id = wl.user_id 
         AND logged_at <= NOW() - INTERVAL '30 days'
         ORDER BY logged_at DESC LIMIT 1),
        (SELECT weight_kg FROM weight_logs wl2 
         WHERE wl2.user_id = wl.user_id 
         ORDER BY logged_at DESC LIMIT 1)
    ) as monthly_change,
    
    -- Average weight
    ROUND(AVG(weight_kg)::numeric, 2) as average_weight,
    
    -- Total entries
    COUNT(*) as total_entries,
    
    -- Calculate streak (consecutive days with entries)
    0 as streak_days, -- Calculated in app for simplicity
    
    -- Last logged date
    MAX(logged_at::date)::text as last_logged_date
    
FROM weight_logs wl
GROUP BY user_id;


-- =====================================================
-- 4. FUNCTION: Calculate Weight Streak
-- Returns number of consecutive days user has logged weight
-- =====================================================
CREATE OR REPLACE FUNCTION calculate_weight_streak(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    streak INTEGER := 0;
    check_date DATE := CURRENT_DATE;
    has_entry BOOLEAN;
BEGIN
    -- Check if today has entry
    SELECT EXISTS(
        SELECT 1 FROM weight_logs 
        WHERE user_id = p_user_id 
        AND DATE(logged_at) = check_date
    ) INTO has_entry;
    
    IF NOT has_entry THEN
        check_date := check_date - 1;
    END IF;
    
    -- Count consecutive days
    LOOP
        SELECT EXISTS(
            SELECT 1 FROM weight_logs 
            WHERE user_id = p_user_id 
            AND DATE(logged_at) = check_date
        ) INTO has_entry;
        
        EXIT WHEN NOT has_entry;
        
        streak := streak + 1;
        check_date := check_date - 1;
    END LOOP;
    
    RETURN streak;
END;
$$ LANGUAGE plpgsql;


-- =====================================================
-- 5. TRIGGER: Update user profile weight on log
-- Automatically updates user_profiles.weight_kg when new weight is logged
-- =====================================================
CREATE OR REPLACE FUNCTION sync_profile_weight()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the user's profile with the new weight
    UPDATE user_profiles
    SET 
        weight_kg = NEW.weight_kg,
        weight_lbs = NEW.weight_lbs,
        updated_at = NOW()
    WHERE id = NEW.user_id::text;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger (if not exists)
DROP TRIGGER IF EXISTS trigger_sync_profile_weight ON weight_logs;
CREATE TRIGGER trigger_sync_profile_weight
AFTER INSERT ON weight_logs
FOR EACH ROW
EXECUTE FUNCTION sync_profile_weight();


-- =====================================================
-- 6. GRANT PERMISSIONS
-- =====================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON weight_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON weight_goals TO authenticated;
GRANT SELECT ON weight_statistics TO authenticated;


-- =====================================================
-- 7. INDEXES FOR PERFORMANCE
-- =====================================================
-- Index on logged_at directly (most queries filter by date range)
CREATE INDEX IF NOT EXISTS idx_weight_logs_logged_at 
ON weight_logs(logged_at DESC);

-- Composite index for user + date queries
CREATE INDEX IF NOT EXISTS idx_weight_logs_user_logged
ON weight_logs(user_id, logged_at DESC);


-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE 'Weight tracking tables created successfully!';
    RAISE NOTICE 'Tables: weight_logs, weight_goals';
    RAISE NOTICE 'View: weight_statistics';
    RAISE NOTICE 'Function: calculate_weight_streak()';
    RAISE NOTICE 'Trigger: sync_profile_weight';
END $$;
