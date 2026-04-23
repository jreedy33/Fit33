-- 20260504_bug_report_state_snapshot.sql
-- Phase 7 / Cheat Code — Runtime state snapshot at shake time.
--
-- Most iOS "silent logic" bugs (widget A shows 199 / widget B shows 190, etc.)
-- are state-sync bugs. Claude is mediocre at reasoning about Swift files
-- blind but world-class at diffing *structured state*. Phase 7 captures the
-- published values of key ObservableObject singletons at the exact moment
-- the user shakes, sends them to Claude as a structured evidence block,
-- and — in practice — turns multi-hour silent-bug triage into a 1-shot
-- "these two values disagree, here's why" answer. See report 40 + 66
-- (Weight Dashboard/Nutrition sync) — Claude landed at 65% confidence
-- guessing the area; a state snapshot would have pinned the divergence.
--
-- Schema:
--   bug_reports.state_snapshot JSONB DEFAULT '{}'::jsonb — opaque dict
--     keyed by SnapshotProvider.snapshotKey ("WeightTrackingService") →
--     redacted published values ({ "recentLogs.count": 12,
--     "recentLogs.first.weightLbs": 190, "todayLog.weightLbs": 199 }).
--     PII-scrubbed client-side (no emails, phone numbers, tokens).
--
-- Triage view (`v_bug_reports_for_triage`) MUST project the new column so
-- the edge function can read it without extra roundtrips. Same
-- DROP-then-CREATE pattern 20260503 used.
--
-- RLS: bug_reports already has RLS; the new column inherits existing
-- policies. No policy changes.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS + DROP/CREATE VIEW.

BEGIN;

-- 1. New column on bug_reports ----------------------------------------
ALTER TABLE public.bug_reports
    ADD COLUMN IF NOT EXISTS state_snapshot JSONB
        NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.bug_reports.state_snapshot IS
'Phase 7 / Cheat Code — key-value map of ObservableObject singleton
 published state at the moment of shake. Keys are human service names
 (e.g. "WeightTrackingService"); values are redacted JSON with only
 scalar/short-array fields that reveal divergences. PII-scrubbed by
 BugReportSnapshotter.swift before insert.';

-- Tiny GIN index for ad-hoc CMS queries. Bounded — bug_reports is small
-- (shake-generated only) so index cost is negligible.
CREATE INDEX IF NOT EXISTS idx_bug_reports_state_snapshot_gin
    ON public.bug_reports USING GIN (state_snapshot jsonb_path_ops);

-- 2. Refresh triage view ----------------------------------------------
-- `CREATE OR REPLACE VIEW` can't add columns in Postgres when the
-- underlying column list changes. DROP then CREATE. Safe: view is
-- service-role-only and has no dependents (checked 2026-05-04).
DROP VIEW IF EXISTS public.v_bug_reports_for_triage;

CREATE VIEW public.v_bug_reports_for_triage
WITH (security_invoker = on) AS
SELECT
    id,
    user_id,
    user_name,
    user_email,
    description,
    expected_behavior,
    reproduces_every_time,
    additional_info,
    screenshot_base64,
    screen_name,
    likely_source_files,
    severity,
    bug_category,
    session_log,
    state_snapshot,                 -- NEW: Phase 7 cheat-code column
    device_model,
    os_version,
    app_version,
    triage_status,
    created_at
FROM public.bug_reports
WHERE triage_status IN ('pending', 'analyzing');

REVOKE ALL ON public.v_bug_reports_for_triage FROM PUBLIC, authenticated, anon;
GRANT  SELECT ON public.v_bug_reports_for_triage TO service_role;

COMMENT ON VIEW public.v_bug_reports_for_triage IS
'Phase 6 rage-shake view feeding supabase/functions/triage-shake-reports.
 v2.1 (2026-05-03): user_email for Claude user-lookup fallback.
 v3.0 (2026-05-04, Phase 7 Cheat Code): state_snapshot JSONB — runtime
 state at shake time, fed to Claude as a structured evidence block.
 Service-role only.';

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- SELECT column_name, data_type FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'bug_reports'
--    AND column_name = 'state_snapshot';
-- SELECT 1 FROM pg_views WHERE schemaname = 'public'
--   AND viewname = 'v_bug_reports_for_triage';
