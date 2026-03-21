-- ============================================================================
-- SCHEMA FIXES FROM DEV SESSION LOG ANALYSIS
-- Date: 2026-03-21
-- Source: Claude analysis of dev session 50E10EF5
-- Fixes:
--   1. Recreate crash_reports table (was dropped but service still writes to it)
--   2. Add UNIQUE constraint on user_push_tokens(user_id, device_token)
--   3. Add user_equipment column to collaborative_workout_data
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Recreate crash_reports table
-- ============================================================================
-- Was dropped by 20260320_drop_dead_tables.sql (had 0 rows at audit time)
-- but CrashReportingService.swift actively writes to it on every error/crash.

CREATE TABLE IF NOT EXISTS crash_reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  user_email TEXT,
  user_name TEXT,
  report_type TEXT NOT NULL DEFAULT 'error',
  severity TEXT NOT NULL DEFAULT 'medium',
  error_message TEXT NOT NULL,
  error_domain TEXT,
  error_code TEXT,
  stack_trace TEXT,
  fingerprint TEXT NOT NULL,
  breadcrumbs JSONB,
  device_model TEXT,
  os_version TEXT,
  app_version TEXT,
  build_number TEXT,
  current_screen TEXT,
  memory_usage_mb DOUBLE PRECISION,
  free_memory_mb DOUBLE PRECISION,
  battery_level DOUBLE PRECISION,
  is_low_power_mode BOOLEAN DEFAULT false,
  network_type TEXT,
  session_id TEXT,
  session_duration_seconds INT,
  actions_before_crash INT,
  additional_context JSONB,
  session_log_snippet TEXT,
  status TEXT DEFAULT 'new',
  occurred_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_crash_reports_user_id ON crash_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_crash_reports_status ON crash_reports(status);
CREATE INDEX IF NOT EXISTS idx_crash_reports_created ON crash_reports(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_crash_reports_fingerprint ON crash_reports(fingerprint);

ALTER TABLE crash_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own crash reports" ON crash_reports;
CREATE POLICY "Users can insert own crash reports"
  ON crash_reports FOR INSERT
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

DROP POLICY IF EXISTS "Users can view own crash reports" ON crash_reports;
CREATE POLICY "Users can view own crash reports"
  ON crash_reports FOR SELECT
  USING (auth.uid() = user_id OR user_id IS NULL);

DO $$ BEGIN
  RAISE NOTICE '1. crash_reports table recreated with RLS';
END $$;

-- ============================================================================
-- 2. Add UNIQUE constraint on user_push_tokens(user_id, device_token)
-- ============================================================================
-- PushNotificationService.swift uses onConflict: "user_id, device_token"
-- but the constraint doesn't exist, causing upsert failures.

-- Deduplicate first (keep newest per user+token pair)
DELETE FROM user_push_tokens a
USING user_push_tokens b
WHERE a.user_id = b.user_id
  AND a.device_token = b.device_token
  AND a.updated_at < b.updated_at;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_push_tokens_user_device'
  ) THEN
    ALTER TABLE user_push_tokens
      ADD CONSTRAINT uq_user_push_tokens_user_device UNIQUE (user_id, device_token);
  END IF;
END $$;

DO $$ BEGIN
  RAISE NOTICE '2. Added UNIQUE(user_id, device_token) on user_push_tokens';
END $$;

-- ============================================================================
-- 3. Add user_equipment column to collaborative_workout_data
-- ============================================================================
-- CollaborativeLearningEngine.swift inserts this column but it doesn't exist.

ALTER TABLE collaborative_workout_data
  ADD COLUMN IF NOT EXISTS user_equipment JSONB;

DO $$ BEGIN
  RAISE NOTICE '3. Added user_equipment JSONB column to collaborative_workout_data';
END $$;

COMMIT;
