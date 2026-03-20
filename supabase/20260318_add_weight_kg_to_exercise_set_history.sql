-- Migration: Add weight_kg column to exercise_set_history
-- Date: 2026-03-18
-- Agent: Data Backend
-- Reason: Store both lbs and kg values for weight unit toggle in active workout

BEGIN;

ALTER TABLE exercise_set_history
ADD COLUMN IF NOT EXISTS weight_kg DOUBLE PRECISION;

COMMENT ON COLUMN exercise_set_history.weight_kg IS 'Weight in kilograms (auto-calculated from weight in lbs)';

-- Backfill existing rows: convert lbs to kg
UPDATE exercise_set_history
SET weight_kg = ROUND((weight * 0.453592)::numeric, 1)
WHERE weight_kg IS NULL AND weight IS NOT NULL;

COMMIT;

-- ROLLBACK:
-- ALTER TABLE exercise_set_history DROP COLUMN IF EXISTS weight_kg;
