-- =============================================================================
-- cardio_workouts: one-time dedup of overlapping rows (same user, same origin)
-- =============================================================================
-- WHOOP's API sometimes returns multiple `workout` records for a single
-- physical session — an auto-detected generic "Activity" (sport_name=null →
-- activity_type="other") alongside the user-logged specific sport. Our client
-- dedup previously only guarded `(user_id, source='whoop', external_id)` so
-- every returned id produced its own row and the Workout History list showed
-- two entries with the WHOOP badge (see screenshot report 2026-04-20).
--
-- Client-side dedup is now in HealthDataService.syncWhoopData (time-overlap
-- check, keeps the higher-quality row). This migration cleans up the rows
-- that were already inserted before that fix shipped.
--
-- Scope: same-user, same canonical origin (whoop, strava, fitbit, oura, ...),
-- overlapping time windows. The row with the richest data wins:
--   +10 if activity_type is specific (not other/workout/unknown)
--    +3 if average_heart_rate > 0
--    +2 if distance_meters > 0
--    +1 if calories_burned > 0
--    +1 if duration_seconds > 0
--   tie-break: newer `created_at` wins, then larger `id` (stable).
--
-- Safe to re-run: after it runs once the overlap sets become singletons.
-- =============================================================================

BEGIN;

-- Resolve canonical origin using the same rules as CardioWorkoutDTO.resolvedOrigin.
-- We need a stable per-row origin key so we only dedup WHOOP-vs-WHOOP and not
-- collapse, say, a treadmill run that happens to overlap a HealthKit walk
-- authored by a different app.
WITH row_origin AS (
    SELECT
        id,
        user_id,
        started_at,
        completed_at,
        activity_type,
        average_heart_rate,
        distance_meters,
        calories_burned,
        duration_seconds,
        created_at,
        COALESCE(
            origin_app,
            CASE source
                WHEN 'strava' THEN 'strava'
                WHEN 'fitbit' THEN 'fitbit'
                WHEN 'whoop'  THEN 'whoop'
                WHEN 'oura'   THEN 'oura'
                WHEN 'fit33'  THEN 'fit33'
                ELSE NULL
            END
        ) AS canonical_origin
    FROM public.cardio_workouts
    WHERE started_at IS NOT NULL
      AND completed_at IS NOT NULL
      AND completed_at > started_at
),
scored AS (
    SELECT
        id,
        user_id,
        started_at,
        completed_at,
        canonical_origin,
        -- richness score (matches Swift cardioQualityScore)
        (CASE WHEN LOWER(COALESCE(activity_type, '')) NOT IN ('', 'other', 'workout', 'unknown') THEN 10 ELSE 0 END)
      + (CASE WHEN COALESCE(average_heart_rate, 0) > 0 THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(distance_meters, 0)   > 0 THEN 2 ELSE 0 END)
      + (CASE WHEN COALESCE(calories_burned, 0)   > 0 THEN 1 ELSE 0 END)
      + (CASE WHEN COALESCE(duration_seconds, 0)  > 0 THEN 1 ELSE 0 END)
          AS quality_score,
        created_at
    FROM row_origin
    WHERE canonical_origin IS NOT NULL
),
-- Sessionize: walk rows sorted by start time per (user, origin). A new group
-- starts whenever the current row begins AFTER the running max end time of
-- the cluster. This yields one integer `cluster_id` per overlapping set.
clustered AS (
    SELECT
        id,
        user_id,
        canonical_origin,
        started_at,
        completed_at,
        quality_score,
        created_at,
        SUM(is_new_cluster) OVER (
            PARTITION BY user_id, canonical_origin
            ORDER BY started_at, id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cluster_id
    FROM (
        SELECT
            s.*,
            CASE
                WHEN s.started_at > LAG(max_end) OVER (PARTITION BY s.user_id, s.canonical_origin ORDER BY s.started_at, s.id)
                    THEN 1
                ELSE 0
            END AS is_new_cluster
        FROM (
            SELECT
                scored.*,
                MAX(completed_at) OVER (
                    PARTITION BY user_id, canonical_origin
                    ORDER BY started_at, id
                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS max_end
            FROM scored
        ) s
    ) t
),
ranked AS (
    SELECT
        id,
        user_id,
        canonical_origin,
        cluster_id,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, canonical_origin, cluster_id
            ORDER BY quality_score DESC, created_at DESC NULLS LAST, id DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY user_id, canonical_origin, cluster_id
        ) AS cluster_size
    FROM clustered
),
losers AS (
    SELECT id
    FROM ranked
    WHERE cluster_size > 1
      AND rn > 1
)
DELETE FROM public.cardio_workouts
WHERE id IN (SELECT id FROM losers);

-- Verification: after the dedup, there should be no same-user/same-origin
-- rows whose time windows still overlap. This block emits a NOTICE so the
-- migration runner surfaces any residual overlaps for manual review.
DO $$
DECLARE
    remaining_overlaps BIGINT;
BEGIN
    SELECT COUNT(*) INTO remaining_overlaps
    FROM public.cardio_workouts a
    JOIN public.cardio_workouts b
      ON a.user_id = b.user_id
     AND a.id < b.id
     AND COALESCE(a.origin_app, a.source) IS NOT DISTINCT FROM COALESCE(b.origin_app, b.source)
     AND a.started_at < b.completed_at
     AND b.started_at < a.completed_at;
    RAISE NOTICE 'cardio_workouts overlap dedup complete. Residual overlapping pairs (should be 0): %', remaining_overlaps;
END $$;

COMMIT;
