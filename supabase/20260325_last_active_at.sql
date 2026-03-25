-- Add last_active_at column to user_profiles
-- Updated by the iOS app every time it enters foreground (throttled to 1 min)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS last_active_at timestamptz;

-- Index for admin queries sorting/filtering by activity
CREATE INDEX IF NOT EXISTS idx_user_profiles_last_active_at ON user_profiles (last_active_at DESC);
