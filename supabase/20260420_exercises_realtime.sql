-- ============================================================================
-- 20260420 — CMS EXERCISE EDITS → REAL-TIME IN-APP UPDATES
-- ============================================================================
-- Problem: Admin CMS edits to the `exercises` table took up to 6 hours to
-- appear in the app (syncExercisesFromCloud interval) AND were invisible to
-- cold-start fetches that read from `mv_public_exercises` (materialized view
-- that never auto-refreshes when the base table changes).
--
-- Fix:
--   1. Enable Supabase Realtime publication on `exercises` so the iOS app
--      can subscribe to INSERT/UPDATE/DELETE events.
--   2. Set REPLICA IDENTITY FULL so UPDATE events include the full NEW row
--      (Supabase Realtime v2 otherwise only ships changed columns).
--   3. Add a UNIQUE index on `mv_public_exercises(id)` so the view can be
--      refreshed CONCURRENTLY (no table lock → safe to call on every save).
--   4. Expose a SECURITY DEFINER RPC `refresh_mv_public_exercises()` that the
--      admin CMS calls after every exercise create/update/delete so cold-start
--      app launches also see the latest data.
--
-- Safe to run multiple times — every statement is idempotent.
-- ============================================================================

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Realtime publication + full replica identity
-- ───────────────────────────────────────────────────────────────────────────

-- REPLICA IDENTITY FULL so the realtime `UPDATE` payload contains the entire
-- new row (not just changed columns) AND the old row for diff detection.
ALTER TABLE public.exercises REPLICA IDENTITY FULL;

-- Add the table to Supabase's realtime publication if it isn't already.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'exercises'
    ) THEN
        EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.exercises';
        RAISE NOTICE '✅ Added public.exercises to supabase_realtime publication';
    ELSE
        RAISE NOTICE 'ℹ️ public.exercises already in supabase_realtime publication';
    END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Materialized view → refreshable CONCURRENTLY
-- ───────────────────────────────────────────────────────────────────────────

-- Ensure there is a UNIQUE index on `id` so REFRESH MATERIALIZED VIEW
-- CONCURRENTLY works (Postgres hard requirement). If the matview doesn't
-- exist we silently skip — the app falls back to the `exercises` table.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public'
              AND tablename  = 'mv_public_exercises'
              AND indexdef ILIKE '%UNIQUE%'
              AND indexdef ILIKE '%(id)%'
        ) THEN
            EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_public_exercises_id_unique ON public.mv_public_exercises(id)';
            RAISE NOTICE '✅ Created UNIQUE index on mv_public_exercises(id) — CONCURRENT refresh now possible';
        ELSE
            RAISE NOTICE 'ℹ️ UNIQUE index on mv_public_exercises(id) already exists';
        END IF;
    ELSE
        RAISE NOTICE 'ℹ️ mv_public_exercises does not exist — skipping unique index';
    END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Refresh RPC for the admin CMS
-- ───────────────────────────────────────────────────────────────────────────
-- SECURITY DEFINER so the service-role admin client can invoke it without
-- needing direct matview privileges. Returns quickly because CONCURRENTLY
-- only blocks on the small diff since the last refresh.

CREATE OR REPLACE FUNCTION public.refresh_mv_public_exercises()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises') THEN
        BEGIN
            REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_public_exercises;
        EXCEPTION WHEN feature_not_supported OR others THEN
            -- Fall back to a blocking refresh if CONCURRENT fails
            -- (e.g. very first refresh, or unique index missing somehow).
            REFRESH MATERIALIZED VIEW public.mv_public_exercises;
        END;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_mv_public_exercises() FROM public;
REVOKE ALL ON FUNCTION public.refresh_mv_public_exercises() FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.refresh_mv_public_exercises() TO service_role;

COMMENT ON FUNCTION public.refresh_mv_public_exercises() IS
  'Admin-only refresh of mv_public_exercises. Called by the CMS after every exercise create/update/delete so cold-start app launches see the latest data. Runs CONCURRENTLY — does not block app readers.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Verification
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    in_publication BOOLEAN;
    replica_identity CHAR;
    matview_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'exercises'
    ) INTO in_publication;

    SELECT relreplident INTO replica_identity
    FROM pg_class WHERE oid = 'public.exercises'::regclass;

    SELECT EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises') INTO matview_exists;

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Exercises realtime setup verification:';
    RAISE NOTICE '  exercises in supabase_realtime publication: %', in_publication;
    RAISE NOTICE '  exercises REPLICA IDENTITY (f=FULL):        %', replica_identity;
    RAISE NOTICE '  mv_public_exercises exists:                 %', matview_exists;
    RAISE NOTICE '  refresh_mv_public_exercises RPC:            ready';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;
