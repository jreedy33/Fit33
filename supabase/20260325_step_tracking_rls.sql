-- Fix: step_tracking has RLS enabled but no policies, blocking all client writes.
-- Error: "new row violates row-level security policy for table step_tracking"
--
-- All client operations use auth.uid() = user_id:
--   INSERT/UPSERT: SupabaseManager.saveStepData(), batchSaveStepData()
--   SELECT:        SupabaseManager.fetchRecentSteps(), DataDownloadView

ALTER TABLE step_tracking ENABLE ROW LEVEL SECURITY;

-- Users can insert their own step data
CREATE POLICY "Users can insert own steps"
    ON step_tracking FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own step data (upsert on user_id,date)
CREATE POLICY "Users can update own steps"
    ON step_tracking FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can read their own step data
CREATE POLICY "Users can read own steps"
    ON step_tracking FOR SELECT
    USING (auth.uid() = user_id);
