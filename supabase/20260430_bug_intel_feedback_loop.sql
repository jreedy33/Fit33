-- ============================================================================
-- Bug Intelligence Pipeline (Phase 4): Knowledge Feedback Loop
-- Date: 2026-04-30
-- Sprint 8 (Q2-97)
--
-- PURPOSE
-- -------
-- Phases 1-3 produce fingerprints → Claude reports → PRs. This phase closes
-- the cycle by listening to GitHub `pull_request.closed` webhook events and
-- auto-updating the DB lifecycle when a BugIntel PR merges. That feeds:
--
--   * `bug_intelligence_reports.review_status` → `merged`
--   * `bug_intelligence_fingerprints.status`   → `resolved`
--   * `bug_intelligence_fingerprints.resolution_pr_url`
--   * Agent leaderboard view `v_bug_intelligence_metrics`
--
-- Adds columns + view only — no new tables. Keeps the schema small.
--
-- ARCHITECTURE
-- ------------
--   GitHub PR merged
--     ↓ (webhook HMAC-signed)
--   supabase/functions/github-pr-webhook/index.ts
--     ↓ regex-extract Report-Id + Fingerprint from PR body
--     ↓ 1 UPDATE per row (report + fingerprint)
--   Admin CMS /bug-intelligence
--     ↓ queries v_bug_intelligence_metrics for leaderboard
--
-- ROLLBACK
--   DROP VIEW IF EXISTS v_bug_intelligence_metrics;
--   ALTER TABLE bug_intelligence_reports
--     DROP COLUMN IF EXISTS github_pr_number,
--     DROP COLUMN IF EXISTS github_pr_merged_at,
--     DROP COLUMN IF EXISTS feedback_applied_at,
--     DROP COLUMN IF EXISTS docs_commit_sha;
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Lifecycle columns on bug_intelligence_reports
-- ============================================================================

ALTER TABLE bug_intelligence_reports
  ADD COLUMN IF NOT EXISTS github_pr_number INTEGER,
  ADD COLUMN IF NOT EXISTS github_pr_merged_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS feedback_applied_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS docs_commit_sha TEXT;

CREATE INDEX IF NOT EXISTS idx_bug_reports_pr_number
  ON bug_intelligence_reports(github_pr_number)
  WHERE github_pr_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bug_reports_merged_at
  ON bug_intelligence_reports(github_pr_merged_at DESC)
  WHERE github_pr_merged_at IS NOT NULL;

COMMENT ON COLUMN bug_intelligence_reports.github_pr_number IS
  'PR number populated by github-pr-webhook when a BugIntel PR merges.';
COMMENT ON COLUMN bug_intelligence_reports.github_pr_merged_at IS
  'When the PR merged (UTC). Used for time-to-fix metrics.';
COMMENT ON COLUMN bug_intelligence_reports.feedback_applied_at IS
  'When the webhook finished updating this report + its fingerprint. Reserved for Phase 4.1 docs auto-commit.';
COMMENT ON COLUMN bug_intelligence_reports.docs_commit_sha IS
  'Reserved: SHA of docs/history/BUG_INTEL_FIXES.md auto-commit (Phase 4.1).';

-- ============================================================================
-- 2. Metrics view — agent leaderboard + resolution stats (last 30 days)
--    security_invoker = on per supabase-rules.mdc invariant.
-- ============================================================================

CREATE OR REPLACE VIEW v_bug_intelligence_metrics
WITH (security_invoker = on)
AS
WITH base AS (
    SELECT
        r.id,
        r.fingerprint,
        r.agent_owner,
        r.severity,
        r.confidence,
        r.review_status,
        r.created_at            AS report_created_at,
        r.github_pr_merged_at,
        f.first_seen_at,
        f.last_seen_at,
        f.status                AS fingerprint_status,
        f.occurrence_count,
        f.unique_user_count
    FROM bug_intelligence_reports r
    JOIN bug_intelligence_fingerprints f USING (fingerprint)
    WHERE r.created_at >= NOW() - INTERVAL '30 days'
)
SELECT
    agent_owner,

    COUNT(*)::INT                                        AS reports_total,
    COUNT(DISTINCT fingerprint)::INT                     AS unique_fingerprints,

    COUNT(*) FILTER (WHERE review_status = 'pending')::INT   AS reports_pending,
    COUNT(*) FILTER (WHERE review_status = 'approved')::INT  AS reports_approved,
    COUNT(*) FILTER (WHERE review_status = 'rejected')::INT  AS reports_rejected,
    COUNT(*) FILTER (WHERE review_status = 'merged')::INT    AS reports_merged,

    COUNT(*) FILTER (WHERE severity = 'critical')::INT   AS reports_critical,
    COUNT(*) FILTER (WHERE severity = 'high')::INT       AS reports_high,

    ROUND(AVG(confidence)::NUMERIC, 2)                   AS avg_confidence,

    -- Fix rate = merged / (merged + rejected + approved)  (excludes pending)
    CASE WHEN COUNT(*) FILTER (WHERE review_status IN ('merged','rejected','approved')) > 0 THEN
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE review_status = 'merged')
            / NULLIF(COUNT(*) FILTER (WHERE review_status IN ('merged','rejected','approved')), 0),
            1
        )
    ELSE NULL END                                        AS fix_rate_pct,

    -- Median time-to-fix in hours (first report → PR merged)
    ROUND(
        EXTRACT(EPOCH FROM PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY (github_pr_merged_at - first_seen_at)
        )) / 3600.0,
        1
    )                                                    AS median_time_to_fix_hours,

    SUM(occurrence_count)::BIGINT                        AS total_occurrences_affected,
    SUM(unique_user_count)::BIGINT                       AS total_users_affected
FROM base
GROUP BY agent_owner
ORDER BY reports_merged DESC, reports_total DESC;

COMMENT ON VIEW v_bug_intelligence_metrics IS
  'Per-agent bug leaderboard (last 30 days). Merged counts + fix rate + median time-to-fix.';

-- ============================================================================
-- 3. Sanity notice
-- ============================================================================

DO $$ BEGIN
    RAISE NOTICE '✅ bug_intelligence_reports lifecycle columns added';
    RAISE NOTICE '   Next: deploy supabase/functions/github-pr-webhook + register webhook on jreedy33/Fit33';
END $$;

COMMIT;
