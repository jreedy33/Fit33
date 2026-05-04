-- ============================================================================
-- Bug Intelligence Phase 14 — Build-Aged-Out Auto-Resolver
-- Date: 2026-05-04
-- Pairs with: BUG_INTELLIGENCE_AGENT.md invariant 15 (auto_resolved_reason
--             taxonomy — adds `silent_fix:build_aged_out:<src>:<live>`)
--
-- PROBLEM
-- -------
-- The 2026-05-04 inbox drain audit found that ~30 of 244 fingerprints were
-- last seen on builds the user base no longer runs (build 27 / 41 / 45 /
-- 46 — minimum live cohort is build 63+). These are by definition
-- silent-fixed: whatever code path triggered them has shipped and the FP
-- has not recurred. They sit forever in the inbox because:
--
--   1. The single-incident transient resolver only fires for
--      `error_class IN ('cancelled','offline','timeout','gateway','auth_expired')`.
--      A `pg:23514` constraint violation from build 41 doesn't qualify.
--
--   2. The Phase-13 root-cause collapse only fires when the FP's
--      `root_cause_fingerprint` matches a row in `bug_intel_resolved_history`.
--      No twin → no collapse.
--
--   3. The compute_daily_bug_rollup step 6i auto-resolve gate is
--      "fixed_in_build IS NOT NULL AND last_seen_at > 5d AND
--       NOT regressed_after_fix". `fixed_in_build` is an opt-in stamp that
--      almost no migration sets, so this gate almost never fires.
--
-- FIX
-- ---
-- Add a third nightly auto-resolver pass — the "build-aged-out" drain —
-- that runs at 04:45 UTC (after #93 single-incident at 04:30 and before
-- #94 severity recompute at 05:00) and applies the canonical heuristic:
-- a FP is build-aged-out if it has not appeared on any build less than
-- (live_max_build - p_build_cushion) AND has been silent for at least
-- p_min_silent_days. The cushion + silence requirement together prevent
-- premature drainage of a FP that's still live on a slow-updating cohort.
--
-- WHY 5-build cushion + 7-day silence (defaults):
--   * 5 builds: TestFlight typically ships every 2-3 days, App Store every
--     1-2 weeks. 5 builds back ≈ 1-3 weeks behind the live release train —
--     long enough that a non-pinned cohort has rotated through.
--   * 7 days: matches the existing rollup auto-resolve "silent ≥ 5 days"
--     threshold but adds 2 days to compensate for build-cohort skew (a
--     user might be on stale build N-6 but still active; 7 days lets us
--     observe whether they hit the bug AGAIN on their stale build before
--     drainage).
--
-- Both thresholds are RPC parameters so the cron can pass tighter values
-- during a backlog drain (e.g. `p_build_cushion := 3, p_min_silent_days := 3`)
-- and looser values during stable periods.
--
-- The `live_max_build` is computed dynamically per-run from crash_reports
-- last 3 days (small enough to track release-train motion, large enough
-- to survive a quiet weekend). If no crash_reports rows exist (cold prod /
-- never instrumented), the function no-ops with a clear NOTICE so we
-- never accidentally drain everything.
--
-- BACKWARD COMPAT
-- ---------------
-- Additive — does not modify any existing function. Auto-resolved rows
-- are still queryable. The CMS export filter at
-- `auto_resolved_reason NOT IN (...)` excludes the new reason.
--
-- ROLLBACK
-- --------
--   DROP FUNCTION IF EXISTS bug_intel_resolve_build_aged_out(INT, INT);
--   SELECT cron.unschedule('bug-intel-build-aged-out-autoresolve');
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. The auto-resolver function
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.bug_intel_resolve_build_aged_out(INT, INT);

CREATE OR REPLACE FUNCTION public.bug_intel_resolve_build_aged_out(
    p_build_cushion    INT DEFAULT 5,
    p_min_silent_days  INT DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_live_max_build INT;
    v_threshold      INT;
    v_resolved_count INTEGER := 0;
    v_started        TIMESTAMPTZ := now();
    v_classes_seen   TEXT[];
    v_min_drained    INT;
    v_max_drained    INT;
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_resolve_build_aged_out is service-role only'
            USING ERRCODE = '42501';
    END IF;

    IF p_build_cushion < 1 OR p_min_silent_days < 1 THEN
        RAISE EXCEPTION 'bug_intel_resolve_build_aged_out: cushion=% silent_days=% — both must be >= 1',
                        p_build_cushion, p_min_silent_days
            USING ERRCODE = '22023';
    END IF;

    -- Discover the current "live" build cohort. We treat "live" as the MAX
    -- build_number observed in crash_reports created in the last 3 days.
    -- 3 days is small enough to track release-train motion (TestFlight
    -- pushes every 2-3 days) but large enough to survive a quiet weekend.
    -- If no crash_reports rows exist (cold prod / instrumentation gap),
    -- bail out — never auto-resolve in the absence of a known live cohort.
    -- `crash_reports.build_number` is TEXT (20260427); cast for numeric MAX
    -- so "67" beats "9" (lexicographic MAX would be wrong).
    SELECT MAX((build_number)::INT)
      INTO v_live_max_build
      FROM crash_reports
     WHERE build_number IS NOT NULL
       AND build_number ~ '^[0-9]+$'
       AND created_at >= now() - INTERVAL '3 days';

    IF v_live_max_build IS NULL THEN
        RAISE NOTICE 'bug_intel_resolve_build_aged_out: no live cohort observed in crash_reports — skipping (cold prod / instrumentation gap)';
        RETURN jsonb_build_object(
            'resolved_count',     0,
            'live_max_build',     NULL,
            'threshold',          NULL,
            'reason',             'no_live_cohort_observed',
            'started_at',         v_started,
            'completed_at',       now()
        );
    END IF;

    v_threshold := v_live_max_build - p_build_cushion;

    -- Resolve every open FP whose `last_seen_build` is non-null AND
    -- strictly below the threshold AND has been silent ≥ p_min_silent_days.
    -- Stamp the dynamic reason so the audit trail captures both the
    -- aged-out cohort and the live cohort at drain time.
    --
    -- The unassigned/no-approved-report guards mirror the single-incident
    -- resolver — never preempt a human review in flight.
    -- `bug_intelligence_fingerprints.last_seen_build` is TEXT (20260427).
    -- Only compare rows that are pure digits; skip non-numeric garbage.
    WITH targets AS (
        SELECT
            f.fingerprint,
            f.error_class,
            f.last_seen_build
        FROM bug_intelligence_fingerprints f
        WHERE f.last_seen_build IS NOT NULL
          AND f.last_seen_build ~ '^[0-9]+$'
          AND (f.last_seen_build)::INT < v_threshold
          AND f.last_seen_at < (now() - make_interval(days => p_min_silent_days))
          AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
          AND (f.assigned_agent IS NULL OR f.assigned_agent = 'unassigned')
          AND NOT EXISTS (
              SELECT 1 FROM bug_intelligence_reports r
              WHERE r.fingerprint = f.fingerprint
                AND r.review_status IN ('approved', 'merged')
          )
    ),
    flipped AS (
        UPDATE bug_intelligence_fingerprints f
           SET status               = 'resolved',
               auto_resolved_at     = COALESCE(auto_resolved_at, now()),
               auto_resolved_reason = format(
                   'silent_fix:build_aged_out:%s:%s',
                   t.last_seen_build,
                   v_live_max_build
               ),
               resolved_at          = COALESCE(f.resolved_at, now()),
               updated_at           = now()
          FROM targets t
         WHERE f.fingerprint = t.fingerprint
        RETURNING f.fingerprint, f.error_class, t.last_seen_build
    )
    SELECT
        COUNT(*),
        ARRAY_AGG(DISTINCT error_class),
        MIN((last_seen_build)::INT),
        MAX((last_seen_build)::INT)
      INTO v_resolved_count, v_classes_seen, v_min_drained, v_max_drained
      FROM flipped;

    -- Audit trail on bug_intelligence_reports — leave a paper trail for
    -- the CMS markdown export. Same pattern as the single-incident
    -- resolver: review_status='merged' + dated note. `bug_intelligence_reports`
    -- has no `updated_at` column, only `reviewed_at` (verified 2026-04-25
    -- against prod schema).
    UPDATE bug_intelligence_reports r
       SET review_status = 'merged',
           review_notes  = COALESCE(review_notes || E'\n', '')
                           || format(
                                '[%s] Auto-merged: silent_fix:build_aged_out — last_seen_build=%s, live_max_build=%s, threshold=%s, silent ≥%s days, no human claim.',
                                to_char(now(), 'YYYY-MM-DD HH24:MI UTC'),
                                f.last_seen_build,
                                v_live_max_build,
                                v_threshold,
                                p_min_silent_days
                              ),
           reviewed_at   = COALESCE(reviewed_at, now())
      FROM bug_intelligence_fingerprints f
     WHERE r.fingerprint = f.fingerprint
       AND f.auto_resolved_reason LIKE 'silent_fix:build_aged_out:%'
       AND f.auto_resolved_at >= v_started
       AND r.review_status NOT IN ('merged', 'rejected', 'stale');

    RAISE NOTICE 'bug_intel_resolve_build_aged_out: live_max_build=% threshold=% drained=% (build range %..%), classes=%',
                 v_live_max_build, v_threshold, v_resolved_count,
                 COALESCE(v_min_drained, -1), COALESCE(v_max_drained, -1),
                 COALESCE(v_classes_seen, '{}'::TEXT[]);

    RETURN jsonb_build_object(
        'resolved_count',     v_resolved_count,
        'live_max_build',     v_live_max_build,
        'threshold',          v_threshold,
        'cushion',            p_build_cushion,
        'min_silent_days',    p_min_silent_days,
        'min_drained_build',  v_min_drained,
        'max_drained_build',  v_max_drained,
        'error_classes',      COALESCE(v_classes_seen, '{}'::TEXT[]),
        'started_at',         v_started,
        'completed_at',       now(),
        'duration_seconds',   EXTRACT(EPOCH FROM (now() - v_started))
    );
END;
$$;

COMMENT ON FUNCTION public.bug_intel_resolve_build_aged_out(INT, INT) IS
    'Phase 14 (2026-05-04): nightly auto-resolver for fingerprints whose '
    '`last_seen_build` is more than `p_build_cushion` builds behind the '
    'currently-live cohort AND has been silent ≥ `p_min_silent_days`. '
    'Drains the build-aged backlog without touching FPs that are still '
    'firing on slow-updating user cohorts. live_max_build computed '
    'dynamically per-run from crash_reports last 3 days. Idempotent.';

REVOKE ALL ON FUNCTION public.bug_intel_resolve_build_aged_out(INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bug_intel_resolve_build_aged_out(INT, INT) TO service_role;

-- ----------------------------------------------------------------------------
-- 2. pg_cron schedule — nightly at 04:45 UTC
--    Order in the night:
--      00:45  Phase 13 root-cause collapse           (#94)
--      04:30  Phase 12 single-incident transients    (#93)
--      04:45  Phase 14 build-aged-out                (this migration)
--      05:00  Phase 12 severity recompute            (downstream of all 3)
--    All three drain passes feed into the 05:00 severity recompute, so
--    drained FPs don't waste compute in the score calculation.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-build-aged-out-autoresolve') THEN
            PERFORM cron.unschedule('bug-intel-build-aged-out-autoresolve');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-build-aged-out-autoresolve',
            '45 4 * * *',
            $cron$ SELECT public.bug_intel_resolve_build_aged_out(); $cron$
        );
        RAISE NOTICE '[Phase 14] scheduled bug-intel-build-aged-out-autoresolve (daily 04:45 UTC, defaults: cushion=5 silent_days=7)';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Initial drain — run once now to clear the existing backlog.
--    Pre-deploy audit (2026-05-04): live_max_build=67, threshold=62,
--    expect to drain ~17 FPs (last_seen_build IN (41, 54, 58, 59, 60)).
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT public.bug_intel_resolve_build_aged_out() INTO v_result;
    RAISE NOTICE '[Phase 14] initial drain: %', v_result;
END $$;

-- ----------------------------------------------------------------------------
-- 4. Companion view: v_bug_intel_classifier_coverage
--    Surfaces error_class values that have OPEN fingerprints but NO
--    corresponding noise_filter row (a proxy for "does the iOS classifier
--    handle this class?"). Driver for the next sprint's CMS panel.
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS public.v_bug_intel_classifier_coverage;

CREATE VIEW public.v_bug_intel_classifier_coverage
WITH (security_invoker = on)
AS
WITH open_classes AS (
    SELECT
        COALESCE(error_class, 'unknown') AS error_class,
        COUNT(*)                          AS open_fp_count,
        SUM(occurrence_count)             AS total_occurrences,
        SUM(unique_user_count)            AS total_unique_users,
        ARRAY_AGG(DISTINCT pg_code) FILTER (WHERE pg_code IS NOT NULL)
                                          AS pg_codes_seen,
        MAX(last_seen_at)                 AS most_recent
    FROM bug_intelligence_fingerprints
    WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate')
    GROUP BY 1
),
filter_coverage AS (
    SELECT
        f.error_class,
        f.open_fp_count,
        f.total_occurrences,
        f.total_unique_users,
        f.pg_codes_seen,
        f.most_recent,
        EXISTS (
            SELECT 1 FROM bug_intel_noise_filter nf
             WHERE nf.pg_code IS NOT NULL
               AND f.pg_codes_seen IS NOT NULL
               AND nf.pg_code = ANY(f.pg_codes_seen)
        ) AS has_pg_filter,
        EXISTS (
            SELECT 1 FROM bug_intel_noise_filter nf
             WHERE nf.message_pattern IS NOT NULL
        ) AS has_any_message_filter
    FROM open_classes f
)
SELECT
    error_class,
    open_fp_count,
    total_occurrences,
    total_unique_users,
    pg_codes_seen,
    most_recent,
    has_pg_filter,
    -- Suggestion: if there are >= 3 open FPs in this class with no pg_code
    -- filter, propose adding one. Operators read this column in the CMS.
    CASE
        WHEN open_fp_count >= 3 AND NOT has_pg_filter
             AND error_class LIKE 'pg:%'
            THEN 'PROPOSE: add bug_intel_noise_filter row for this pg_code'
        WHEN open_fp_count >= 5 AND error_class = 'unknown'
            THEN 'PROPOSE: classify these FPs (error_class = unknown)'
        ELSE NULL
    END AS coverage_action
  FROM filter_coverage
 ORDER BY open_fp_count DESC, total_occurrences DESC;

COMMENT ON VIEW public.v_bug_intel_classifier_coverage IS
    'Phase 14: surfaces error_class values with open fingerprints + whether '
    'a corresponding bug_intel_noise_filter row exists. Drives the CMS '
    'classifier-coverage audit panel + the operator-readable PROPOSE '
    'suggestions in `coverage_action`.';

GRANT SELECT ON public.v_bug_intel_classifier_coverage TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Audit: post-drain row count snapshot
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_open_after  INT;
    v_drained_today INT;
BEGIN
    SELECT COUNT(*) INTO v_open_after
      FROM bug_intelligence_fingerprints
     WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

    SELECT COUNT(*) INTO v_drained_today
      FROM bug_intelligence_fingerprints
     WHERE auto_resolved_reason LIKE 'silent_fix:build_aged_out:%'
       AND auto_resolved_at >= now() - INTERVAL '1 hour';

    RAISE NOTICE '[Phase 14] post-deploy: open=% build_aged_out_drained_this_run=%',
                 v_open_after, v_drained_today;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
