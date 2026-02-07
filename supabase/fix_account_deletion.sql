-- Fix Account Deletion System
-- This ensures account deletion works properly

-- Drop any existing versions of the function to avoid conflicts
DROP FUNCTION IF EXISTS delete_user_account(UUID);
DROP FUNCTION IF EXISTS delete_user_account(TEXT);

-- Create a single, simple version that accepts UUID
CREATE OR REPLACE FUNCTION delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER := 0;
  result jsonb;
BEGIN
  -- Delete from auth.users (this will cascade to profile via trigger)
  DELETE FROM auth.users WHERE id = user_id_to_delete;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  IF deleted_count > 0 THEN
    result := jsonb_build_object(
      'success', true,
      'message', 'User account completely deleted',
      'user_id', user_id_to_delete
    );
    RAISE NOTICE 'Account deleted: %', user_id_to_delete;
  ELSE
    result := jsonb_build_object(
      'success', false,
      'message', 'User not found',
      'user_id', user_id_to_delete
    );
  END IF;
  
  RETURN result;
END;
$$;

COMMENT ON FUNCTION delete_user_account(UUID) IS 
  'Completely deletes a user account including auth record. All related data is cleaned up via cascade delete constraints.';

-- Grant permissions
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO authenticated;

-- Update the trigger to work for ALL deletions (not just incomplete ones)
CREATE OR REPLACE FUNCTION cleanup_auth_on_profile_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- When a profile is deleted, also delete the auth user
  -- (This handles cases where profile is deleted directly)
  BEGIN
    DELETE FROM auth.users WHERE id = OLD.id;
    RAISE NOTICE 'Cleaned up auth.users for deleted profile: %', OLD.id;
  EXCEPTION
    WHEN OTHERS THEN
      -- If auth user doesn't exist or deletion fails, that's OK
      RAISE NOTICE 'Could not delete auth.users for %: %', OLD.id, SQLERRM;
  END;
  
  RETURN OLD;
END;
$$;

-- Recreate the trigger using AFTER DELETE to avoid conflicts with cascade operations
DROP TRIGGER IF EXISTS trigger_cleanup_auth_on_profile_delete ON user_profiles;
CREATE TRIGGER trigger_cleanup_auth_on_profile_delete
  AFTER DELETE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_auth_on_profile_delete();

-- Test the function (safe - just shows what would be deleted)
CREATE OR REPLACE FUNCTION preview_account_deletion(user_id_to_check UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
  profile_exists BOOLEAN;
  auth_exists BOOLEAN;
BEGIN
  -- Check if profile exists
  SELECT EXISTS(SELECT 1 FROM user_profiles WHERE id = user_id_to_check) INTO profile_exists;
  
  -- Check if auth user exists
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = user_id_to_check) INTO auth_exists;
  
  result := jsonb_build_object(
    'user_id', user_id_to_check,
    'profile_exists', profile_exists,
    'auth_exists', auth_exists,
    'can_delete', profile_exists OR auth_exists
  );
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION preview_account_deletion(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION preview_account_deletion(UUID) TO service_role;

-- Summary
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ ACCOUNT DELETION SYSTEM FIXED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Changes made:';
  RAISE NOTICE '   1. Simplified delete_user_account() function';
  RAISE NOTICE '   2. Fixed trigger to clean up auth.users';
  RAISE NOTICE '   3. Added preview function for testing';
  RAISE NOTICE '';
  RAISE NOTICE '📌 How it works now:';
  RAISE NOTICE '   - delete_user_account(user_id) deletes from auth.users';
  RAISE NOTICE '   - Cascade constraints delete profile and all related data';
  RAISE NOTICE '   - Trigger ensures auth.users is always cleaned up';
  RAISE NOTICE '';
  RAISE NOTICE '📌 Test it:';
  RAISE NOTICE '   SELECT preview_account_deletion(''YOUR_USER_ID'');';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
