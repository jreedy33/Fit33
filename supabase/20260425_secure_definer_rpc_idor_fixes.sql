-- =============================================================================
-- Secure SECURITY DEFINER RPCs against IDOR (2026-04-25)
-- =============================================================================
-- Codebase audit (2026-04-22) found two high-severity IDOR gaps in legacy
-- SECURITY DEFINER RPCs that accept a user_id parameter but never verify the
-- caller is that user:
--
--   1. `delete_user_account(user_id_to_delete UUID)` (P0 — any authenticated
--      user could wipe any other user's account).
--   2. `get_user_achievements(p_user_id UUID DEFAULT NULL)` (P1 — any
--      authenticated user could read any other user's achievement progress).
--
-- Follows the pattern established by `20260417_secure_get_friend_ids.sql`:
-- callers with a non-NULL `auth.uid()` must pass their own id; service_role
-- and pg_cron contexts (where auth.uid() is NULL) remain unrestricted so
-- internal cleanup flows keep working.
--
-- Rollout is idempotent: `CREATE OR REPLACE FUNCTION` with the same
-- signatures as the originals, so no `DROP FUNCTION` sweep is required.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. delete_user_account — P0 IDOR fix
-- ---------------------------------------------------------------------------
-- Original definition: supabase/complete_account_deletion.sql (no auth guard).
-- The Swift app calls this via `SupabaseManager.rpc('delete_user_account')`
-- and always passes the signed-in user's own id, so this tightening is safe
-- for first-party callers.

CREATE OR REPLACE FUNCTION public.delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  friendships_deleted INTEGER := 0;
  friend_requests_deleted INTEGER := 0;
  contacts_deleted INTEGER := 0;
  workouts_deleted INTEGER := 0;
  push_tokens_deleted INTEGER := 0;
  notifications_deleted INTEGER := 0;
  result jsonb;
BEGIN
  -- IDOR guard: authenticated callers must delete their own account only.
  -- service_role / pg_cron contexts (auth.uid() IS NULL) remain unrestricted.
  IF auth.uid() IS NOT NULL AND user_id_to_delete <> auth.uid() THEN
    RAISE EXCEPTION 'Forbidden: cannot delete another user''s account'
      USING ERRCODE = '42501';
  END IF;

  -- 1. Delete friendships (both sides)
  DELETE FROM friendships
  WHERE requester_id = user_id_to_delete OR addressee_id = user_id_to_delete;
  GET DIAGNOSTICS friendships_deleted = ROW_COUNT;

  -- 2. Delete friend requests
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
    DELETE FROM friend_requests
    WHERE from_user_id = user_id_to_delete OR to_user_id = user_id_to_delete;
    GET DIAGNOSTICS friend_requests_deleted = ROW_COUNT;
  END IF;

  -- 3. Delete user contacts
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
    DELETE FROM user_contacts WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS contacts_deleted = ROW_COUNT;
  END IF;

  -- 4. Delete workouts
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
    DELETE FROM workouts WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS workouts_deleted = ROW_COUNT;
  END IF;

  -- 5. Delete push tokens
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
    DELETE FROM user_push_tokens WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS push_tokens_deleted = ROW_COUNT;
  END IF;

  -- 6. Delete notifications
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
    DELETE FROM push_notification_queue WHERE recipient_user_id = user_id_to_delete;
    GET DIAGNOSTICS notifications_deleted = ROW_COUNT;
  END IF;

  -- 7. Delete user profile
  DELETE FROM user_profiles WHERE id = user_id_to_delete;

  -- 8. Delete auth user
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
      'notifications', notifications_deleted
    )
  );

  RAISE NOTICE 'Account deleted: %', result;
  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.delete_user_account(UUID) IS
  'Deletes a user account and ALL associated data. IDOR-guarded 2026-04-25: authenticated callers must delete their own account only.';

GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO service_role;

-- ---------------------------------------------------------------------------
-- 2. get_user_achievements — P1 IDOR fix
-- ---------------------------------------------------------------------------
-- Original definition: supabase/20260307_achievements.sql. The old body let
-- any authenticated user pass any `p_user_id` and read that user's progress.
-- The hardened body requires either NULL (defaults to auth.uid()) or an
-- explicit match against auth.uid(). service_role / pg_cron bypass the
-- guard so backfills keep working.

CREATE OR REPLACE FUNCTION public.get_user_achievements(p_user_id UUID DEFAULT NULL)
RETURNS TABLE (
    achievement_key TEXT,
    title TEXT,
    description TEXT,
    icon TEXT,
    category TEXT,
    threshold INT,
    xp_reward INT,
    rarity TEXT,
    progress INT,
    unlocked_at TIMESTAMPTZ,
    sort_order INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_user_id UUID;
BEGIN
    target_user_id := COALESCE(p_user_id, auth.uid());

    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- IDOR guard: if the caller is a real user (auth.uid() NOT NULL) and
    -- they explicitly asked for someone else's achievements, refuse.
    -- service_role / pg_cron contexts keep full access.
    IF auth.uid() IS NOT NULL AND target_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot read another user''s achievements'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        a.key AS achievement_key,
        a.title,
        a.description,
        a.icon,
        a.category,
        a.threshold,
        a.xp_reward,
        a.rarity,
        COALESCE(ua.progress, 0) AS progress,
        ua.unlocked_at,
        a.sort_order
    FROM achievements a
    LEFT JOIN user_achievements ua
        ON ua.achievement_id = a.id
       AND ua.user_id = target_user_id
    ORDER BY a.sort_order;
END;
$$;

COMMENT ON FUNCTION public.get_user_achievements(UUID) IS
  'Returns a user''s achievement progress. IDOR-guarded 2026-04-25.';

GRANT EXECUTE ON FUNCTION public.get_user_achievements(UUID) TO authenticated;

COMMIT;
