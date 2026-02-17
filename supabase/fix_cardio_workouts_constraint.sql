-- ============================================================================
-- FIX: cardio_workouts missing unique constraint for ON CONFLICT upsert
-- ============================================================================
-- Error: "there is no unique or exclusion constraint matching the ON CONFLICT specification"
-- The app upserts HealthKit workouts with: ON CONFLICT (user_id, source, external_id)
-- but the table is missing this unique constraint.
-- ============================================================================

-- Add the unique constraint that the upsert needs
-- First, clean up any existing duplicates (keep the newest one)
DELETE FROM cardio_workouts a
USING cardio_workouts b
WHERE a.id < b.id
  AND a.user_id = b.user_id
  AND a.source = b.source
  AND a.external_id = b.external_id
  AND a.source IS NOT NULL
  AND a.external_id IS NOT NULL;

-- Now add the unique constraint
-- Use a partial index (only where source and external_id are NOT NULL)
-- This allows regular inserts without source/external_id to work normally
CREATE UNIQUE INDEX IF NOT EXISTS idx_cardio_workouts_user_source_external
    ON cardio_workouts (user_id, source, external_id)
    WHERE source IS NOT NULL AND external_id IS NOT NULL;

DO $$
BEGIN
    RAISE NOTICE '✅ Added unique index on cardio_workouts(user_id, source, external_id)';
    RAISE NOTICE '   HealthKit/Strava upserts will now work correctly';
END $$;
