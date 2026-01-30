-- =====================================================
-- ADD USER NAME TO BUG REPORTS
-- =====================================================
-- This adds the user_name column to bug_reports table
-- so we can identify who submitted each bug report
-- =====================================================

-- Step 1: Add user_name column to bug_reports table
ALTER TABLE bug_reports 
ADD COLUMN IF NOT EXISTS user_name TEXT;

-- Step 2: Create an index on user_name for faster filtering
CREATE INDEX IF NOT EXISTS idx_bug_reports_user_name 
ON bug_reports(user_name);

-- Step 3: Optionally backfill existing records (if you have a user_profiles table)
-- This will populate user_name for existing bug reports that have a user_id
UPDATE bug_reports br
SET user_name = up.name
FROM user_profiles up
WHERE br.user_id = up.id
AND br.user_name IS NULL;

-- Step 4: Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'bug_reports' 
AND column_name = 'user_name';

SELECT '✅ USER NAME COLUMN ADDED TO BUG REPORTS!' AS status;
