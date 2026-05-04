-- ============================================================================
-- Bug Intelligence Phase 14b — Structural-Fingerprint Twin Collapse
-- Date: 2026-05-04
-- Pairs with: 20260714_bug_intel_phase13_collapse_and_classify.sql (which
--             added `bug_intel_resolve_by_root_cause()` matching by
--             `root_cause_fingerprint`)
--
-- PROBLEM
-- -------
-- The Phase-13 collapser fires only when an open FP's
-- `root_cause_fingerprint` matches a row in `bug_intel_resolved_history`.
-- That key is `md5(op || '|' || error_class)` — useful when both the iOS
-- callsite (op) and the error class are stable.
--
-- It MISSES the case where the same underlying bug surfaces from two
-- different ops but produces an identical message shape. Today's example:
-- the daily-quest 23505 cluster fingerprinted as 4 distinct FPs because
-- the iOS callsite (`fetchDailyQuests` for crash source vs.
-- `dailyquests.fetch.error_details` for log source) and the message
-- prefix differ, even though the root cause (the unique-key violation
-- inside `get_daily_quests`) is identical. The `structural_fingerprint`
-- column captures that — it's computed from the normalized message body,
-- so message-body-equivalent FPs share it regardless of op.
--
-- FIX
-- ---
-- Add a second nightly auto-resolver — `bug_intel_resolve_by_structural_fp()` —
-- that fires AFTER the root-cause collapser and applies the same logic
-- but joins on `structural_fingerprint` instead. Stamps the canonical
-- reason `silent_fix:matched_root_cause:<source_fp>` (same as Phase 13)
-- so downstream tooling treats them identically.
--
-- ORDER OF OPERATIONS (per night):
--   00:30 compute_daily_bug_rollup (writes new fingerprints)
--   00:45 bug_intel_resolve_by_root_cause          (Phase 13)
--   00:50 bug_intel_resolve_by_structural_fp       (this migration — runs
--         AFTER Phase 13 so a FP collapsed via root_cause doesn't get
--         re-stamped via structural)
--   04:30 bug_intel_resolve_single_incident_transients
--   04:45 bug_intel_resolve_build_aged_out         (Phase 14a)
--
-- WHY EXCLUDE NOISE_FILTER_EXPANDED + TRANSIENT_SINGLE_INCIDENT FROM THE
-- SOURCE SET: same as Phase 13 — those are noise drains, not "we shipped a
-- fix". Stamping a NEW open FP as "matched_root_cause: <noise drain hash>"
-- would obscure the true history.
--
-- BACKWARD COMPAT
-- ---------------
-- Additive — no existing function modified. `bug_intel_resolved_history`
-- is read-only here (history is appended by the rollup's resolved-row
-- archiver). Idempotent — re-running is a no-op once all eligible twins
-- are collapsed.
--
-- ROLLBACK
-- --------
--   DROP FUNCTION IF EXISTS public.bug_intel_resolve_by_structural_fp();
--   SELECT cron.unschedule('bug-intel-resolve-by-structural-fp');
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.bug_intel_resolve_by_structural_fp();

CREATE OR REPLACE FUNCTION public.bug_intel_resolve_by_structural_fp()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved INTEGER := 0;
    v_started  TIMESTAMPTZ := now();
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_resolve_by_structural_fp is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- Find every open fingerprint whose `structural_fingerprint` matches
    -- ANY past resolution that wasn't itself a noise-drain (same exclusion
    -- list as Phase 13). The structural_fingerprint is the message-shape
    -- key: open FP X collapses against past-resolved FP Y when
    --   X.structural_fingerprint = Y.structural_fingerprint
    --   AND Y was resolved with a non-noise reason
    --   AND X.root_cause_fingerprint did NOT already collapse via Phase 13
    --       (we exclude FPs already stamped silent_fix:matched_root_cause:
    --        to avoid re-stamping)
    WITH matchable AS (
        SELECT DISTINCT
            f.fingerprint,
            (
                SELECT h.fingerprint
                  FROM bug_intel_resolved_history h
                 WHERE h.structural_fingerprint = f.structural_fingerprint
                   AND h.structural_fingerprint IS NOT NULL
                   AND COALESCE(h.auto_resolved_reason, '') NOT IN (
                       'transient_single_incident',
                       'noise_filter_expanded',
                       'triaged_stale'
                   )
                   AND COALESCE(h.auto_resolved_reason, '') NOT LIKE 'silent_fix:build_aged_out:%'
                 ORDER BY h.resolved_at DESC
                 LIMIT 1
            ) AS source_resolution_fp
          FROM bug_intelligence_fingerprints f
         WHERE f.structural_fingerprint IS NOT NULL
           AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
           -- Don't preempt a human review in flight.
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
               auto_resolved_reason = 'silent_fix:matched_root_cause:' ||
                                      COALESCE(m.source_resolution_fp, 'unknown'),
               resolved_at          = COALESCE(resolved_at, now()),
               updated_at           = now()
          FROM matchable m
         WHERE f.fingerprint = m.fingerprint
           AND m.source_resolution_fp IS NOT NULL
        RETURNING f.fingerprint
    )
    SELECT COUNT(*) INTO v_resolved FROM flipped;

    -- Paired reports → merged with audit note.
    UPDATE bug_intelligence_reports r
       SET review_status = 'merged',
           review_notes  = COALESCE(review_notes || E'\n', '') ||
                           format(
                               '[%s] Auto-merged: matched structural_fingerprint of an already-resolved fingerprint. Phase 14b structural-twin drain.',
                               to_char(now(), 'YYYY-MM-DD HH24:MI UTC')
                           ),
           reviewed_at   = COALESCE(reviewed_at, now())
      FROM bug_intelligence_fingerprints f
     WHERE r.fingerprint = f.fingerprint
       AND f.auto_resolved_reason LIKE 'silent_fix:matched_root_cause:%'
       AND f.auto_resolved_at >= v_started
       AND r.review_status NOT IN ('merged', 'rejected', 'stale');

    RAISE NOTICE 'bug_intel_resolve_by_structural_fp: collapsed % structural-twin fingerprints',
                 v_resolved;

    RETURN jsonb_build_object(
        'resolved_count',   v_resolved,
        'started_at',       v_started,
        'completed_at',     now(),
        'duration_seconds', EXTRACT(EPOCH FROM (now() - v_started))
    );
END;
$$;

COMMENT ON FUNCTION public.bug_intel_resolve_by_structural_fp() IS
    'Phase 14b (2026-05-04): nightly auto-drain at 00:50 UTC. Open '
    'fingerprints whose `structural_fingerprint` matches a row in '
    '`bug_intel_resolved_history` (excluding noise-drains) flip to '
    'status=resolved with reason=silent_fix:matched_root_cause:<source_fp>. '
    'Catches message-shape twins that Phase 13 misses because the iOS op '
    'differs (e.g. crash source vs log source of the same underlying bug).';

REVOKE ALL ON FUNCTION public.bug_intel_resolve_by_structural_fp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bug_intel_resolve_by_structural_fp() TO service_role;

-- ----------------------------------------------------------------------------
-- Schedule nightly at 00:50 UTC — 5 minutes after Phase-13 root-cause
-- collapse so any FP that already drained via root_cause doesn't get
-- re-stamped here.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-resolve-by-structural-fp') THEN
            PERFORM cron.unschedule('bug-intel-resolve-by-structural-fp');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-resolve-by-structural-fp',
            '50 0 * * *',
            $cron$ SELECT public.bug_intel_resolve_by_structural_fp(); $cron$
        );
        RAISE NOTICE '[Phase 14b] scheduled bug-intel-resolve-by-structural-fp (daily 00:50 UTC)';
    END IF;
END $$;

-- Initial drain — surface what's collapsed today against existing history.
DO $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT public.bug_intel_resolve_by_structural_fp() INTO v_result;
    RAISE NOTICE '[Phase 14b] initial drain: %', v_result;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
