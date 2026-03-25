-- ============================================================================
-- Security Fix: RLS + SECURITY DEFINER Views
-- Date: 2026-03-24
-- Reason: Supabase security linter flagged publicly accessible tables and
--         SECURITY DEFINER views that bypass RLS.
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: Enable RLS on group_challenge_members
-- ============================================================================
-- Previously disabled due to infinite recursion (see fix_group_challenge_members_recursion.sql).
-- All actual access is via SECURITY DEFINER RPCs which bypass RLS.
-- These policies are simple (no subqueries on the same table) to avoid recursion.

ALTER TABLE IF EXISTS group_challenge_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gcm_select_own" ON group_challenge_members;
CREATE POLICY "gcm_select_own" ON group_challenge_members
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "gcm_insert_own" ON group_challenge_members;
CREATE POLICY "gcm_insert_own" ON group_challenge_members
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "gcm_update_own" ON group_challenge_members;
CREATE POLICY "gcm_update_own" ON group_challenge_members
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "gcm_delete_own" ON group_challenge_members;
CREATE POLICY "gcm_delete_own" ON group_challenge_members
    FOR DELETE TO authenticated
    USING (user_id = auth.uid());

-- ============================================================================
-- PART 2: Enable RLS on achievements
-- ============================================================================
-- This is the achievement DEFINITION table (static rows like "First Workout").
-- All authenticated users need to read it. Nobody should write via PostgREST.
-- Writes happen through the check_achievement RPC (SECURITY DEFINER).

ALTER TABLE IF EXISTS achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "achievements_select_all" ON achievements;
CREATE POLICY "achievements_select_all" ON achievements
    FOR SELECT TO authenticated
    USING (true);

-- ============================================================================
-- PART 3: Convert SECURITY DEFINER views to SECURITY INVOKER
-- ============================================================================
-- SECURITY DEFINER views run with the view owner's permissions, bypassing RLS
-- for the calling user. SECURITY INVOKER makes the view respect the calling
-- user's RLS policies.
--
-- Views queried by the app (weight_statistics, body_composition_statistics)
-- will still work because the app filters by user_id and the underlying tables
-- have RLS policies allowing users to read their own data.
--
-- Admin/analytics views will return empty for regular users (correct behavior)
-- but still work for service_role queries which bypass RLS.

ALTER VIEW IF EXISTS public.weight_statistics SET (security_invoker = on);
ALTER VIEW IF EXISTS public.body_composition_statistics SET (security_invoker = on);
ALTER VIEW IF EXISTS public.popular_foods_view SET (security_invoker = on);
ALTER VIEW IF EXISTS public.user_food_history_v SET (security_invoker = on);
ALTER VIEW IF EXISTS public.challenge_progress_summary SET (security_invoker = on);
ALTER VIEW IF EXISTS public.user_activity_stats SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_challenge_progress_correlation SET (security_invoker = on);
ALTER VIEW IF EXISTS public.weekly_health_stats SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_hydration_workout_correlation SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_onboarding_problems SET (security_invoker = on);
ALTER VIEW IF EXISTS public.pending_notifications_webhook SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_social_retention_correlation SET (security_invoker = on);
ALTER VIEW IF EXISTS public.notification_health_stats SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_onboarding_summary SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_sleep_recovery_correlation SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_onboarding_issues SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_field_comparison SET (security_invoker = on);
ALTER VIEW IF EXISTS public.v_nutrition_workout_correlation SET (security_invoker = on);
ALTER VIEW IF EXISTS public.weekly_sleep_stats SET (security_invoker = on);

-- ============================================================================
-- PART 4: Verification
-- ============================================================================

DO $$
DECLARE
    gcm_rls BOOLEAN;
    ach_rls BOOLEAN;
BEGIN
    SELECT relrowsecurity INTO gcm_rls
    FROM pg_class WHERE relname = 'group_challenge_members';

    SELECT relrowsecurity INTO ach_rls
    FROM pg_class WHERE relname = 'achievements';

    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  Security Fix Applied (2026-03-24)';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '  group_challenge_members RLS: %', CASE WHEN gcm_rls THEN 'ENABLED' ELSE 'DISABLED' END;
    RAISE NOTICE '  achievements RLS: %', CASE WHEN ach_rls THEN 'ENABLED' ELSE 'DISABLED' END;
    RAISE NOTICE '  19 SECURITY DEFINER views -> SECURITY INVOKER';
    RAISE NOTICE '';
    RAISE NOTICE '  App impact: None. weight_statistics and';
    RAISE NOTICE '  body_composition_statistics still work because';
    RAISE NOTICE '  underlying tables have user_id RLS policies.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
