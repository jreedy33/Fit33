-- ============================================================================
-- FIX H-6: Create admin_audit_log table for GDPR compliance
-- ============================================================================
-- Date: March 7, 2026
-- Source: MASTER_TODO.md item H-6
--
-- Logs all write/bulk admin actions with IP, timestamp, and target.
-- Retention: 90 days (configurable via pg_cron cleanup).
--
-- RUN IN: Supabase Dashboard → SQL Editor
-- ============================================================================

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL,
    action TEXT NOT NULL,
    target_id TEXT,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON admin_audit_log (admin_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON admin_audit_log (action, created_at DESC);

DO $$
BEGIN
    RAISE NOTICE '✅ admin_audit_log table created';
    RAISE NOTICE '   RLS enabled (no SELECT policy = admin-only via service role)';
    RAISE NOTICE '   Indexes on (admin_user_id, created_at) and (action, created_at)';
END $$;
