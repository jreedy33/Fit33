-- ═══════════════════════════════════════════════════════════════════════════
-- 20260508_user_deletion_realtime_events.sql
--
-- Feature — instant cross-device invalidation when a user is deleted.
-- Pairs with `Fit33/RealtimeService.swift::subscribeUserDeletions` and the
-- per-service `purgeDeletedUser(_:)` methods in `FriendService`,
-- `ContactsService`, `FriendRankingService`, and `ActivityFeedService`.
--
-- BACKGROUND
-- ----------
-- Today, when an admin (or the user themselves) deletes an account:
--   • Server-side data is wiped (cascades from auth.users + the AFTER
--     triggers on user_profiles installed by migration #200, 2026-05-08).
--   • Other clients only learn about it on next refresh — `fetchFriends`,
--     `fetchPeopleYouMayKnow`, `findMatchingUsers` all replace their
--     arrays from the server response, but those fetches are gated:
--       - PYMK + contacts: once-per-session + 6h TTL, or pull-to-refresh.
--       - Friends list: foreground re-sync (>30s stale) or pull-to-refresh.
--   • Stale "Add Friends" suggestions (deleted Joes) and friend rows
--     persist in @Published arrays + UserDefaults caches until then.
--
-- FIX
-- ---
-- Turn user-deletion into a Realtime broadcast. Every authenticated
-- session subscribes to `public.user_deletion_events` and on each INSERT:
--   1. Extracts `deleted_user_id`.
--   2. Calls `purgeDeletedUser(_:)` on FriendService / ContactsService /
--      FriendRankingService / ActivityFeedService.
--   3. Each service removes the user from its in-memory @Published
--      arrays AND re-saves the UserDefaults cache so the next cold
--      launch doesn't re-hydrate the deleted user.
--
-- Schema choices:
--   • NO foreign key from `deleted_user_id` to `auth.users(id)`. The
--     event row MUST outlive the deleted row — if there were a FK with
--     ON DELETE CASCADE, the event would vanish in the same transaction
--     it was meant to broadcast. Without a FK, the row sticks around for
--     the realtime fan-out and the 7-day TTL audit window.
--   • `deleted_by` (NULLABLE) — `auth.uid()` of the initiator if known.
--     For service-role admin CMS deletes, `auth.uid()` is NULL — fine,
--     the admin audit log already captures who clicked the button.
--   • `REPLICA IDENTITY FULL` so realtime payloads include every column
--     (per supabase-rules §realtime — INSERT events otherwise only
--     ship the primary key, which would force the iOS client to make
--     a follow-up query just to get the deleted_user_id).
--   • Added to `supabase_realtime` publication so iOS clients can
--     subscribe via `RealtimeChannelV2`.
--
-- RLS:
--   • SELECT for `authenticated` (so realtime events are deliverable).
--     The payload is a single UUID — no PII.
--   • No INSERT/UPDATE/DELETE policy for users; writes happen ONLY via
--     `delete_user_account(uuid)` SECURITY DEFINER RPC (or future
--     equivalent), which bypasses RLS.
--
-- Patches `delete_user_account(uuid)`:
--   • Inserts an event row at the START of the function (before any
--     destructive deletes). If a downstream delete fails, the
--     transaction rolls back — including the event INSERT — so we
--     never broadcast a "deleted" signal for an account that's still
--     present.
--
-- INVARIANT TO CARRY FORWARD (DATA_BACKEND_AGENT.md):
--   Every code path that deletes a `user_profiles` row MUST emit a
--   `user_deletion_events` row before doing so. Today the canonical
--   path is `delete_user_account(uuid)` (used by iOS account
--   self-delete + the admin CMS Delete button). If a future migration
--   adds another deletion path (bulk cleanup, cron sweeper, etc.) it
--   MUST also INSERT INTO `user_deletion_events` so the Realtime
--   broadcast still fires for those clients.
--
-- TTL:
--   `cleanup_old_user_deletion_events()` deletes rows older than 7 days.
--   Schedule via pg_cron in a separate migration if needed; the table
--   is small enough that a manual run every few months is also fine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. The events table.
-- ──────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_deletion_events (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    deleted_user_id uuid        NOT NULL,
    deleted_by      uuid,
    deleted_at      timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.user_deletion_events IS
'Append-only stream of user-deletion broadcasts. Every authenticated client
subscribes via Supabase Realtime and purges the deleted_user_id from its
local @Published arrays + UserDefaults caches. Rows MUST outlive the
deleted user_profiles/auth.users records — that is why deleted_user_id has
no FK to auth.users. TTL handled by cleanup_old_user_deletion_events().';

CREATE INDEX IF NOT EXISTS idx_user_deletion_events_deleted_at
    ON public.user_deletion_events (deleted_at DESC);

-- ──────────────────────────────────────────────────────────────────────────
-- 2. RLS — authenticated SELECT only. Writes go through SECURITY DEFINER
--    RPCs which bypass RLS.
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_deletion_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_deletion_events_select_authenticated" ON public.user_deletion_events;
CREATE POLICY "user_deletion_events_select_authenticated"
    ON public.user_deletion_events
    FOR SELECT
    TO authenticated
    USING (true);

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Realtime: REPLICA IDENTITY FULL + add to supabase_realtime publication.
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_deletion_events REPLICA IDENTITY FULL;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname    = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename  = 'user_deletion_events'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.user_deletion_events;
            RAISE NOTICE '✅ Added public.user_deletion_events to supabase_realtime publication';
        ELSE
            RAISE NOTICE 'ℹ️  public.user_deletion_events already in supabase_realtime publication';
        END IF;
    ELSE
        RAISE WARNING '⚠️  supabase_realtime publication not found — Realtime will not deliver events for this table until the publication exists';
    END IF;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Patch `delete_user_account(uuid)` to emit a row before destructive
--    deletes. The function body otherwise mirrors `complete_account_deletion.sql`
--    (canonical owner) — any future edits to the body should be made there
--    and ported here, OR vice versa, but the INSERT INTO user_deletion_events
--    block at the top is the canonical home.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
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
  -- ───────────────────────────────────────────────────────────────────
  -- 0. Broadcast the deletion FIRST (transactional).
  --
  -- Every authenticated session subscribes to public.user_deletion_events
  -- via Supabase Realtime. iOS clients react in `RealtimeService` by
  -- purging the deleted_user_id from FriendService / ContactsService /
  -- FriendRankingService / ActivityFeedService caches.
  --
  -- If any subsequent DELETE in this function errors, the entire
  -- transaction (including this INSERT) rolls back — clients NEVER
  -- receive a "deleted" event for an account that's still present.
  -- ───────────────────────────────────────────────────────────────────
  INSERT INTO public.user_deletion_events (deleted_user_id, deleted_by)
  VALUES (user_id_to_delete, auth.uid());

  -- 1. Delete friendships (both sides — where user is requester OR addressee)
  DELETE FROM friendships
  WHERE requester_id = user_id_to_delete OR addressee_id = user_id_to_delete;
  GET DIAGNOSTICS friendships_deleted = ROW_COUNT;

  -- 2. Delete friend requests (both sent and received)
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

  -- 7. Delete user profile (fires AFTER triggers from migration #200 →
  --    cascades to auth.users + auth.identities + user_quest_*).
  DELETE FROM user_profiles WHERE id = user_id_to_delete;

  -- 8. Belt-and-suspenders: explicit auth.users delete in case the
  --    profile row was already gone (zombie auth.users orphan path).
  DELETE FROM auth.users WHERE id = user_id_to_delete;

  -- Return summary
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
    ),
    'broadcast', 'user_deletion_events'
  );

  RAISE NOTICE 'Account deleted: %', result;
  RETURN result;
END;
$$;

-- Owner (postgres) ALREADY has EXECUTE; the prior migration already granted
-- to authenticated + service_role. Re-run the GRANTs to be defensive — they
-- are idempotent for SQL purposes.
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. TTL cleanup — events older than 7 days. Run manually or schedule via
--    pg_cron if/when the table grows past a few thousand rows. The
--    7-day window gives every iOS client a generous chance to come back
--    online and process events that were missed while offline (the
--    Supabase Realtime client has no built-in "missed events while
--    disconnected" replay, so the ON-FOREGROUND fetches still serve as
--    backstop).
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleanup_old_user_deletion_events()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INTEGER := 0;
BEGIN
    DELETE FROM public.user_deletion_events
    WHERE deleted_at < NOW() - INTERVAL '7 days';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_old_user_deletion_events() TO service_role;

COMMENT ON FUNCTION public.cleanup_old_user_deletion_events() IS
'Deletes user_deletion_events rows older than 7 days. Run manually or via
pg_cron. Returns the number of rows purged.';

-- ──────────────────────────────────────────────────────────────────────────
-- 6. Trailing audit — fail loud if any of the wiring is missing.
-- ──────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    has_table        BOOLEAN;
    has_pub_entry    BOOLEAN;
    has_select_pol   BOOLEAN;
    rel_identity     CHAR;
    has_rpc_insert   BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_class
        WHERE relname    = 'user_deletion_events'
          AND relnamespace = 'public'::regnamespace
    ) INTO has_table;
    IF NOT has_table THEN
        RAISE EXCEPTION '[20260508 audit] FAILED — public.user_deletion_events table missing';
    END IF;

    -- Realtime publication entry. Soft-fail (warning only) if the
    -- supabase_realtime publication itself is missing — Supabase normally
    -- creates this for every project, but locally-bootstrapped Postgres
    -- might not have it.
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        SELECT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname    = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename  = 'user_deletion_events'
        ) INTO has_pub_entry;
        IF NOT has_pub_entry THEN
            RAISE EXCEPTION '[20260508 audit] FAILED — public.user_deletion_events not in supabase_realtime publication';
        END IF;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename  = 'user_deletion_events'
          AND policyname = 'user_deletion_events_select_authenticated'
    ) INTO has_select_pol;
    IF NOT has_select_pol THEN
        RAISE EXCEPTION '[20260508 audit] FAILED — SELECT policy missing on user_deletion_events';
    END IF;

    SELECT relreplident INTO rel_identity
    FROM pg_class
    WHERE relname    = 'user_deletion_events'
      AND relnamespace = 'public'::regnamespace;
    IF rel_identity <> 'f' THEN
        RAISE EXCEPTION '[20260508 audit] FAILED — REPLICA IDENTITY on user_deletion_events is %, expected FULL (f)', rel_identity;
    END IF;

    -- The patched delete_user_account function MUST contain the INSERT
    -- INTO user_deletion_events line. We check pg_proc.prosrc for the
    -- substring as a smoke test — full body parity with this migration
    -- is not enforced.
    SELECT (prosrc LIKE '%user_deletion_events%')
    INTO has_rpc_insert
    FROM pg_proc
    WHERE proname = 'delete_user_account'
      AND pronamespace = 'public'::regnamespace
    LIMIT 1;
    IF has_rpc_insert IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION '[20260508 audit] FAILED — delete_user_account does not reference user_deletion_events';
    END IF;

    RAISE NOTICE '✅ [20260508 audit] user_deletion_events wired: table + RLS + REPLICA IDENTITY FULL + publication + RPC INSERT.';
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
