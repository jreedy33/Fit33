-- ============================================================================
-- FIX: Infinite Recursion in group_challenge_members RLS Policy
-- ============================================================================
-- DISCOVERED BY: Social System Simulator (Feb 25, 2026)
--
-- PROBLEM: The `group_challenge_members` table has an RLS policy that causes
-- infinite recursion, blocking ALL challenge reads/writes that touch this table.
--
-- The app uses `challenge_participants` (not group_challenge_members) for all
-- challenge logic, and ALL RPCs are SECURITY DEFINER (bypass RLS anyway).
-- So the safest fix is: drop the bad policies and disable RLS on this table.
-- ============================================================================

-- Step 1: Drop ALL existing RLS policies (they cause infinite recursion)
DO $$
DECLARE
    pol_name TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'group_challenge_members'
    ) THEN
        RAISE NOTICE '✅ group_challenge_members does not exist — nothing to fix';
        RETURN;
    END IF;

    FOR pol_name IN
        SELECT policyname FROM pg_policies
        WHERE tablename = 'group_challenge_members' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON group_challenge_members', pol_name);
        RAISE NOTICE 'Dropped policy: %', pol_name;
    END LOOP;

    -- Disable RLS entirely — this table is accessed through SECURITY DEFINER RPCs
    ALTER TABLE group_challenge_members DISABLE ROW LEVEL SECURITY;
    RAISE NOTICE '✅ RLS disabled on group_challenge_members — infinite recursion fixed';
END $$;
