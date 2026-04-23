-- =============================================================================
-- SUPERSEDED 2026-04-26 — Q2-96
-- =============================================================================
-- This file is a duplicate of 20260307_activity_feed_realtime.sql (both added
-- `friend_activity_feed` to the supabase_realtime publication on the same
-- day). The canonical file is 20260307_activity_feed_realtime.sql; running
-- this one a second time would throw `duplicate_object`.
--
-- Kept in-tree as a breadcrumb so MIGRATION_INDEX references still resolve.
-- Do NOT re-run against any environment.
-- =============================================================================

-- No-op: the publication ADD now lives in 20260307_activity_feed_realtime.sql.
SELECT 1;
