-- ═══════════════════════════════════════════════════════════════
-- CRASH REPORTS TABLE
-- Production-grade error/crash reporting for Fit33 iOS app
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS crash_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- User context
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_email TEXT,
    user_name TEXT,
    
    -- Report classification
    report_type TEXT NOT NULL DEFAULT 'error',  -- 'crash', 'error', 'critical', 'warning', 'fatal_signal'
    severity TEXT NOT NULL DEFAULT 'error',     -- 'low', 'medium', 'high', 'critical', 'fatal'
    
    -- Error details
    error_message TEXT NOT NULL,
    error_domain TEXT,               -- e.g. 'Network', 'CoreData', 'Auth', 'Workout', 'UI'
    error_code TEXT,                 -- Specific error code if available
    stack_trace TEXT,                -- Full or symbolicated stack trace
    
    -- Crash fingerprint for deduplication/grouping
    fingerprint TEXT NOT NULL,       -- Hash of (error_message + top_stack_frames + domain)
    
    -- Breadcrumbs - last N user actions before crash
    breadcrumbs JSONB,              -- [{action, screen, timestamp}, ...]
    
    -- Device context
    device_model TEXT,              -- e.g. 'iPhone 15 Pro'
    os_version TEXT,                -- e.g. 'iOS 18.2'
    app_version TEXT,               -- e.g. '1.4.2'
    build_number TEXT,              -- e.g. '142'
    
    -- Runtime context
    current_screen TEXT,            -- Screen user was on when crash occurred
    memory_usage_mb REAL,           -- App memory usage at time of crash
    free_memory_mb REAL,            -- Device free memory
    battery_level REAL,             -- Battery percentage 0-1
    is_low_power_mode BOOLEAN DEFAULT FALSE,
    network_type TEXT,              -- 'wifi', 'cellular', 'none'
    
    -- Session context
    session_id TEXT,                -- Links to session log
    session_duration_seconds INTEGER, -- How long the session was before crash
    actions_before_crash INTEGER,   -- Number of user actions in session
    
    -- Additional data
    additional_context JSONB,       -- Any extra key-value data
    session_log_snippet TEXT,       -- Last ~50 lines of session log
    
    -- Admin management
    status TEXT NOT NULL DEFAULT 'new',  -- 'new', 'investigating', 'identified', 'resolved', 'wont_fix', 'duplicate'
    admin_notes TEXT,               -- Notes from admin investigating
    resolved_at TIMESTAMPTZ,
    resolved_by TEXT,
    linked_bug_report_id UUID,      -- Optional link to user-submitted bug report
    
    -- Timestamps
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- When the crash/error actually happened
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- When it was uploaded (may differ for crashes)
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- INDEXES for fast querying
-- ═══════════════════════════════════════════════════════════════

-- Most common query: recent reports
CREATE INDEX idx_crash_reports_created_at ON crash_reports(created_at DESC);

-- Filter by status (admin workflow)
CREATE INDEX idx_crash_reports_status ON crash_reports(status);

-- Filter by severity (triage)
CREATE INDEX idx_crash_reports_severity ON crash_reports(severity);

-- Filter by user
CREATE INDEX idx_crash_reports_user_id ON crash_reports(user_id);

-- Group by fingerprint (dedup/aggregate)
CREATE INDEX idx_crash_reports_fingerprint ON crash_reports(fingerprint);

-- Filter by report type
CREATE INDEX idx_crash_reports_type ON crash_reports(report_type);

-- Combined for common admin queries
CREATE INDEX idx_crash_reports_status_severity ON crash_reports(status, severity, created_at DESC);

-- App version tracking
CREATE INDEX idx_crash_reports_app_version ON crash_reports(app_version);

-- ═══════════════════════════════════════════════════════════════
-- RLS POLICIES
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE crash_reports ENABLE ROW LEVEL SECURITY;

-- Users can insert their own crash reports
CREATE POLICY "Users can insert own crash reports"
    ON crash_reports FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Users can read their own crash reports
CREATE POLICY "Users can read own crash reports"
    ON crash_reports FOR SELECT
    USING (auth.uid() = user_id);

-- Service role (admin CMS) has full access via supabase-admin client
