-- ============================================================================
-- Enhance admin_audit_log for richer auditing
-- ============================================================================
-- Adds details JSONB (before/after diffs) and admin_email (denormalized)
-- to support the new Audit Log Viewer in the CMS.
-- ============================================================================

ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS details JSONB DEFAULT '{}';
ALTER TABLE admin_audit_log ADD COLUMN IF NOT EXISTS admin_email TEXT;

CREATE INDEX IF NOT EXISTS idx_audit_log_created ON admin_audit_log (created_at DESC);

DO $$ BEGIN
  RAISE NOTICE 'admin_audit_log enhanced with details JSONB and admin_email columns';
END $$;
