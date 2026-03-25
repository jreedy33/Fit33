-- Version changelogs: auto-captured on every push to main via GitHub Action
-- Stores technical diffs, Claude-generated summaries, and affected areas
-- Used by CMS crash analysis to correlate crashes with code changes

CREATE TABLE IF NOT EXISTS version_changelogs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version TEXT,
  build_number TEXT,
  commit_sha TEXT UNIQUE NOT NULL,
  commit_message TEXT NOT NULL,
  changed_files TEXT[] DEFAULT '{}',
  swift_files_changed TEXT[] DEFAULT '{}',
  diff_stats TEXT,
  technical_summary TEXT,
  user_facing_summary TEXT,
  areas_affected TEXT[] DEFAULT '{}',
  is_version_bump BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE version_changelogs ENABLE ROW LEVEL SECURITY;

-- Service role can insert (GitHub Action uses service_role key)
CREATE POLICY "service_role_insert_changelogs"
  ON version_changelogs FOR INSERT
  TO service_role
  WITH CHECK (true);

-- Service role can read
CREATE POLICY "service_role_select_changelogs"
  ON version_changelogs FOR SELECT
  TO service_role
  USING (true);

-- Authenticated admin users can read via CMS
CREATE POLICY "authenticated_select_changelogs"
  ON version_changelogs FOR SELECT
  TO authenticated
  USING (true);

CREATE INDEX idx_version_changelogs_version ON version_changelogs (version);
CREATE INDEX idx_version_changelogs_created ON version_changelogs (created_at DESC);
