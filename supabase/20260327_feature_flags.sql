-- ============================================================================
-- Feature Flags system
-- ============================================================================
-- Supports toggling, gradual rollout (0-100%), platform targeting,
-- minimum app version, and arbitrary metadata.
-- ============================================================================

CREATE TABLE IF NOT EXISTS feature_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  description TEXT,
  enabled BOOLEAN NOT NULL DEFAULT false,
  rollout_percentage INT NOT NULL DEFAULT 100
    CHECK (rollout_percentage BETWEEN 0 AND 100),
  platform TEXT NOT NULL DEFAULT 'all'
    CHECK (platform IN ('all', 'ios', 'android')),
  min_app_version TEXT,
  metadata JSONB DEFAULT '{}',
  created_by TEXT,
  updated_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_feature_flags_key ON feature_flags (key);
CREATE INDEX IF NOT EXISTS idx_feature_flags_enabled ON feature_flags (enabled) WHERE enabled = true;

-- App-facing RPC: returns flags enabled for this user's platform/version.
-- Rollout uses hashtext(user_id) so the same user always gets the same result.
CREATE OR REPLACE FUNCTION get_active_feature_flags(
  p_platform TEXT DEFAULT 'ios',
  p_app_version TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_hash INT;
  v_result JSONB := '{}';
  v_row RECORD;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN '{}'::JSONB;
  END IF;

  v_hash := abs(hashtext(v_user_id::text)) % 100;

  FOR v_row IN
    SELECT key, metadata
    FROM feature_flags
    WHERE enabled = true
      AND (platform = 'all' OR platform = p_platform)
      AND v_hash < rollout_percentage
      AND (min_app_version IS NULL OR p_app_version IS NULL OR p_app_version >= min_app_version)
  LOOP
    v_result := v_result || jsonb_build_object(v_row.key, COALESCE(v_row.metadata, '{}'::jsonb) || '{"enabled": true}'::jsonb);
  END LOOP;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_feature_flags(TEXT, TEXT) TO authenticated;

DO $$ BEGIN
  RAISE NOTICE 'feature_flags table and get_active_feature_flags() RPC created';
END $$;
