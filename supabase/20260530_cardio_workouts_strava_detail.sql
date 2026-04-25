-- =============================================================================
-- cardio_workouts: Strava detail + streams enrichment columns
-- =============================================================================
-- Phase 2 of the Strava Integration Upgrade. The current Strava sync only
-- writes the fields available in `GET /athlete/activities` (the list
-- endpoint). Strava exposes much richer data via:
--   * `GET /activities/{id}`        — splits, segment efforts, gear, kudos,
--                                     suffer score, polyline summary, etc.
--   * `GET /activities/{id}/streams`— full HR / pace / cadence / power /
--                                     altitude time-series for the activity.
--
-- We persist the fields we want to show in the Dashboard recap, segment PR
-- insights, and HR-zone analytics directly as columns; everything else lands
-- in `streams_json` / `splits_json` / `segment_efforts_json` so the recap
-- sheet can render arbitrary cuts without a follow-up API call.
--
-- Idempotent — uses `IF NOT EXISTS` so re-running this migration on an
-- already-enriched DB is a no-op (Data invariant #20).
-- =============================================================================

BEGIN;

ALTER TABLE public.cardio_workouts
    ADD COLUMN IF NOT EXISTS suffer_score          INT,
    ADD COLUMN IF NOT EXISTS kudos_count           INT,
    ADD COLUMN IF NOT EXISTS achievement_count     INT,
    ADD COLUMN IF NOT EXISTS polyline_summary      TEXT,
    ADD COLUMN IF NOT EXISTS splits_json           JSONB,
    ADD COLUMN IF NOT EXISTS segment_efforts_json  JSONB,
    ADD COLUMN IF NOT EXISTS streams_json          JSONB,
    ADD COLUMN IF NOT EXISTS gear_name             TEXT,
    ADD COLUMN IF NOT EXISTS detail_synced_at      TIMESTAMPTZ;

COMMENT ON COLUMN public.cardio_workouts.suffer_score IS
    'Strava Relative Effort score (formerly "Suffer Score"). NULL when the source did not provide one.';
COMMENT ON COLUMN public.cardio_workouts.kudos_count IS
    'Strava kudos count at the time the activity detail was synced; refreshed on next enrichment pass.';
COMMENT ON COLUMN public.cardio_workouts.achievement_count IS
    'Strava achievement count (PRs / KOMs detected on the activity).';
COMMENT ON COLUMN public.cardio_workouts.polyline_summary IS
    'Encoded summary polyline from Strava `map.summary_polyline` — used for the dashboard mini-map preview.';
COMMENT ON COLUMN public.cardio_workouts.splits_json IS
    'Strava `splits_metric` array (per-km splits with pace, elevation, HR).';
COMMENT ON COLUMN public.cardio_workouts.segment_efforts_json IS
    'Strava `segment_efforts` array (filtered to PR-eligible / leaderboard segments).';
COMMENT ON COLUMN public.cardio_workouts.streams_json IS
    'Strava streams (heartrate, cadence, watts, velocity_smooth, altitude) keyed by stream type. Used for HR zone + pace charts in the recap sheet.';
COMMENT ON COLUMN public.cardio_workouts.gear_name IS
    'Strava gear (shoe / bike) name attached to the activity.';
COMMENT ON COLUMN public.cardio_workouts.detail_synced_at IS
    'Timestamp of the last successful detail+streams enrichment for this row. NULL = list-only (raw sync).';

-- Useful for the nightly insights computer to find activities that need
-- enrichment (or are due for a kudos refresh).
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_strava_pending_enrichment
    ON public.cardio_workouts (user_id, started_at DESC)
    WHERE source = 'strava' AND detail_synced_at IS NULL;

COMMIT;
