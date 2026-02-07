-- Automatic cleanup of incomplete onboarding profiles
-- This prevents duplicate accounts when users restart onboarding after abandoning it

-- Create function to clean up incomplete profiles older than 30 minutes
CREATE OR REPLACE FUNCTION cleanup_incomplete_onboarding_profiles()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete user profiles that:
  -- 1. Haven't completed onboarding (has_completed_onboarding = false)
  -- 2. Were created more than 30 minutes ago
  -- 3. Only have minimal data (just phone/email, no full profile)
  
  DELETE FROM user_profiles
  WHERE has_completed_onboarding = false
    AND created_at < NOW() - INTERVAL '30 minutes'
    -- Additional safety check: only delete if they don't have significant profile data
    -- (username, birthday, height, weight all NULL indicates incomplete profile)
    AND (username IS NULL OR username = '')
    AND birthday IS NULL
    AND height_cm IS NULL
    AND weight_kg IS NULL;
  
  -- Log how many were deleted
  RAISE NOTICE 'Cleaned up % incomplete onboarding profiles', ROW_COUNT;
END;
$$;

-- Grant execute permission to authenticated users (though it will run as service role)
GRANT EXECUTE ON FUNCTION cleanup_incomplete_onboarding_profiles() TO authenticated;
GRANT EXECUTE ON FUNCTION cleanup_incomplete_onboarding_profiles() TO service_role;

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule the cleanup function to run every 10 minutes
-- This ensures abandoned profiles are cleaned up promptly
SELECT cron.schedule(
  'cleanup-incomplete-onboarding',  -- job name
  '*/10 * * * *',                   -- every 10 minutes
  $$SELECT cleanup_incomplete_onboarding_profiles();$$
);

-- You can also manually run the cleanup function:
-- SELECT cleanup_incomplete_onboarding_profiles();

-- View scheduled jobs:
-- SELECT * FROM cron.job;

-- Remove the job if needed:
-- SELECT cron.unschedule('cleanup-incomplete-onboarding');

COMMENT ON FUNCTION cleanup_incomplete_onboarding_profiles() IS 
  'Automatically deletes user profiles that were created during onboarding (phone verification) but never completed within 30 minutes. This prevents duplicate accounts when users restart onboarding.';
