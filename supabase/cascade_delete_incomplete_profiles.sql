-- Ensure proper cascade deletion for incomplete onboarding profiles
-- When we delete an incomplete profile, we need to clean up related data

-- STEP 1: Clean up orphaned data before adding constraints
-- This removes any references to users that no longer exist

-- Clean up orphaned friendships
DELETE FROM friendships
WHERE requester_id NOT IN (SELECT id FROM user_profiles)
   OR addressee_id NOT IN (SELECT id FROM user_profiles);

-- Log how many were cleaned
DO $$
DECLARE
  deleted_count INTEGER;
BEGIN
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RAISE NOTICE 'Cleaned up % orphaned friendship records', deleted_count;
END $$;

-- Clean up orphaned friend_requests (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
    DELETE FROM friend_requests
    WHERE from_user_id NOT IN (SELECT id FROM user_profiles)
       OR to_user_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned friend_requests records';
  END IF;
END $$;

-- Clean up orphaned user_contacts
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
    DELETE FROM user_contacts
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned user_contacts records';
  END IF;
END $$;

-- Clean up orphaned user_push_tokens
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
    DELETE FROM user_push_tokens
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned user_push_tokens records';
  END IF;
END $$;

-- Clean up orphaned push_notification_queue
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
    DELETE FROM push_notification_queue
    WHERE recipient_user_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned push_notification_queue records';
  END IF;
END $$;

-- Clean up orphaned workouts
DO $$
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
    DELETE FROM workouts
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned workouts records';
  END IF;
END $$;

-- STEP 2: Add cascade delete constraints
-- Now that orphaned data is cleaned up, we can safely add the constraints

-- For friendships table (uses requester_id and addressee_id)
DO $$ 
BEGIN
  -- Drop existing foreign key constraints
  ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_requester_id_fkey;
  ALTER TABLE friendships DROP CONSTRAINT IF EXISTS friendships_addressee_id_fkey;
  
  -- Add them back with CASCADE
  ALTER TABLE friendships 
    ADD CONSTRAINT friendships_requester_id_fkey 
    FOREIGN KEY (requester_id) 
    REFERENCES user_profiles(id) 
    ON DELETE CASCADE;
  
  ALTER TABLE friendships 
    ADD CONSTRAINT friendships_addressee_id_fkey 
    FOREIGN KEY (addressee_id) 
    REFERENCES user_profiles(id) 
    ON DELETE CASCADE;
  
  RAISE NOTICE 'Added cascade delete constraints for friendships table';
END $$;

-- For friend_requests table (if it exists separately)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
    ALTER TABLE friend_requests DROP CONSTRAINT IF EXISTS friend_requests_from_user_id_fkey;
    ALTER TABLE friend_requests DROP CONSTRAINT IF EXISTS friend_requests_to_user_id_fkey;
    
    ALTER TABLE friend_requests 
      ADD CONSTRAINT friend_requests_from_user_id_fkey 
      FOREIGN KEY (from_user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    ALTER TABLE friend_requests 
      ADD CONSTRAINT friend_requests_to_user_id_fkey 
      FOREIGN KEY (to_user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE 'Added cascade delete constraints for friend_requests table';
  END IF;
END $$;

-- For user_contacts table (contact sync data)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
    ALTER TABLE user_contacts DROP CONSTRAINT IF EXISTS user_contacts_user_id_fkey;
    
    ALTER TABLE user_contacts 
      ADD CONSTRAINT user_contacts_user_id_fkey 
      FOREIGN KEY (user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE 'Added cascade delete constraints for user_contacts table';
  END IF;
END $$;

-- For user_push_tokens table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
    ALTER TABLE user_push_tokens DROP CONSTRAINT IF EXISTS user_push_tokens_user_id_fkey;
    
    ALTER TABLE user_push_tokens 
      ADD CONSTRAINT user_push_tokens_user_id_fkey 
      FOREIGN KEY (user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE 'Added cascade delete constraints for user_push_tokens table';
  END IF;
END $$;

-- For push_notification_queue table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
    ALTER TABLE push_notification_queue DROP CONSTRAINT IF EXISTS push_notification_queue_recipient_user_id_fkey;
    
    ALTER TABLE push_notification_queue 
      ADD CONSTRAINT push_notification_queue_recipient_user_id_fkey 
      FOREIGN KEY (recipient_user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE 'Added cascade delete constraints for push_notification_queue table';
  END IF;
END $$;

-- For workouts table (if users can have workouts)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
    ALTER TABLE workouts DROP CONSTRAINT IF EXISTS workouts_user_id_fkey;
    
    ALTER TABLE workouts 
      ADD CONSTRAINT workouts_user_id_fkey 
      FOREIGN KEY (user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE 'Added cascade delete constraints for workouts table';
  END IF;
END $$;

-- STEP 3: Create trigger to clean up auth.users when profile is deleted
-- This creates a trigger that deletes the auth.users record when profile is deleted
CREATE OR REPLACE FUNCTION delete_auth_user_on_profile_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only delete auth user if this was an incomplete onboarding profile
  IF OLD.has_completed_onboarding = false THEN
    DELETE FROM auth.users WHERE id = OLD.id;
    RAISE NOTICE 'Deleted auth.users record for incomplete profile: %', OLD.id;
  END IF;
  
  RETURN OLD;
END;
$$;

-- Create trigger to delete auth user when incomplete profile is deleted
DROP TRIGGER IF EXISTS trigger_delete_auth_user_on_profile_delete ON user_profiles;
CREATE TRIGGER trigger_delete_auth_user_on_profile_delete
  BEFORE DELETE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION delete_auth_user_on_profile_delete();

COMMENT ON FUNCTION delete_auth_user_on_profile_delete() IS 
  'Automatically deletes the auth.users record when an incomplete onboarding profile is deleted. This ensures complete cleanup of abandoned accounts.';

-- Summary
DO $$
BEGIN
  RAISE NOTICE '✅ CASCADE DELETE SETUP COMPLETE';
  RAISE NOTICE '   1. Cleaned up orphaned data';
  RAISE NOTICE '   2. Added cascade delete constraints';
  RAISE NOTICE '   3. Created auth.users cleanup trigger';
  RAISE NOTICE '   When incomplete profiles are deleted, all related data will be automatically cleaned up.';
END $$;
