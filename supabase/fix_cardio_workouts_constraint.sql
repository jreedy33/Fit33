-- ============================================================================
-- FIX: cardio_workouts missing unique constraint for ON CONFLICT upsert
-- ============================================================================
-- Error: "there is no unique or exclusion constraint matching the ON CONFLICT specification"
-- The app upserts HealthKit workouts with: ON CONFLICT (user_id, source, external_id)
-- but the table needs a proper (non-partial) unique constraint.
--
-- IMPORTANT: PostgREST's onConflict parameter does NOT support partial indexes
-- (indexes with a WHERE clause). It generates ON CONFLICT (col1, col2, col3)
-- without a WHERE predicate, so PostgreSQL can't match it to a partial index.
-- Solution: use a regular (non-partial) unique index instead.
-- NULLs are treated as distinct by PostgreSQL, so rows with NULL source/external_id
-- won't conflict with each other (which is the correct behavior).
-- ============================================================================

-- Drop the old partial index if it exists (it won't match PostgREST's ON CONFLICT)
DROP INDEX IF EXISTS idx_cardio_workouts_user_source_external;

-- Clean up any existing duplicates (keep the newest one by id)
DELETE FROM cardio_workouts a
USING cardio_workouts b
WHERE a.id < b.id
  AND a.user_id = b.user_id
  AND a.source = b.source
  AND a.external_id = b.external_id
  AND a.source IS NOT NULL
  AND a.external_id IS NOT NULL;

-- Create a non-partial unique index that PostgREST can match
-- NULLs are distinct in PostgreSQL unique indexes, so rows without
-- source/external_id won't conflict with each other.
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_workouts_user_source_external
    ON cardio_workouts (user_id, source, external_id);

DO $$
BEGIN
    RAISE NOTICE '✅ Created non-partial unique index on cardio_workouts(user_id, source, external_id)';
    RAISE NOTICE '   PostgREST upserts with onConflict: "user_id,source,external_id" will now work';
END $$;
