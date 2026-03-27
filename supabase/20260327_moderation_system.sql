-- ============================================================================
-- Moderation System: user_reports + user_suspensions
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed')),
  resolution_notes TEXT,
  resolved_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  CHECK (reporter_id != reported_user_id)
);

ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_user_reports_status ON user_reports (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON user_reports (reported_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports (reporter_id, created_at DESC);

-- Users can insert reports and read their own
CREATE POLICY "Users can report others" ON user_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());

CREATE POLICY "Users can see own reports" ON user_reports
  FOR SELECT USING (reporter_id = auth.uid());

-- Suspensions table
CREATE TABLE IF NOT EXISTS user_suspensions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  suspended_by TEXT NOT NULL,
  suspended_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  lifted_at TIMESTAMPTZ,
  lifted_by TEXT
);

ALTER TABLE user_suspensions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_user_suspensions_user ON user_suspensions (user_id, suspended_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_suspensions_active ON user_suspensions (user_id)
  WHERE lifted_at IS NULL;

-- App-facing: check if current user is suspended
CREATE OR REPLACE FUNCTION is_user_suspended()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_suspensions
    WHERE user_id = auth.uid()
      AND lifted_at IS NULL
      AND (expires_at IS NULL OR expires_at > NOW())
  );
$$;

GRANT EXECUTE ON FUNCTION is_user_suspended() TO authenticated;

DO $$ BEGIN
  RAISE NOTICE 'Moderation system created (user_reports, user_suspensions, is_user_suspended RPC)';
END $$;
