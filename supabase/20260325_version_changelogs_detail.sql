-- Add rich per-file code change detail to version_changelogs
-- Each entry is: { file, snippet, rationale, risk_areas }
-- Gives Claude full context when correlating crashes with code changes

ALTER TABLE version_changelogs
  ADD COLUMN IF NOT EXISTS code_changes_detail JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN version_changelogs.code_changes_detail IS
  'Array of {file, snippet, rationale, risk_areas} per changed Swift file';
