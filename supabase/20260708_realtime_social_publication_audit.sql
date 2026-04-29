-- ============================================================================
-- 20260708_realtime_social_publication_audit.sql
--
-- Sync Triage 2026-04-28 — Layer C (paired with iOS Layer A + B in commit
--                              "Social Sync Regression Fix Plan").
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- Reasserts the `supabase_realtime` publication membership AND
-- `REPLICA IDENTITY FULL` for every table the iOS `RealtimeService`
-- subscribes to. Idempotent — safe to re-run any time.
--
-- WHY
-- ---
-- Friend-request, challenge-invite, private-invite, group-invite,
-- and friend-activity-feed cards stopped appearing on the receiver's
-- dashboard despite the push notification firing correctly (Bug-Intel
-- fingerprint `721fe5d6` and the 2026-04-28 user report). The iOS
-- `RealtimeService` filtered subscriptions on `friendships`,
-- `shared_workouts`, `challenge_participants`, etc. — but the repo
-- migration history shows that `friendships` and `shared_workouts`
-- were NEVER explicitly added to `supabase_realtime` via a migration
-- file. They may have been added directly via the Supabase dashboard
-- in the past, but if any prior maintenance ever recreated the
-- publication, the channels would silently go dark.
--
-- The companion iOS fix (Layer A in `Fit33/Fit33App.swift` + Layer B
-- in `Fit33/RealtimeService.swift`) makes the client resilient to a
-- broken publication by always re-fetching social state on
-- foreground. THIS migration closes the loop on the SERVER side so
-- realtime actually delivers events again — restoring the "instant
-- card appears when sender hits Send" UX, not just the "card
-- appears when receiver next foregrounds" fallback.
--
-- TABLES COVERED
-- --------------
-- Every table referenced by `RealtimeService.{subscribe*}` in
-- `Fit33/RealtimeService.swift` (10 channels, 14 distinct tables):
--   subscribeFriendships          → friendships
--   subscribeSharedWorkouts       → shared_workouts
--   subscribeChallenges           → challenge_participants, group_challenges
--   subscribeDailyProgress        → challenge_daily_progress
--   subscribePrivateProgress      → private_challenge_daily_progress
--   subscribeCommunityProgress    → community_challenge_daily_progress
--   subscribeCommunityParticipants→ community_challenge_participants
--   subscribePrivateMembers       → private_challenge_members
--   subscribeFriendActivityFeed   → friend_activity_feed
--   subscribePrivacyChanges       → privacy_change_events
--   subscribeExercises            → exercises
--   (in-app private chat)         → private_challenge_chat
--   (private invites)             → private_challenge_invites
--   (community challenges body)   → community_challenges
--   (private challenges body)     → private_challenges
--
-- IDEMPOTENCY
-- -----------
-- Each ALTER PUBLICATION call is wrapped in a `DO $$` block that
-- catches `duplicate_object` (table already in publication). Each
-- `REPLICA IDENTITY FULL` is unconditional and a no-op when already
-- set. Safe to re-run on any environment.
--
-- DEPLOY ORDER
-- ------------
-- Standalone — no dependency on prior migrations in this train.
-- Run via the Supabase SQL Editor on prod once Layer A + Layer B
-- iOS code lands in TestFlight. Sub-second runtime expected.
--
-- VALIDATION
-- ----------
-- Trailing `DO $$` block emits `RAISE NOTICE` lines confirming each
-- table is in the publication AND has `REPLICA IDENTITY FULL`. Any
-- mismatch raises a hard `EXCEPTION` so the migration fails loud.
-- ============================================================================

BEGIN;

-- ─── Idempotent helper ─────────────────────────────────────────────
-- Adds `tbl_name` to `supabase_realtime` publication and forces
-- `REPLICA IDENTITY FULL`. Both operations are no-ops when already
-- in place. We can't `CREATE OR REPLACE` ALTER PUBLICATION, so we
-- inline a `DO $$` per-table to swallow `duplicate_object`.

-- Friendships — was implicit-only (never added via migration).
-- This is THE high-leverage row of the migration: closing the
-- "Matt sent Paul a friend request, no card appeared" gap.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE friendships;
    RAISE NOTICE '✅ Added friendships to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  friendships already in supabase_realtime publication';
END $$;
ALTER TABLE friendships REPLICA IDENTITY FULL;

-- Shared workouts — same pattern; closes the "shared workout card
-- not appearing in carousel" gap.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE shared_workouts;
    RAISE NOTICE '✅ Added shared_workouts to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  shared_workouts already in supabase_realtime publication';
END $$;
ALTER TABLE shared_workouts REPLICA IDENTITY FULL;

-- Challenge participants — already added by 20260612_fix_challenge_realtime_replica_identity.sql,
-- reasserting defensively. The carousel reads `challenge_invite` cards
-- via this table's INSERT events.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE challenge_participants;
    RAISE NOTICE '✅ Added challenge_participants to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  challenge_participants already in supabase_realtime publication';
END $$;
ALTER TABLE challenge_participants REPLICA IDENTITY FULL;

-- Challenge daily progress — opponent-progress widget data source.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE challenge_daily_progress;
    RAISE NOTICE '✅ Added challenge_daily_progress to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  challenge_daily_progress already in supabase_realtime publication';
END $$;
ALTER TABLE challenge_daily_progress REPLICA IDENTITY FULL;

-- Group challenges — also covers the "I accepted a group challenge"
-- → opponent's UI path via group_challenges UPDATE events.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE group_challenges;
    RAISE NOTICE '✅ Added group_challenges to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  group_challenges already in supabase_realtime publication';
END $$;
ALTER TABLE group_challenges REPLICA IDENTITY FULL;

-- Private challenges — challenge body (title, members, etc.).
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenges;
    RAISE NOTICE '✅ Added private_challenges to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  private_challenges already in supabase_realtime publication';
END $$;
ALTER TABLE private_challenges REPLICA IDENTITY FULL;

-- Private challenge invites — the "you've been invited to X's private
-- challenge" carousel card.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_invites;
    RAISE NOTICE '✅ Added private_challenge_invites to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  private_challenge_invites already in supabase_realtime publication';
END $$;
ALTER TABLE private_challenge_invites REPLICA IDENTITY FULL;

-- Private challenge members — join/leave events fan-out.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_members;
    RAISE NOTICE '✅ Added private_challenge_members to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  private_challenge_members already in supabase_realtime publication';
END $$;
ALTER TABLE private_challenge_members REPLICA IDENTITY FULL;

-- Private challenge daily progress — leaderboard widget data source.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_daily_progress;
    RAISE NOTICE '✅ Added private_challenge_daily_progress to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  private_challenge_daily_progress already in supabase_realtime publication';
END $$;
ALTER TABLE private_challenge_daily_progress REPLICA IDENTITY FULL;

-- Private challenge chat — moderation hide propagation
-- (added by 20260426_sprint7_security_hygiene.sql — reasserting defensively).
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE private_challenge_chat;
    RAISE NOTICE '✅ Added private_challenge_chat to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  private_challenge_chat already in supabase_realtime publication';
END $$;
ALTER TABLE private_challenge_chat REPLICA IDENTITY FULL;

-- Community challenges — challenge body.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_challenges;
    RAISE NOTICE '✅ Added community_challenges to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  community_challenges already in supabase_realtime publication';
END $$;
ALTER TABLE community_challenges REPLICA IDENTITY FULL;

-- Community challenge participants — join/leave events.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_participants;
    RAISE NOTICE '✅ Added community_challenge_participants to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  community_challenge_participants already in supabase_realtime publication';
END $$;
ALTER TABLE community_challenge_participants REPLICA IDENTITY FULL;

-- Community challenge daily progress — leaderboard widget data source.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_daily_progress;
    RAISE NOTICE '✅ Added community_challenge_daily_progress to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  community_challenge_daily_progress already in supabase_realtime publication';
END $$;
ALTER TABLE community_challenge_daily_progress REPLICA IDENTITY FULL;

-- Friend activity feed — Recent Activity feed on dashboard.
-- Covers "Joe can't see Paul's recent workouts" symptom.
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE friend_activity_feed;
    RAISE NOTICE '✅ Added friend_activity_feed to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  friend_activity_feed already in supabase_realtime publication';
END $$;
ALTER TABLE friend_activity_feed REPLICA IDENTITY FULL;

-- Privacy change events — ledger of privacy toggles for league + feed.
-- (added by 20260330_league_privacy_realtime.sql — reasserting.)
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE privacy_change_events;
    RAISE NOTICE '✅ Added privacy_change_events to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  privacy_change_events already in supabase_realtime publication';
END $$;
ALTER TABLE privacy_change_events REPLICA IDENTITY FULL;

-- Exercises — admin CMS live sync (added by 20260420_exercises_realtime.sql).
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.exercises;
    RAISE NOTICE '✅ Added public.exercises to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'ℹ️  public.exercises already in supabase_realtime publication';
END $$;
ALTER TABLE public.exercises REPLICA IDENTITY FULL;

-- ─── Validation: fail-loud audit ───────────────────────────────────
-- Verify every table we just touched is in the publication AND has
-- REPLICA IDENTITY FULL. If any mismatch, raise EXCEPTION so the
-- migration fails visibly instead of silently leaving a half-broken
-- realtime surface.

DO $$
DECLARE
    expected_tables TEXT[] := ARRAY[
        'friendships',
        'shared_workouts',
        'challenge_participants',
        'challenge_daily_progress',
        'group_challenges',
        'private_challenges',
        'private_challenge_invites',
        'private_challenge_members',
        'private_challenge_daily_progress',
        'private_challenge_chat',
        'community_challenges',
        'community_challenge_participants',
        'community_challenge_daily_progress',
        'friend_activity_feed',
        'privacy_change_events',
        'exercises'
    ];
    tbl TEXT;
    in_publication BOOLEAN;
    replica_setting "char";
    missing_pub TEXT[] := ARRAY[]::TEXT[];
    bad_replica TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOREACH tbl IN ARRAY expected_tables LOOP
        -- Is the table in supabase_realtime publication?
        SELECT EXISTS (
            SELECT 1
            FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
              AND schemaname = 'public'
              AND tablename = tbl
        ) INTO in_publication;

        IF NOT in_publication THEN
            missing_pub := array_append(missing_pub, tbl);
        END IF;

        -- Is REPLICA IDENTITY set to FULL? ('f' = FULL in pg_class.relreplident)
        SELECT c.relreplident
        INTO replica_setting
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = tbl;

        IF replica_setting IS NULL THEN
            -- Table doesn't exist — defensive case (e.g. on a fresh
            -- project missing one). Note and skip.
            RAISE NOTICE '⚠️  Table public.% does not exist (skipping replica check)', tbl;
        ELSIF replica_setting <> 'f' THEN
            bad_replica := array_append(bad_replica, tbl || ' (replident=' || replica_setting::text || ')');
        END IF;
    END LOOP;

    IF array_length(missing_pub, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'AUDIT FAILED: tables NOT in supabase_realtime publication: %', missing_pub;
    END IF;

    IF array_length(bad_replica, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'AUDIT FAILED: tables without REPLICA IDENTITY FULL: %', bad_replica;
    END IF;

    RAISE NOTICE '✅ All % social-realtime tables verified in publication AND REPLICA IDENTITY FULL', array_length(expected_tables, 1);
END $$;

COMMIT;

-- ─── Post-deploy verification (run manually in SQL Editor) ─────────
--
-- Confirm the publication membership directly:
-- SELECT tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
-- ORDER BY tablename;
--
-- Confirm REPLICA IDENTITY FULL on every social table:
-- SELECT c.relname,
--        CASE c.relreplident
--          WHEN 'd' THEN 'default (primary key)'
--          WHEN 'n' THEN 'nothing'
--          WHEN 'f' THEN 'full'
--          WHEN 'i' THEN 'index'
--        END AS replica_identity
-- FROM pg_class c
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- WHERE n.nspname = 'public'
--   AND c.relname IN (
--      'friendships', 'shared_workouts', 'challenge_participants',
--      'challenge_daily_progress', 'group_challenges',
--      'private_challenges', 'private_challenge_invites',
--      'private_challenge_members', 'private_challenge_daily_progress',
--      'private_challenge_chat', 'community_challenges',
--      'community_challenge_participants',
--      'community_challenge_daily_progress', 'friend_activity_feed',
--      'privacy_change_events', 'exercises'
--   )
-- ORDER BY c.relname;
