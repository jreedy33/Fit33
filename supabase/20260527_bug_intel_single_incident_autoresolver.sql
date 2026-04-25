-- ============================================================================
-- Bug Intelligence — Single-Incident Transient Auto-Resolver (Phase 12 — Tier 1 #1)
-- Date: 2026-05-27 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- The 2026-04-25 export had 24 fingerprints. Of those, ~9 were single-occurrence
-- transients ("network connection lost during workout save", "request cancelled
-- mid-tab-switch") that nobody could ever fix because they're network weather,
-- not bugs. They sit in the bug-intel inbox indefinitely as `pending`, get
-- re-triaged every 4 hours by `triage-bugs` (cost: ~$0.04/run), and clutter
-- every export.
--
-- The existing auto-resolver (compute_daily_bug_rollup step 6i) only flips
-- fingerprints to resolved when:
--   - `fixed_in_build` is stamped (someone manually shipped a fix), AND
--   - `last_seen_at < now() - 5 days`, AND
--   - `regressed_after_fix = FALSE`.
-- That criterion never matches a single-occurrence transient because nobody
-- stamps `fixed_in_build` on "the user's wifi blipped".
--
-- FIX
-- ---
-- Add a second auto-resolve pass that runs nightly:
--   - error_class IN ('cancelled', 'offline', 'timeout', 'gateway', 'auth_expired'), AND
--   - occurrence_count = 1, AND
--   - unique_user_count = 1, AND
--   - last_seen_at < now() - 14 days, AND
--   - status NOT IN ('resolved', 'wont_fix', 'duplicate'), AND
--   - assigned_agent IS NULL OR assigned_agent = 'unassigned'  (i.e. nobody
--     has manually claimed it).
-- Flip to status='resolved' with auto_resolved_reason='transient_single_incident'.
--
-- Why 14 days: short enough to clear weekly review noise, long enough that a
-- recurring transient (cluster forming) won't get auto-resolved on day 2 of a
-- regression.
--
-- Why "single user": a single transient affecting two users is at minimum
-- a "third-party flake hit two of our users" — still resolvable, but worth
-- a human glance. Stays in the inbox.
--
-- The auto_resolved_reason='transient_single_incident' lets the CMS export
-- exclude these from the "Improvement Tracker" tab (per QP invariant 25k-bugintel)
-- so they don't pollute the silent-fix counter.
--
-- BACKWARD COMPAT
-- ---------------
-- Additive — no existing function is modified. Auto-resolved rows are still
-- queryable; the CMS list filter at `status NOT IN ('resolved', 'wont_fix')`
-- already hides them. To resurrect one for re-triage, an admin manually flips
-- status='pending' (existing UI affordance).
--
-- ROLLBACK
-- --------
--   DROP FUNCTION IF EXISTS bug_intel_resolve_single_incident_transients();
--   SELECT cron.unschedule('bug-intel-single-incident-autoresolve');
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. The auto-resolver function
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_resolve_single_incident_transients();

CREATE OR REPLACE FUNCTION bug_intel_resolve_single_incident_transients()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved_count INTEGER;
    v_started        TIMESTAMPTZ := now();
    v_classes_seen   TEXT[];
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_resolve_single_incident_transients is service-role only'
            USING ERRCODE = '42501';
    END IF;

    WITH targets AS (
        SELECT
            f.fingerprint,
            f.error_class,
            f.last_seen_at
        FROM bug_intelligence_fingerprints f
        WHERE f.error_class IN (
                'cancelled',
                'offline',
                'timeout',
                'gateway',
                'auth_expired'
            )
          AND f.occurrence_count  = 1
          AND f.unique_user_count = 1
          AND f.last_seen_at < (now() - INTERVAL '14 days')
          AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
          -- Don't auto-resolve fingerprints a human has actively claimed.
          -- `assigned_agent` is the canonical "claim" column from migration 63.
          AND (f.assigned_agent IS NULL OR f.assigned_agent = 'unassigned')
          -- Belt-and-suspenders: if a CMS reviewer has approved a fix in
          -- bug_intelligence_reports, leave the fingerprint open until the
          -- PR lands; don't pre-empt their workflow.
          AND NOT EXISTS (
              SELECT 1 FROM bug_intelligence_reports r
              WHERE r.fingerprint = f.fingerprint
                AND r.review_status IN ('approved', 'merged')
          )
    ),
    flipped AS (
        UPDATE bug_intelligence_fingerprints f
        SET
            status                = 'resolved',
            auto_resolved_at      = now(),
            auto_resolved_reason  = 'transient_single_incident',
            resolved_at           = COALESCE(f.resolved_at, now()),
            updated_at            = now()
        FROM targets t
        WHERE f.fingerprint = t.fingerprint
        RETURNING f.fingerprint, f.error_class
    )
    SELECT
        COUNT(*),
        ARRAY_AGG(DISTINCT error_class)
    INTO v_resolved_count, v_classes_seen
    FROM flipped;

    -- Audit trail on bug_intelligence_reports — leave a paper trail so the
    -- CMS markdown export can show "Auto-merged: transient_single_incident".
    -- NOTE: bug_intelligence_reports does NOT have an `updated_at` column
    -- (verified 2026-04-25 against the prod schema); only `reviewed_at` is
    -- updated here — `review_notes` carries the dated stamp.
    UPDATE bug_intelligence_reports r
    SET
        review_status = 'merged',
        review_notes  = COALESCE(r.review_notes || E'\n', '')
                        || format(
                            '[%s] Auto-merged: transient_single_incident (single occurrence, single user, silent ≥14 days, error_class in cancelled/offline/timeout/gateway/auth_expired)',
                            to_char(now(), 'YYYY-MM-DD HH24:MI UTC')
                           ),
        reviewed_at   = COALESCE(r.reviewed_at, now())
    FROM bug_intelligence_fingerprints f
    WHERE r.fingerprint = f.fingerprint
      AND f.auto_resolved_reason = 'transient_single_incident'
      AND f.auto_resolved_at >= v_started
      AND r.review_status NOT IN ('merged', 'rejected', 'stale');

    RAISE NOTICE 'bug_intel_resolve_single_incident_transients: resolved % fingerprints across classes %',
                 v_resolved_count, v_classes_seen;

    RETURN jsonb_build_object(
        'resolved_count',  v_resolved_count,
        'error_classes',   COALESCE(v_classes_seen, '{}'::TEXT[]),
        'started_at',      v_started,
        'completed_at',    now(),
        'duration_seconds', EXTRACT(EPOCH FROM (now() - v_started))
    );
END;
$$;

COMMENT ON FUNCTION bug_intel_resolve_single_incident_transients() IS
    'Phase 12 (Tier 1 #1, 2026-04-25): nightly auto-resolver for single-occurrence '
    'single-user transient errors that are silent ≥14 days. Drains the '
    '"weather not bug" backlog so reviewers see only actionable fingerprints. '
    'Auto-resolved with reason=transient_single_incident; CMS export filters by reason.';

REVOKE ALL ON FUNCTION bug_intel_resolve_single_incident_transients() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_resolve_single_incident_transients() TO service_role;

-- ----------------------------------------------------------------------------
-- 2. pg_cron schedule — nightly at 04:30 UTC, after rollup cleanup at 04:15
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-single-incident-autoresolve') THEN
            PERFORM cron.unschedule('bug-intel-single-incident-autoresolve');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-single-incident-autoresolve',
            '30 4 * * *',
            $cron$ SELECT bug_intel_resolve_single_incident_transients(); $cron$
        );
        RAISE NOTICE '[Phase 12 Tier 1 #1] scheduled bug-intel-single-incident-autoresolve (daily 04:30 UTC)';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Initial drain — run once now to clear the existing backlog
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT bug_intel_resolve_single_incident_transients() INTO v_result;
    RAISE NOTICE '[Phase 12 Tier 1 #1] initial drain: %', v_result;
END $$;

COMMIT;
