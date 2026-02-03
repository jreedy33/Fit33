-- =====================================================
-- ADD USER EMAIL TO BUG REPORTS
-- =====================================================
-- This adds the user_email column to bug_reports table
-- so we can contact users about their bug reports
-- =====================================================

-- Step 1: Add user_email column to bug_reports table
ALTER TABLE bug_reports 
ADD COLUMN IF NOT EXISTS user_email TEXT;

-- Step 2: Create an index on user_email for faster filtering
CREATE INDEX IF NOT EXISTS idx_bug_reports_user_email 
ON bug_reports(user_email);

-- Step 3: Backfill existing records from user_profiles
UPDATE bug_reports br
SET user_email = up.email
FROM user_profiles up
WHERE br.user_id = up.id
AND br.user_email IS NULL;

-- Step 4: Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'bug_reports' 
AND column_name = 'user_email';

SELECT '✅ USER EMAIL COLUMN ADDED TO BUG REPORTS!' AS status;
