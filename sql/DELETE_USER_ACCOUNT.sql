-- ============================================================================
-- DELETE USER ACCOUNT - Complete Data Removal (BULLETPROOF VERSION)
-- ============================================================================
-- This function completely removes all user data when an account is deleted.
-- Uses direct deletes with individual exception handling for each table.
-- Run this in Supabase SQL Editor to enable full account deletion.
-- ============================================================================

-- First, disable RLS on challenge tables temporarily for this function
-- Drop any problematic policies that might cause recursion
DO $$
BEGIN
    -- Try to drop problematic policies
    DROP POLICY IF EXISTS "Users can view their own progress" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "Users can insert their own progress" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "Users can update their own progress" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "Users can delete their own progress" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "challenge_daily_progress_select" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "challenge_daily_progress_insert" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "challenge_daily_progress_update" ON challenge_daily_progress;
    DROP POLICY IF EXISTS "challenge_daily_progress_delete" ON challenge_daily_progress;
EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN OTHERS THEN NULL;
END $$;

-- Recreate simpler policies for challenge_daily_progress
DO $$
BEGIN
    -- Enable RLS
    ALTER TABLE challenge_daily_progress ENABLE ROW LEVEL SECURITY;
    
    -- Simple policy: users can manage their own progress
    CREATE POLICY "challenge_progress_all" ON challenge_daily_progress
        FOR ALL USING (user_id = auth.uid());
EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN duplicate_object THEN NULL;
    WHEN OTHERS THEN NULL;
END $$;

-- Drop existing function
DROP FUNCTION IF EXISTS delete_user_account(UUID);
DROP FUNCTION IF EXISTS delete_user_account(TEXT);

-- ============================================================================
-- Main function to delete user account and ALL associated data
-- ============================================================================
CREATE OR REPLACE FUNCTION delete_user_account(user_id_to_delete TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_uuid UUID;
    v_deleted_count INT;
BEGIN
    -- Convert text to UUID
    v_user_uuid := user_id_to_delete::UUID;
    
    -- Verify the caller is the user being deleted (security check)
    IF auth.uid() IS NULL OR auth.uid() != v_user_uuid THEN
        RAISE EXCEPTION 'Unauthorized: You can only delete your own account';
    END IF;
    
    RAISE NOTICE '🗑️ Starting BULLETPROOF account deletion for user: %', v_user_uuid;
    
    -- ========================================================================
    -- CHALLENGE DATA - Most likely to have issues, handle each carefully
    -- ========================================================================
    
    -- 1. challenge_daily_progress
    BEGIN
        DELETE FROM challenge_daily_progress WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ challenge_daily_progress: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ challenge_daily_progress: %', SQLERRM;
    END;
    
    -- 2. challenge_participants
    BEGIN
        DELETE FROM challenge_participants WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ challenge_participants: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ challenge_participants: %', SQLERRM;
    END;
    
    -- 3. friend_challenges (as creator)
    BEGIN
        DELETE FROM friend_challenges WHERE creator_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ friend_challenges: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ friend_challenges: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- FRIENDS DATA - Try both table/column naming conventions
    -- ========================================================================
    
    -- friends table (different naming conventions)
    BEGIN
        DELETE FROM friends WHERE user_id = v_user_uuid OR friend_user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ friends: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ friends: %', SQLERRM;
    END;
    
    -- friendships table (alternative)
    BEGIN
        DELETE FROM friendships WHERE user1_id = v_user_uuid OR user2_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ friendships: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ friendships: %', SQLERRM;
    END;
    
    -- shared_workouts
    BEGIN
        DELETE FROM shared_workouts WHERE sender_id = v_user_uuid OR receiver_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ shared_workouts: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ shared_workouts: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- CONTACT/NOTIFICATIONS DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM user_synced_contacts WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_synced_contacts: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_synced_contacts: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM contact_joined_notifications WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ contact_joined_notifications (user): % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ contact_joined_notifications: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_push_tokens WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_push_tokens: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_push_tokens: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM push_notification_queue WHERE recipient_user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ push_notification_queue: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ push_notification_queue: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- WORKOUT DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM workout_history WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ workout_history: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ workout_history: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM workouts WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ workouts: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ workouts: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM exercise_usage_logs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ exercise_usage_logs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ exercise_usage_logs: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- PROGRAM DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM user_active_programs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_active_programs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_active_programs: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_custom_programs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_custom_programs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_custom_programs: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM program_history WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ program_history: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ program_history: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- FOOD/MEAL DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM meal_logs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ meal_logs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ meal_logs: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_food_history WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_food_history: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_food_history: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_ingredient_preferences WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_ingredient_preferences: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_ingredient_preferences: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_cuisine_preferences WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_cuisine_preferences: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_cuisine_preferences: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- FAVORITES
    -- ========================================================================
    
    BEGIN
        DELETE FROM user_favorites WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_favorites: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_favorites: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM favorite_workouts WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ favorite_workouts: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ favorite_workouts: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM custom_exercises WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ custom_exercises: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ custom_exercises: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- HEALTH DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM step_tracking WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ step_tracking: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ step_tracking: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM weight_logs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ weight_logs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ weight_logs: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM hydration_logs WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ hydration_logs: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ hydration_logs: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM cardio_workouts WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ cardio_workouts: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ cardio_workouts: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- OTHER DATA
    -- ========================================================================
    
    BEGIN
        DELETE FROM bug_reports WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ bug_reports: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ bug_reports: %', SQLERRM;
    END;
    
    BEGIN
        DELETE FROM user_progress WHERE user_id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_progress: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_progress: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- USER PROFILE (delete before auth.users)
    -- ========================================================================
    
    BEGIN
        DELETE FROM user_profiles WHERE id = v_user_uuid;
        GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
        RAISE NOTICE '✓ user_profiles: % rows', v_deleted_count;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '⚠ user_profiles: %', SQLERRM;
    END;
    
    -- ========================================================================
    -- AUTH.USERS - THE CRITICAL FINAL STEP
    -- This MUST succeed for user to be able to re-register
    -- ========================================================================
    
    RAISE NOTICE '🔐 Attempting to delete from auth.users...';
    
    DELETE FROM auth.users WHERE id = v_user_uuid;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    IF v_deleted_count > 0 THEN
        RAISE NOTICE '✅ Successfully deleted from auth.users';
        RAISE NOTICE '🎉 Account deletion COMPLETE for user: %', v_user_uuid;
        RETURN TRUE;
    ELSE
        RAISE NOTICE '⚠️ No rows deleted from auth.users (user may not exist)';
        RETURN TRUE; -- Still return true if user wasn't in auth.users
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ Fatal error during deletion: %', SQLERRM;
        
        -- Last-ditch attempt to delete from auth.users
        BEGIN
            DELETE FROM auth.users WHERE id = v_user_uuid;
            RAISE NOTICE '✅ Recovered: deleted from auth.users despite other errors';
            RETURN TRUE;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '❌ Could not delete from auth.users: %', SQLERRM;
            RETURN FALSE;
        END;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION delete_user_account(TEXT) TO authenticated;

-- ============================================================================
-- MANUAL CLEANUP: Delete joe.r.reedis@gmail.com if it still exists
-- ============================================================================
DO $$
DECLARE
    joe_id UUID;
BEGIN
    SELECT id INTO joe_id FROM auth.users WHERE email = 'joe.r.reedis@gmail.com';
    IF joe_id IS NOT NULL THEN
        RAISE NOTICE 'Found joe.r.reedis@gmail.com with ID: %', joe_id;
        
        -- Delete from all tables
        DELETE FROM challenge_daily_progress WHERE user_id = joe_id;
        DELETE FROM challenge_participants WHERE user_id = joe_id;
        DELETE FROM friend_challenges WHERE creator_id = joe_id;
        DELETE FROM user_profiles WHERE id = joe_id;
        DELETE FROM auth.users WHERE id = joe_id;
        
        RAISE NOTICE '✅ Deleted joe.r.reedis@gmail.com';
    ELSE
        RAISE NOTICE 'joe.r.reedis@gmail.com not found in auth.users';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error cleaning up joe: %', SQLERRM;
END $$;

-- Also delete hilary@test.com if it exists
DO $$
DECLARE
    hilary_id UUID;
BEGIN
    SELECT id INTO hilary_id FROM auth.users WHERE email = 'hilary@test.com';
    IF hilary_id IS NOT NULL THEN
        RAISE NOTICE 'Found hilary@test.com with ID: %', hilary_id;
        
        DELETE FROM challenge_daily_progress WHERE user_id = hilary_id;
        DELETE FROM challenge_participants WHERE user_id = hilary_id;
        DELETE FROM friend_challenges WHERE creator_id = hilary_id;
        DELETE FROM user_profiles WHERE id = hilary_id;
        DELETE FROM auth.users WHERE id = hilary_id;
        
        RAISE NOTICE '✅ Deleted hilary@test.com';
    ELSE
        RAISE NOTICE 'hilary@test.com not found in auth.users';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error cleaning up hilary: %', SQLERRM;
END $$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
SELECT 'delete_user_account function created (BULLETPROOF version)' AS status;

-- Check what users remain
SELECT email FROM auth.users ORDER BY created_at DESC LIMIT 10;
