-- Fix cascade delete for challenge-related tables
-- This allows users to be deleted even if they created/participated in challenges

-- STEP 1: Clean up orphaned data first
DO $$
BEGIN
  RAISE NOTICE 'Cleaning up orphaned challenge data...';
  
  -- Clean up group_challenges with non-existent creators
  DELETE FROM group_challenges
  WHERE created_by NOT IN (SELECT id FROM user_profiles);
  RAISE NOTICE 'Cleaned up orphaned group_challenges';
  
  -- Clean up challenge_participants with non-existent users
  DELETE FROM challenge_participants
  WHERE user_id NOT IN (SELECT id FROM user_profiles);
  RAISE NOTICE 'Cleaned up orphaned challenge_participants (by user_id)';
  
  -- Clean up challenge_participants with non-existent challenges
  DELETE FROM challenge_participants
  WHERE challenge_id NOT IN (SELECT id FROM group_challenges);
  RAISE NOTICE 'Cleaned up orphaned challenge_participants (by challenge_id)';
  
  -- Clean up group_challenge_members if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'group_challenge_members') THEN
    -- Check if user_id column exists
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'user_id') THEN
      DELETE FROM group_challenge_members
      WHERE user_id NOT IN (SELECT id FROM user_profiles);
      RAISE NOTICE 'Cleaned up orphaned group_challenge_members (by user_id)';
    END IF;
    
    -- Check if group_challenge_id column exists (might be named differently)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'group_challenge_id') THEN
      DELETE FROM group_challenge_members
      WHERE group_challenge_id NOT IN (SELECT id FROM group_challenges);
      RAISE NOTICE 'Cleaned up orphaned group_challenge_members (by group_challenge_id)';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'challenge_id') THEN
      DELETE FROM group_challenge_members
      WHERE challenge_id NOT IN (SELECT id FROM group_challenges);
      RAISE NOTICE 'Cleaned up orphaned group_challenge_members (by challenge_id)';
    END IF;
  END IF;
  
  -- Clean up challenge_daily_progress if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'challenge_daily_progress') THEN
    DELETE FROM challenge_daily_progress
    WHERE user_id NOT IN (SELECT id FROM user_profiles);
    DELETE FROM challenge_daily_progress
    WHERE challenge_id NOT IN (SELECT id FROM group_challenges);
    RAISE NOTICE 'Cleaned up orphaned challenge_daily_progress';
  END IF;
  
  -- Clean up challenge_invites if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'challenge_invites') THEN
    DELETE FROM challenge_invites
    WHERE from_user_id NOT IN (SELECT id FROM user_profiles)
       OR to_user_id NOT IN (SELECT id FROM user_profiles);
    DELETE FROM challenge_invites
    WHERE challenge_id NOT IN (SELECT id FROM group_challenges);
    RAISE NOTICE 'Cleaned up orphaned challenge_invites';
  END IF;
  
  -- Clean up shared_workouts if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'shared_workouts') THEN
    DELETE FROM shared_workouts
    WHERE sender_id NOT IN (SELECT id FROM user_profiles)
       OR recipient_id NOT IN (SELECT id FROM user_profiles);
    RAISE NOTICE 'Cleaned up orphaned shared_workouts';
  END IF;
  
  -- Clean up group_challenge_nudges if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'group_challenge_nudges') THEN
    -- Check each column exists before cleaning
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'sender_id') THEN
      EXECUTE 'DELETE FROM group_challenge_nudges WHERE sender_id NOT IN (SELECT id FROM user_profiles)';
      RAISE NOTICE 'Cleaned up orphaned group_challenge_nudges (by sender_id)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'recipient_id') THEN
      EXECUTE 'DELETE FROM group_challenge_nudges WHERE recipient_id NOT IN (SELECT id FROM user_profiles)';
      RAISE NOTICE 'Cleaned up orphaned group_challenge_nudges (by recipient_id)';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'challenge_id') THEN
      EXECUTE 'DELETE FROM group_challenge_nudges WHERE challenge_id NOT IN (SELECT id FROM group_challenges)';
      RAISE NOTICE 'Cleaned up orphaned group_challenge_nudges (by challenge_id)';
    END IF;
  END IF;
  
  -- Clean up contact_joined_notifications if it exists
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'contact_joined_notifications') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contact_joined_notifications' AND column_name = 'user_id') THEN
      DELETE FROM contact_joined_notifications
      WHERE user_id NOT IN (SELECT id FROM user_profiles);
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contact_joined_notifications' AND column_name = 'new_user_id') THEN
      DELETE FROM contact_joined_notifications
      WHERE new_user_id NOT IN (SELECT id FROM user_profiles);
    END IF;
    RAISE NOTICE 'Cleaned up orphaned contact_joined_notifications';
  END IF;
  
  RAISE NOTICE '✅ All orphaned challenge data cleaned up';
END $$;

-- STEP 2: Now add cascade delete constraints

-- Fix group_challenges table (created_by foreign key)
DO $$ 
BEGIN
  -- Drop existing constraint
  ALTER TABLE group_challenges DROP CONSTRAINT IF EXISTS group_challenges_created_by_fkey;
  
  -- Add it back with CASCADE
  ALTER TABLE group_challenges 
    ADD CONSTRAINT group_challenges_created_by_fkey 
    FOREIGN KEY (created_by) 
    REFERENCES user_profiles(id) 
    ON DELETE CASCADE;
  
  RAISE NOTICE '✅ group_challenges.created_by now cascades on delete';
END $$;

-- Fix challenge_participants table
DO $$ 
BEGIN
  -- Drop existing constraints
  ALTER TABLE challenge_participants DROP CONSTRAINT IF EXISTS challenge_participants_user_id_fkey;
  ALTER TABLE challenge_participants DROP CONSTRAINT IF EXISTS challenge_participants_challenge_id_fkey;
  
  -- Add them back with CASCADE
  ALTER TABLE challenge_participants 
    ADD CONSTRAINT challenge_participants_user_id_fkey 
    FOREIGN KEY (user_id) 
    REFERENCES user_profiles(id) 
    ON DELETE CASCADE;
  
  ALTER TABLE challenge_participants 
    ADD CONSTRAINT challenge_participants_challenge_id_fkey 
    FOREIGN KEY (challenge_id) 
    REFERENCES group_challenges(id) 
    ON DELETE CASCADE;
  
  RAISE NOTICE '✅ challenge_participants now cascades on delete';
END $$;

-- Fix challenge_daily_progress table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'challenge_daily_progress') THEN
    ALTER TABLE challenge_daily_progress DROP CONSTRAINT IF EXISTS challenge_daily_progress_user_id_fkey;
    ALTER TABLE challenge_daily_progress DROP CONSTRAINT IF EXISTS challenge_daily_progress_challenge_id_fkey;
    
    ALTER TABLE challenge_daily_progress 
      ADD CONSTRAINT challenge_daily_progress_user_id_fkey 
      FOREIGN KEY (user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    ALTER TABLE challenge_daily_progress 
      ADD CONSTRAINT challenge_daily_progress_challenge_id_fkey 
      FOREIGN KEY (challenge_id) 
      REFERENCES group_challenges(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE '✅ challenge_daily_progress now cascades on delete';
  END IF;
END $$;

-- Fix challenge_invites table (if it exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'challenge_invites') THEN
    ALTER TABLE challenge_invites DROP CONSTRAINT IF EXISTS challenge_invites_from_user_id_fkey;
    ALTER TABLE challenge_invites DROP CONSTRAINT IF EXISTS challenge_invites_to_user_id_fkey;
    ALTER TABLE challenge_invites DROP CONSTRAINT IF EXISTS challenge_invites_challenge_id_fkey;
    
    ALTER TABLE challenge_invites 
      ADD CONSTRAINT challenge_invites_from_user_id_fkey 
      FOREIGN KEY (from_user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    ALTER TABLE challenge_invites 
      ADD CONSTRAINT challenge_invites_to_user_id_fkey 
      FOREIGN KEY (to_user_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    ALTER TABLE challenge_invites 
      ADD CONSTRAINT challenge_invites_challenge_id_fkey 
      FOREIGN KEY (challenge_id) 
      REFERENCES group_challenges(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE '✅ challenge_invites now cascades on delete';
  END IF;
END $$;

-- Fix shared_workouts table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'shared_workouts') THEN
    ALTER TABLE shared_workouts DROP CONSTRAINT IF EXISTS shared_workouts_sender_id_fkey;
    ALTER TABLE shared_workouts DROP CONSTRAINT IF EXISTS shared_workouts_recipient_id_fkey;
    
    ALTER TABLE shared_workouts 
      ADD CONSTRAINT shared_workouts_sender_id_fkey 
      FOREIGN KEY (sender_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    ALTER TABLE shared_workouts 
      ADD CONSTRAINT shared_workouts_recipient_id_fkey 
      FOREIGN KEY (recipient_id) 
      REFERENCES user_profiles(id) 
      ON DELETE CASCADE;
    
    RAISE NOTICE '✅ shared_workouts now cascades on delete';
  END IF;
END $$;

-- Fix group_challenge_members table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'group_challenge_members') THEN
    -- Check for user_id column
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'user_id') THEN
      ALTER TABLE group_challenge_members DROP CONSTRAINT IF EXISTS group_challenge_members_user_id_fkey;
      
      ALTER TABLE group_challenge_members 
        ADD CONSTRAINT group_challenge_members_user_id_fkey 
        FOREIGN KEY (user_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_members.user_id now cascades on delete';
    END IF;
    
    -- Check for challenge foreign key (could be challenge_id or group_challenge_id)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'group_challenge_id') THEN
      ALTER TABLE group_challenge_members DROP CONSTRAINT IF EXISTS group_challenge_members_group_challenge_id_fkey;
      
      ALTER TABLE group_challenge_members 
        ADD CONSTRAINT group_challenge_members_group_challenge_id_fkey 
        FOREIGN KEY (group_challenge_id) 
        REFERENCES group_challenges(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_members.group_challenge_id now cascades on delete';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_members' AND column_name = 'challenge_id') THEN
      ALTER TABLE group_challenge_members DROP CONSTRAINT IF EXISTS group_challenge_members_challenge_id_fkey;
      
      ALTER TABLE group_challenge_members 
        ADD CONSTRAINT group_challenge_members_challenge_id_fkey 
        FOREIGN KEY (challenge_id) 
        REFERENCES group_challenges(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_members.challenge_id now cascades on delete';
    END IF;
  END IF;
END $$;

-- Fix group_challenge_nudges table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'group_challenge_nudges') THEN
    -- sender_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'sender_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_sender_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_sender_id_fkey 
        FOREIGN KEY (sender_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
    END IF;
    
    -- recipient_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'recipient_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_recipient_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_recipient_id_fkey 
        FOREIGN KEY (recipient_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
    END IF;
    
    -- challenge_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'challenge_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_challenge_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_challenge_id_fkey 
        FOREIGN KEY (challenge_id) 
        REFERENCES group_challenges(id) 
        ON DELETE CASCADE;
    END IF;
    
    RAISE NOTICE '✅ group_challenge_nudges now cascades on delete';
  END IF;
END $$;

-- Fix group_challenge_nudges table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'group_challenge_nudges') THEN
    -- sender_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'sender_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_sender_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_sender_id_fkey 
        FOREIGN KEY (sender_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_nudges.sender_id now cascades on delete';
    END IF;
    
    -- recipient_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'recipient_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_recipient_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_recipient_id_fkey 
        FOREIGN KEY (recipient_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_nudges.recipient_id now cascades on delete';
    END IF;
    
    -- challenge_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'group_challenge_nudges' AND column_name = 'challenge_id') THEN
      ALTER TABLE group_challenge_nudges DROP CONSTRAINT IF EXISTS group_challenge_nudges_challenge_id_fkey;
      
      ALTER TABLE group_challenge_nudges 
        ADD CONSTRAINT group_challenge_nudges_challenge_id_fkey 
        FOREIGN KEY (challenge_id) 
        REFERENCES group_challenges(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ group_challenge_nudges.challenge_id now cascades on delete';
    END IF;
  END IF;
END $$;

-- Fix contact_joined_notifications table
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'contact_joined_notifications') THEN
    -- Find the actual column name for the user reference
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'contact_joined_notifications' 
      AND column_name = 'user_id'
    ) THEN
      ALTER TABLE contact_joined_notifications DROP CONSTRAINT IF EXISTS contact_joined_notifications_user_id_fkey;
      
      ALTER TABLE contact_joined_notifications 
        ADD CONSTRAINT contact_joined_notifications_user_id_fkey 
        FOREIGN KEY (user_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ contact_joined_notifications.user_id now cascades on delete';
    END IF;
    
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'contact_joined_notifications' 
      AND column_name = 'new_user_id'
    ) THEN
      ALTER TABLE contact_joined_notifications DROP CONSTRAINT IF EXISTS contact_joined_notifications_new_user_id_fkey;
      
      ALTER TABLE contact_joined_notifications 
        ADD CONSTRAINT contact_joined_notifications_new_user_id_fkey 
        FOREIGN KEY (new_user_id) 
        REFERENCES user_profiles(id) 
        ON DELETE CASCADE;
      
      RAISE NOTICE '✅ contact_joined_notifications.new_user_id now cascades on delete';
    END IF;
  END IF;
END $$;

-- Summary
DO $$
BEGIN
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '✅ CHALLENGE CASCADE DELETE FIXED';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';
  RAISE NOTICE '📌 All challenge-related foreign keys now cascade:';
  RAISE NOTICE '   - group_challenges (created_by)';
  RAISE NOTICE '   - challenge_participants (user_id, challenge_id)';
  RAISE NOTICE '   - group_challenge_members (user_id)';
  RAISE NOTICE '   - group_challenge_nudges (sender_id, recipient_id)';
  RAISE NOTICE '   - challenge_daily_progress (user_id, challenge_id)';
  RAISE NOTICE '   - challenge_invites (from_user_id, to_user_id)';
  RAISE NOTICE '   - shared_workouts (sender_id, recipient_id)';
  RAISE NOTICE '   - contact_joined_notifications';
  RAISE NOTICE '';
  RAISE NOTICE '✅ You can now delete user accounts without errors!';
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
