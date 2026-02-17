-- ============================================================
-- FIX: Challenge Participants Table
-- 
-- Problem 1: column "role" does not exist
--   The create_challenge RPC references a "role" column that's missing
--
-- Problem 2: infinite recursion in RLS policy
--   A SELECT policy on challenge_participants queries itself, causing recursion
--
-- Solution: Add the missing column + replace policies with simple non-recursive ones
-- ============================================================

-- Step 1: Add the missing "role" column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'challenge_participants' 
        AND column_name = 'role'
    ) THEN
        ALTER TABLE challenge_participants 
        ADD COLUMN role TEXT DEFAULT 'participant';
        
        RAISE NOTICE '✅ Added "role" column to challenge_participants';
    ELSE
        RAISE NOTICE 'ℹ️ "role" column already exists';
    END IF;
END $$;

-- Step 2: Drop ALL existing policies (the recursive ones)
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'challenge_participants'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON challenge_participants', pol.policyname);
        RAISE NOTICE 'Dropped policy: %', pol.policyname;
    END LOOP;
END $$;

-- Step 3: Enable RLS (in case it was disabled)
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;

-- Step 4: Create simple, non-recursive policies
-- All challenge data is accessed through SECURITY DEFINER RPCs,
-- so direct table policies just need to be simple and non-recursive.

-- SELECT: Users can see their own rows + rows in challenges they created
CREATE POLICY "cp_select_own"
ON challenge_participants FOR SELECT
USING (
    user_id = auth.uid()
);

-- SELECT: Challenge creators can see all participants
CREATE POLICY "cp_select_creator"
ON challenge_participants FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM group_challenges gc 
        WHERE gc.id = challenge_participants.challenge_id 
        AND gc.created_by = auth.uid()
    )
);

-- INSERT: Allow inserts (RPCs handle authorization)
CREATE POLICY "cp_insert"
ON challenge_participants FOR INSERT
WITH CHECK (
    -- User is adding themselves OR is the challenge creator
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM group_challenges gc 
        WHERE gc.id = challenge_participants.challenge_id 
        AND gc.created_by = auth.uid()
    )
);

-- UPDATE: Users can update their own participation only
CREATE POLICY "cp_update_own"
ON challenge_participants FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DELETE: Users can remove their own participation
CREATE POLICY "cp_delete_own"
ON challenge_participants FOR DELETE
USING (user_id = auth.uid());

-- Step 5: Verify
DO $$
BEGIN
    RAISE NOTICE '✅ Challenge participants table fixed:';
    RAISE NOTICE '   - "role" column exists';
    RAISE NOTICE '   - Non-recursive RLS policies applied';
    RAISE NOTICE '   - Policies: cp_select_own, cp_select_creator, cp_insert, cp_update_own, cp_delete_own';
END $$;
