-- ============================================================================
-- FIX C-5: Comprehensive RLS Hardening for Challenge Tables
-- ============================================================================
-- Date: March 6, 2026
-- Source: MASTER_TODO.md item C-5
--
-- PROBLEM:
--   group_challenges      → RLS NOT ENABLED (fully open to any authenticated user)
--   group_challenge_nudges → RLS NOT ENABLED (fully open)
--   group_challenge_members → RLS intentionally disabled (accessed only via SECURITY DEFINER RPCs)
--
-- WHAT THIS FIXES:
--   1. Enables RLS on group_challenges with proper INSERT/UPDATE/DELETE scoping
--   2. Enables RLS on group_challenge_nudges with SELECT scoping
--   3. Leaves group_challenge_members as-is (documented conscious decision)
--
-- SAFE BECAUSE:
--   - All iOS direct table access patterns are covered by the new policies
--   - All RPC functions use SECURITY DEFINER (bypass RLS entirely)
--   - Realtime subscriptions use SELECT policies; we use USING(true) on
--     group_challenges to avoid circular RLS recursion with challenge_participants
--     (which references group_challenges in its cp_select_creator policy)
--   - CASCADE DELETEs (foreign key) bypass RLS — no extra policies needed
--
-- RUN IN: Supabase Dashboard → SQL Editor
-- ============================================================================


-- ============================================================================
-- PART 1: group_challenges — Enable RLS + Add Policies
-- ============================================================================
-- Currently: NO RLS — any authenticated user can read/write/delete any row
-- iOS direct access:
--   INSERT: ChallengeService.swift creates challenges (created_by = auth.uid())
--   DELETE: SupabaseManager.swift deletes user's challenges on account deletion
-- Realtime: Unfiltered UPDATE subscription in RealtimeService.swift
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'group_challenges'
    ) THEN
        RAISE NOTICE '⏭️ group_challenges table does not exist — skipping';
        RETURN;
    END IF;

    -- Enable RLS
    ALTER TABLE group_challenges ENABLE ROW LEVEL SECURITY;
    RAISE NOTICE '✅ RLS enabled on group_challenges';
END $$;

-- SELECT: All authenticated users can view challenge metadata.
-- WHY USING(true): Avoids circular RLS recursion with challenge_participants
-- (cp_select_creator references group_challenges). Also ensures Realtime
-- events are delivered to all subscribers. Challenge metadata (title, type,
-- dates, status) is low-sensitivity; personal data lives in
-- challenge_daily_progress which has proper user-scoped policies.
DROP POLICY IF EXISTS "gc_select" ON group_challenges;
CREATE POLICY "gc_select"
    ON group_challenges FOR SELECT
    TO authenticated
    USING (true);

-- INSERT: Only the creator can insert (created_by must match auth.uid())
DROP POLICY IF EXISTS "gc_insert" ON group_challenges;
CREATE POLICY "gc_insert"
    ON group_challenges FOR INSERT
    TO authenticated
    WITH CHECK (created_by = auth.uid());

-- UPDATE: Only the creator can update their challenges
DROP POLICY IF EXISTS "gc_update" ON group_challenges;
CREATE POLICY "gc_update"
    ON group_challenges FOR UPDATE
    TO authenticated
    USING (created_by = auth.uid());

-- DELETE: Only the creator can delete (used by account deletion flow)
DROP POLICY IF EXISTS "gc_delete" ON group_challenges;
CREATE POLICY "gc_delete"
    ON group_challenges FOR DELETE
    TO authenticated
    USING (created_by = auth.uid());


-- ============================================================================
-- PART 2: group_challenge_nudges — Enable RLS + Add Policies
-- ============================================================================
-- Currently: NO RLS — any authenticated user can read/write/delete nudges
-- iOS direct access: NONE (all via nudge_group_challenge_member RPC)
-- Schema: (id, challenge_id, sender_id, recipient_id, created_at)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'group_challenge_nudges'
    ) THEN
        RAISE NOTICE '⏭️ group_challenge_nudges table does not exist — skipping';
        RETURN;
    END IF;

    ALTER TABLE group_challenge_nudges ENABLE ROW LEVEL SECURITY;
    RAISE NOTICE '✅ RLS enabled on group_challenge_nudges';
END $$;

-- SELECT: Only the sender or recipient can see nudge records
DROP POLICY IF EXISTS "gcn_select" ON group_challenge_nudges;
CREATE POLICY "gcn_select"
    ON group_challenge_nudges FOR SELECT
    TO authenticated
    USING (sender_id = auth.uid() OR recipient_id = auth.uid());

-- No INSERT/UPDATE/DELETE policies — all writes go through
-- nudge_group_challenge_member RPC (SECURITY DEFINER, bypasses RLS).
-- Direct API attempts will be blocked, which is the intended behavior.


-- ============================================================================
-- PART 3: group_challenge_members — Documented No-Op
-- ============================================================================
-- RLS was intentionally disabled in fix_group_challenge_members_recursion.sql
-- to resolve infinite recursion. This table is ONLY accessed via SECURITY
-- DEFINER RPCs. Leaving as-is is a conscious security decision.
-- See: fix_group_challenge_members_recursion.sql for full rationale.
-- ============================================================================


-- ============================================================================
-- PART 4: Verification
-- ============================================================================

DO $$
DECLARE
    v_rls_gc BOOLEAN;
    v_rls_gcn BOOLEAN;
    v_gc_policies INT;
    v_gcn_policies INT;
BEGIN
    -- Check group_challenges RLS
    SELECT rowsecurity INTO v_rls_gc
    FROM pg_tables
    WHERE tablename = 'group_challenges' AND schemaname = 'public';

    SELECT COUNT(*) INTO v_gc_policies
    FROM pg_policies
    WHERE tablename = 'group_challenges' AND schemaname = 'public';

    -- Check group_challenge_nudges RLS
    SELECT rowsecurity INTO v_rls_gcn
    FROM pg_tables
    WHERE tablename = 'group_challenge_nudges' AND schemaname = 'public';

    SELECT COUNT(*) INTO v_gcn_policies
    FROM pg_policies
    WHERE tablename = 'group_challenge_nudges' AND schemaname = 'public';

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  C-5 RLS HARDENING — VERIFICATION';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';

    IF v_rls_gc THEN
        RAISE NOTICE '  ✅ group_challenges: RLS ENABLED (% policies)', v_gc_policies;
    ELSE
        RAISE NOTICE '  ❌ group_challenges: RLS NOT enabled';
    END IF;

    IF v_rls_gcn THEN
        RAISE NOTICE '  ✅ group_challenge_nudges: RLS ENABLED (% policies)', v_gcn_policies;
    ELSE
        RAISE NOTICE '  ❌ group_challenge_nudges: RLS NOT enabled';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '  Expected policies:';
    RAISE NOTICE '    group_challenges:      4 (SELECT, INSERT, UPDATE, DELETE)';
    RAISE NOTICE '    group_challenge_nudges: 1 (SELECT only — writes via RPC)';
    RAISE NOTICE '';
    RAISE NOTICE '  group_challenge_members: RLS intentionally disabled';
    RAISE NOTICE '    (accessed only via SECURITY DEFINER RPCs)';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Show all challenge-related RLS policies for manual review:
SELECT
    tablename,
    policyname,
    cmd AS operation,
    qual AS using_clause,
    with_check AS with_check_clause
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'group_challenges',
    'group_challenge_nudges',
    'challenge_participants',
    'challenge_daily_progress'
  )
ORDER BY tablename, policyname;
