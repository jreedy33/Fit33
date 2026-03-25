-- Fix: PGRST204 "Could not find 'completed_days' column in user_programs schema"
-- The SmartProgramEngine.saveProgramsToCloud() sends completed_days, total_days,
-- program_name, template_id, current_day, is_active, started_date, program_data,
-- last_updated — but some columns may be missing from the live table.
-- Crash ID: a63bc3a6 (v1.34.0)

BEGIN;

ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS completed_days INTEGER DEFAULT 0;
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS total_days INTEGER DEFAULT 0;
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS program_name TEXT DEFAULT '';
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS template_id TEXT DEFAULT '';
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS current_day INTEGER DEFAULT 1;
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS started_date TEXT;
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS program_data TEXT DEFAULT '{}';
ALTER TABLE user_programs ADD COLUMN IF NOT EXISTS last_updated TEXT;

COMMIT;

-- Rollback:
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS completed_days;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS total_days;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS program_name;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS template_id;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS current_day;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS is_active;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS started_date;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS program_data;
-- ALTER TABLE user_programs DROP COLUMN IF EXISTS last_updated;
