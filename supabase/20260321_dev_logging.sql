-- ============================================================================
-- DEVELOPER ADVANCED LOGGING SYSTEM
-- Date: 2026-03-21
-- Purpose: Per-user toggleable deep session logging for developer dogfooding.
--   Admins enable logging for specific users via CMS toggle.
--   iOS streams detailed session data to Supabase in realtime.
--   Claude analyzes sessions and suggests code fixes.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. dev_logging_users — which users have advanced logging enabled
-- ============================================================================

CREATE TABLE IF NOT EXISTS dev_logging_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  enabled BOOLEAN DEFAULT true,
  enabled_by TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT uq_dev_logging_user UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_dev_logging_users_user_id ON dev_logging_users(user_id);

ALTER TABLE dev_logging_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages dev logging" ON dev_logging_users;
CREATE POLICY "Service role manages dev logging"
  ON dev_logging_users FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- 2. dev_session_logs — the actual log data (batched entries)
-- ============================================================================

CREATE TABLE IF NOT EXISTS dev_session_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  session_id TEXT NOT NULL,
  batch_index INT NOT NULL DEFAULT 0,
  entries JSONB NOT NULL DEFAULT '[]',
  device_info JSONB,
  session_summary JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dev_session_logs_user_session
  ON dev_session_logs(user_id, session_id, batch_index);

CREATE INDEX IF NOT EXISTS idx_dev_session_logs_created
  ON dev_session_logs(created_at);

ALTER TABLE dev_session_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages session logs" ON dev_session_logs;
CREATE POLICY "Service role manages session logs"
  ON dev_session_logs FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- 3. dev_log_suggestions — Claude's fix suggestions per session
-- ============================================================================

CREATE TABLE IF NOT EXISTS dev_log_suggestions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL,
  user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  file_path TEXT,
  code_diff TEXT,
  severity TEXT DEFAULT 'medium',
  status TEXT DEFAULT 'new',
  pr_url TEXT,
  pr_branch TEXT,
  analysis_model TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dev_log_suggestions_session
  ON dev_log_suggestions(session_id);

ALTER TABLE dev_log_suggestions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages suggestions" ON dev_log_suggestions;
CREATE POLICY "Service role manages suggestions"
  ON dev_log_suggestions FOR ALL
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- 4. Cleanup function — purge logs older than 30 days
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_dev_logs()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM dev_session_logs
  WHERE created_at < now() - INTERVAL '30 days';
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  DELETE FROM dev_log_suggestions
  WHERE created_at < now() - INTERVAL '90 days';
  
  RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_old_dev_logs() TO service_role;

-- ============================================================================
-- 5. RPC to check if user has logging enabled (called from iOS on login)
-- ============================================================================

CREATE OR REPLACE FUNCTION is_dev_logging_enabled()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM dev_logging_users
    WHERE user_id = auth.uid() AND enabled = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION is_dev_logging_enabled() TO authenticated;

DO $$ BEGIN
  RAISE NOTICE '✅ Developer logging tables created: dev_logging_users, dev_session_logs, dev_log_suggestions';
END $$;

COMMIT;
