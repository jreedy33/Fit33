-- ============================================================================
-- 20260820_challenge_reactions_realtime.sql
--
-- Battle Cry overhaul (2026-04-30) — adds `challenge_reactions` to the
-- `supabase_realtime` publication and forces `REPLICA IDENTITY FULL` so
-- new INSERTs are broadcast with the full row payload.
--
-- WHY
-- ---
-- The challenge-detail-page overhaul replaces the old static
-- `ReactionFeedView` polling stack with a streaming `ReactiveBattleFeed`
-- that subscribes via `RealtimeService.subscribeChallengeReactions`.
-- The companion iOS code listens for INSERT events on
-- `challenge_reactions` filtered by `challenge_id`. Without this
-- migration the channel subscribes successfully but no events ever
-- arrive, so the "Instagram DM emoji-arrival" feel collapses back to
-- a fetch-on-open static list.
--
-- IDEMPOTENCY
-- -----------
-- ALTER PUBLICATION wrapped in `DO $$` swallowing `duplicate_object`.
-- REPLICA IDENTITY FULL is unconditional and a no-op when already set.
-- Safe to re-run on any environment.
--
-- DEPLOY ORDER
-- ------------
-- Standalone — depends only on `challenge_reactions.sql` (already
-- deployed). Run via Supabase SQL Editor any time after the iOS
-- `BattleCryComposer.swift` ships in TestFlight.
--
-- VALIDATION
-- ----------
-- Trailing `DO $$` block confirms the table is in the publication AND
-- has REPLICA IDENTITY FULL, raising EXCEPTION if either is missing.
-- ============================================================================

BEGIN;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE challenge_reactions;
    RAISE NOTICE '✅ Added challenge_reactions to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  challenge_reactions already in supabase_realtime publication';
END $$;

ALTER TABLE challenge_reactions REPLICA IDENTITY FULL;

-- ─── Validation ────────────────────────────────────────────────────
DO $$
DECLARE
    in_publication BOOLEAN;
    replica_setting "char";
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'challenge_reactions'
    ) INTO in_publication;

    IF NOT in_publication THEN
        RAISE EXCEPTION 'AUDIT FAILED: challenge_reactions NOT in supabase_realtime publication';
    END IF;

    SELECT c.relreplident
    INTO replica_setting
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'challenge_reactions';

    IF replica_setting IS NULL THEN
        RAISE EXCEPTION 'AUDIT FAILED: table public.challenge_reactions does not exist';
    ELSIF replica_setting <> 'f' THEN
        RAISE EXCEPTION 'AUDIT FAILED: challenge_reactions REPLICA IDENTITY is % (expected f/full)', replica_setting::text;
    END IF;

    RAISE NOTICE '✅ challenge_reactions verified in publication AND REPLICA IDENTITY FULL';
END $$;

COMMIT;
