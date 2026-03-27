-- Fix: user_programs.program_id NOT NULL constraint causes crash
-- SmartProgramEngine.saveProgramsToCloud() sends template_id but not program_id.
-- The existing NOT NULL constraint on program_id causes PGRST 23502 errors.
-- Crash IDs: 150327aa, e7a02536, 0bc360b7 (v1.35.0)

BEGIN;

ALTER TABLE user_programs ALTER COLUMN program_id DROP NOT NULL;
ALTER TABLE user_programs ALTER COLUMN program_id SET DEFAULT NULL;

COMMIT;
