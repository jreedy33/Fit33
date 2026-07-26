-- ============================================================================
-- HOTFIX: restore the IDOR guard + realtime broadcast on delete_user_account
-- ============================================================================
-- WHY (P0 security regression, found by 2026-07-26 production-readiness audit):
--
--   1. `20260425_secure_definer_rpc_idor_fixes.sql` added the IDOR guard
--      (auth.uid() callers may only delete THEMSELVES).
--   2. `20260504_olympian_path.sql`, `20260508_user_deletion_realtime_events.sql`
--      and `20260715_monetization_phase_1a.sql` each did a full
--      CREATE OR REPLACE of the function body and the LAST one (20260715)
--      dropped BOTH the guard AND the `user_deletion_events` broadcast
--      INSERT while adding the monetization-table deletes.
--   3. The function is SECURITY DEFINER and GRANTed to `authenticated`,
--      so with the 20260715 body applied, ANY logged-in user can delete
--      ANY account by passing a forged `user_id_to_delete`.
--
-- THIS FILE is the union of all three concerns and MUST be treated as the
-- canonical body going forward:
--   (a) IDOR guard          (from 20260425)
--   (b) deletion broadcast  (from 20260508)
--   (c) monetization deletes (from 20260715)
--
-- RULE (also documented in SUPABASE_AGENT.md): never CREATE OR REPLACE this
-- function without copying (a) + (b) + (c). The trailing audit below fails
-- the migration loudly if the guard text is missing from the live definition.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    friendships_deleted         INTEGER := 0;
    friend_requests_deleted     INTEGER := 0;
    contacts_deleted            INTEGER := 0;
    workouts_deleted            INTEGER := 0;
    push_tokens_deleted         INTEGER := 0;
    notifications_deleted       INTEGER := 0;
    subscriptions_deleted       INTEGER := 0;
    iap_receipts_deleted        INTEGER := 0;
    grants_deleted              INTEGER := 0;
    paywall_assignments_deleted INTEGER := 0;
    result jsonb;
BEGIN
    -- ───────────────────────────────────────────────────────────────────
    -- 0a. IDOR guard (restored from 20260425_secure_definer_rpc_idor_fixes).
    --     Real users (auth.uid() IS NOT NULL) may only delete themselves.
    --     service_role / pg_cron contexts (auth.uid() IS NULL) remain
    --     unrestricted for admin tooling.
    -- ───────────────────────────────────────────────────────────────────
    IF auth.uid() IS NOT NULL AND user_id_to_delete <> auth.uid() THEN
        RAISE EXCEPTION 'delete_user_account: caller % may not delete user %',
            auth.uid(), user_id_to_delete
            USING ERRCODE = '42501'; -- insufficient_privilege
    END IF;

    -- ───────────────────────────────────────────────────────────────────
    -- 0b. Broadcast the deletion FIRST (restored from
    --     20260508_user_deletion_realtime_events). Transactional: if any
    --     later DELETE errors, this INSERT rolls back too, so clients
    --     never see a "deleted" event for a still-present account.
    -- ───────────────────────────────────────────────────────────────────
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_deletion_events') THEN
        INSERT INTO public.user_deletion_events (deleted_user_id, deleted_by)
        VALUES (user_id_to_delete, auth.uid());
    END IF;

    -- 1. Friendships (both sides)
    DELETE FROM friendships
    WHERE requester_id = user_id_to_delete OR addressee_id = user_id_to_delete;
    GET DIAGNOSTICS friendships_deleted = ROW_COUNT;

    -- 2. Friend requests (sent + received)
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
        DELETE FROM friend_requests
        WHERE from_user_id = user_id_to_delete OR to_user_id = user_id_to_delete;
        GET DIAGNOSTICS friend_requests_deleted = ROW_COUNT;
    END IF;

    -- 3. User contacts
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
        DELETE FROM user_contacts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS contacts_deleted = ROW_COUNT;
    END IF;

    -- 4. Workouts
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
        DELETE FROM workouts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS workouts_deleted = ROW_COUNT;
    END IF;

    -- 5. Push tokens
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
        DELETE FROM user_push_tokens WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS push_tokens_deleted = ROW_COUNT;
    END IF;

    -- 6. Queued notifications
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
        DELETE FROM push_notification_queue WHERE recipient_user_id = user_id_to_delete;
        GET DIAGNOSTICS notifications_deleted = ROW_COUNT;
    END IF;

    -- 7. Monetization tables (kept from 20260715_monetization_phase_1a)
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'subscriptions') THEN
        DELETE FROM public.subscriptions WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS subscriptions_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'iap_receipts') THEN
        DELETE FROM public.iap_receipts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS iap_receipts_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'subscription_grants') THEN
        DELETE FROM public.subscription_grants WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS grants_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'paywall_experiment_assignments') THEN
        DELETE FROM public.paywall_experiment_assignments WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS paywall_assignments_deleted = ROW_COUNT;
    END IF;

    -- 8. Profile (AFTER triggers cascade to auth.users + auth.identities
    --    + user_quest_*), then belt-and-suspenders auth.users delete.
    DELETE FROM user_profiles WHERE id = user_id_to_delete;
    DELETE FROM auth.users WHERE id = user_id_to_delete;

    result := jsonb_build_object(
        'success', true,
        'user_id', user_id_to_delete,
        'deleted', jsonb_build_object(
            'friendships', friendships_deleted,
            'friend_requests', friend_requests_deleted,
            'contacts', contacts_deleted,
            'workouts', workouts_deleted,
            'push_tokens', push_tokens_deleted,
            'notifications', notifications_deleted,
            'subscriptions', subscriptions_deleted,
            'iap_receipts', iap_receipts_deleted,
            'subscription_grants', grants_deleted,
            'paywall_assignments', paywall_assignments_deleted
        ),
        'broadcast', 'user_deletion_events'
    );

    RAISE NOTICE 'Account deleted: %', result;
    RETURN result;
END $$;

-- Grants unchanged: authenticated (self-delete only, guard-enforced) +
-- service_role (admin tooling). Re-run defensively — idempotent.
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- Trailing audit — fail loud if the IDOR guard or broadcast ever regress.
-- Any future CREATE OR REPLACE that drops either will make re-running this
-- migration (or a copy of this audit) raise.
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'delete_user_account';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'AUDIT FAIL: public.delete_user_account not found';
    END IF;

    IF position('user_id_to_delete <> auth.uid()' IN v_def) = 0 THEN
        RAISE EXCEPTION 'AUDIT FAIL: delete_user_account is missing the IDOR guard';
    END IF;

    IF position('user_deletion_events' IN v_def) = 0 THEN
        RAISE EXCEPTION 'AUDIT FAIL: delete_user_account is missing the user_deletion_events broadcast';
    END IF;

    RAISE NOTICE '✅ delete_user_account guard + broadcast verified';
END $$;

COMMIT;
