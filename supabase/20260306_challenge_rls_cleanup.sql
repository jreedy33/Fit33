-- ============================================================================
-- CLEANUP: Remove duplicate/redundant RLS policies on challenge tables
-- ============================================================================
-- Run AFTER 20260306_challenge_rls_hardening.sql
--
-- Enabling RLS on group_challenges and group_challenge_nudges activated
-- dormant policies that were created earlier but never took effect.
-- This cleans up the duplicates, keeping one canonical policy per operation.
-- ============================================================================


-- ============================================================================
-- PART 1: group_challenges — Drop old redundant policies
-- ============================================================================
-- Keep: gc_select (true), gc_insert, gc_update, gc_delete
-- Drop: old policies that duplicate the same operations

-- Old SELECT references group_challenge_members (fragile dependency on a
-- table with RLS disabled). gc_select USING(true) is the correct approach.
DROP POLICY IF EXISTS "Users can view their group challenges" ON group_challenges;

-- Old INSERT — identical to gc_insert
DROP POLICY IF EXISTS "Users can create group challenges" ON group_challenges;

-- Old UPDATE — identical to gc_update
DROP POLICY IF EXISTS "Creator can update group challenges" ON group_challenges;


-- ============================================================================
-- PART 2: group_challenge_nudges — Drop old redundant SELECT
-- ============================================================================
-- Keep: gcn_select (sender/recipient), "Members can insert nudges"
-- Drop: old SELECT that references group_challenge_members

DROP POLICY IF EXISTS "Members can view nudges for their challenges" ON group_challenge_nudges;


-- ============================================================================
-- PART 3: challenge_daily_progress — Deduplicate pre-existing policies
-- ============================================================================
-- The ALL policy (challenge_progress_all) covers SELECT/INSERT/UPDATE/DELETE
-- for user_id = auth.uid(). The individual policies add cross-challenge
-- visibility (seeing opponent progress). Keep the useful ones, drop true dupes.

-- These two INSERT policies are identical — drop one
DROP POLICY IF EXISTS "Users can log own progress" ON challenge_daily_progress;

-- The "View progress of joined challenges" SELECT overlaps with
-- "Users can view progress in their challenges" — keep the simpler one
DROP POLICY IF EXISTS "View progress of joined challenges" ON challenge_daily_progress;


-- ============================================================================
-- PART 4: Verification — show final clean state
-- ============================================================================

SELECT
    tablename,
    policyname,
    cmd AS operation
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'group_challenges',
    'group_challenge_nudges',
    'challenge_participants',
    'challenge_daily_progress'
  )
ORDER BY tablename, policyname;
