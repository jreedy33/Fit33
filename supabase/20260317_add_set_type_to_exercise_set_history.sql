-- Migration: Add set_type column to exercise_set_history
-- Date: 2026-03-17
-- Agent: Data Backend
-- Reason: Enable warmup set filtering in history calculations and progressive overload

BEGIN;

ALTER TABLE exercise_set_history
ADD COLUMN IF NOT EXISTS set_type TEXT NOT NULL DEFAULT 'Normal';

COMMENT ON COLUMN exercise_set_history.set_type IS 'Set type: Normal, Warmup, Dropset, Failure, AMRAP, Pause Rep, Tempo';

CREATE INDEX IF NOT EXISTS idx_exercise_set_history_non_warmup
ON exercise_set_history (performance_id, set_number)
WHERE set_type != 'Warmup';

COMMIT;

-- ROLLBACK:
-- DROP INDEX IF EXISTS idx_exercise_set_history_non_warmup;
-- ALTER TABLE exercise_set_history DROP COLUMN IF EXISTS set_type;
