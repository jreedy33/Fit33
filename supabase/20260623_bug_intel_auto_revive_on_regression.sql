-- ════════════════════════════════════════════════════════════════════
-- Migration #123 — Auto-revive resolved fingerprints when their fix
-- doesn't actually hold. Phase 13 close-the-loop.
-- 2026-04-26
--
-- PROBLEM
-- -------
-- Phase 9's `compute_daily_bug_rollup` has a regression-revival path
-- driven by `fixed_in_build`: when `last_seen_build > fixed_in_build`,
-- it flips `regressed_after_fix=TRUE`. That works when an admin
-- manually stamps `fixed_in_build` from the CMS triage panel.
--
-- Phase 12-Tier-2 + Phase 13 added a SECOND resolution path —
-- `mark_fingerprints_resolved_by_migration` / the `Resolves:` directive
-- convention — which sets `latest_resolving_migration_at` instead of
-- `fixed_in_build`. There is currently NO regression-revival path for
-- this newer track. If a server-side migration ships, the fingerprint
-- flips to `resolved`, and then the bug recurs on the same client
-- build (or a newer one), the row stays `resolved` forever and the
-- dashboard silently hides it.
--
-- That breaks the user's expectation: "resolved disappears, but
-- reappears if it's a regression or wasn't actually fixed."
--
-- FIX
-- ---
-- New SECURITY DEFINER cron `bug_intel_revive_regressed_fingerprints()`
-- that scans every fingerprint where:
--   • status = 'resolved'
--   • auto_resolved_reason starts with 'migration_resolved:' OR
--                                       'code_fix:'           OR
--                                       'silent_fix'          OR
--                                       'transient_single_incident'
--     (i.e. it was auto-resolved by the pipeline, NOT by a human admin
--     who clicked Resolve in the CMS — those stay sticky)
--   • last_seen_at > GREATEST(resolved_at, latest_resolving_migration_at)
--                    + 48h grace window
-- and flips:
--   • status = 'new'
--   • regressed_after_fix = TRUE
--   • auto_resolved_at = NULL  (clears the auto-resolve marker so it
--                                doesn't immediately re-resolve)
--   • emits a `bug_intelligence_trends` row with type='regression_after_fix'
--   • appends an audit line to a representative `bug_intelligence_reports`
--     row's review_notes so admins see "Reopened: post-fix activity at
--     <ts>"
--
-- The 48h grace mirrors the export-side stale-fix filter from #114
-- (`STALE_FIX_GRACE_MS = 48h`) so the dashboard, the export, and the
-- revival cron all agree on the same cutoff. If you tune it, change
-- both places in lock-step.
--
-- Why exclude human-resolved rows? When a human flicks Resolve in the
-- CMS (`status='resolved'` without an `auto_resolved_reason`), they
-- have made a judgement call — duplicate, intended behaviour, etc.
-- We don't want a cron to undo that. Only PIPELINE-resolved rows are
-- candidates for revival.
--
-- SCHEDULING
-- ----------
-- pg_cron at `:20 past every hour`. Runs after `compute_daily_bug_rollup`
-- (which runs at `:00 past`) so the revival sees the freshest
-- `last_seen_at` values. Staggered with `bug_intel_recompute_severity`
-- (`:10`) and `bug_intel_resolve_single_incident_transients` (04:30).
--
-- BACKWARD COMPAT
-- ---------------
-- Pure-additive: new RPC + new cron schedule. No existing function or
-- column is modified. The `regressed_after_fix` column already exists
-- (#86 / #91) and `bug_intelligence_trends` already supports the
-- `regression_after_fix` trend_type.
--
-- ROLLBACK
-- --------
--   SELECT cron.unschedule('bug-intel-revive-regressed-fingerprints');
--   DROP FUNCTION IF EXISTS bug_intel_revive_regressed_fingerprints(INT);
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. RPC: bug_intel_revive_regressed_fingerprints(p_grace_hours INT DEFAULT 48)
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_revive_regressed_fingerprints(INT);

CREATE OR REPLACE FUNCTION bug_intel_revive_regressed_fingerprints(
  p_grace_hours INT DEFAULT 48
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_revived_count INT := 0;
  v_trends_emitted INT := 0;
  v_grace INTERVAL;
BEGIN
  IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'bug_intel_revive_regressed_fingerprints is service-role only'
      USING ERRCODE = '42501';
  END IF;

  IF p_grace_hours IS NULL OR p_grace_hours < 0 OR p_grace_hours > 168 THEN
    RAISE EXCEPTION 'p_grace_hours must be between 0 and 168 (got %)', p_grace_hours;
  END IF;

  v_grace := MAKE_INTERVAL(hours => p_grace_hours);

  -- Step 1: revive eligible fingerprints. Only PIPELINE-resolved rows
  -- (auto_resolved_reason set) — never override a human's manual
  -- Resolve in the CMS (auto_resolved_reason IS NULL means human did it).
  WITH revived AS (
    UPDATE bug_intelligence_fingerprints f
    SET
      status               = 'new',
      regressed_after_fix  = TRUE,
      -- Clear auto_resolved_at so the rollup doesn't immediately
      -- re-resolve via the silent+fixed path. resolved_at is preserved
      -- as historical record (when did the FIRST resolve happen).
      auto_resolved_at     = NULL,
      updated_at           = now()
    WHERE f.status = 'resolved'
      AND f.auto_resolved_reason IS NOT NULL
      -- Only pipeline-resolutions are eligible for auto-revival.
      AND (
        f.auto_resolved_reason LIKE 'migration_resolved:%'
        OR f.auto_resolved_reason LIKE 'code_fix%'
        OR f.auto_resolved_reason = 'silent_fix'
        OR f.auto_resolved_reason = 'transient_single_incident'
        OR f.auto_resolved_reason = 'noise_filter_expanded'
      )
      -- Fresh activity past the grace window.
      AND f.last_seen_at IS NOT NULL
      AND f.last_seen_at > (
        GREATEST(
          COALESCE(f.latest_resolving_migration_at, f.resolved_at, f.auto_resolved_at, 'epoch'::timestamptz),
          COALESCE(f.resolved_at, 'epoch'::timestamptz)
        ) + v_grace
      )
    RETURNING f.fingerprint, f.last_seen_at, f.last_seen_app_version, f.last_seen_build,
              f.occurrence_count, f.unique_user_count
  )
  SELECT COUNT(*) INTO v_revived_count FROM revived;

  -- Step 2: emit a trend row per revived fingerprint so the CMS
  -- "Trends (24h)" widget shows the regression. Idempotent — skip if
  -- a regression_after_fix trend was already emitted today.
  --
  -- NOTE: schema (`supabase/20260427_bug_intelligence.sql` lines 198–211)
  -- exposes `today_count` / `affected_users` / `sample_window` / `notes`
  -- — NOT `occurrence_count` / `unique_user_count` / `window` / `summary`.
  -- `window` is also a reserved word and would parse-error if used unquoted.
  WITH today_trends AS (
    INSERT INTO bug_intelligence_trends (
      fingerprint, trend_type, detected_at, today_count, affected_users, sample_window, notes
    )
    SELECT
      f.fingerprint,
      'regression_after_fix'::TEXT,
      now(),
      f.occurrence_count,
      f.unique_user_count,
      'revival',
      format(
        'Reopened: pipeline-resolved (%s) saw fresh activity at %s on %s (%s) past %sh grace.',
        f.auto_resolved_reason,
        to_char(f.last_seen_at, 'YYYY-MM-DD HH24:MI UTC'),
        COALESCE(f.last_seen_app_version, '?'),
        COALESCE(f.last_seen_build, '?'),
        p_grace_hours
      )
    FROM bug_intelligence_fingerprints f
    WHERE f.status = 'new'
      AND f.regressed_after_fix = TRUE
      AND f.updated_at >= now() - INTERVAL '5 minutes'  -- only the rows we JUST revived
      AND NOT EXISTS (
        SELECT 1 FROM bug_intelligence_trends t
        WHERE t.fingerprint = f.fingerprint
          AND t.trend_type = 'regression_after_fix'
          AND t.detected_at >= (now() AT TIME ZONE 'UTC')::DATE::TIMESTAMPTZ
      )
    RETURNING fingerprint
  )
  SELECT COUNT(*) INTO v_trends_emitted FROM today_trends;

  -- Step 3: stamp the most recent bug_intelligence_reports row per
  -- revived fingerprint with a paper-trail audit line. Re-opens the
  -- review path: review_status flips back from `merged` to `pending`
  -- so the report shows up in the CMS inbox + next export.
  UPDATE bug_intelligence_reports r
  SET review_status = 'pending',
      review_notes  = COALESCE(r.review_notes, '')
                      || E'\n['
                      || to_char(now(), 'YYYY-MM-DD HH24:MI UTC')
                      || '] Reopened by bug_intel_revive_regressed_fingerprints — '
                      || 'fingerprint saw post-fix activity past '
                      || p_grace_hours::TEXT
                      || 'h grace window.'
  WHERE r.id IN (
    SELECT DISTINCT ON (rr.fingerprint) rr.id
    FROM bug_intelligence_reports rr
    JOIN bug_intelligence_fingerprints f
      ON f.fingerprint = rr.fingerprint
    WHERE f.status = 'new'
      AND f.regressed_after_fix = TRUE
      AND f.updated_at >= now() - INTERVAL '5 minutes'
      AND rr.review_status = 'merged'
    ORDER BY rr.fingerprint, rr.created_at DESC
  );

  RAISE NOTICE 'bug_intel_revive_regressed_fingerprints(%h grace): revived % fingerprint(s), emitted % trend(s)',
               p_grace_hours, v_revived_count, v_trends_emitted;

  RETURN jsonb_build_object(
    'revived_count',   v_revived_count,
    'trends_emitted',  v_trends_emitted,
    'grace_hours',     p_grace_hours,
    'completed_at',    now()
  );
END;
$$;

COMMENT ON FUNCTION bug_intel_revive_regressed_fingerprints(INT) IS
  'Phase 13 close-the-loop (2026-04-26) — service-role cron. Scans '
  'pipeline-resolved fingerprints (auto_resolved_reason matches '
  'migration_resolved / code_fix / silent_fix / transient_single_incident / '
  'noise_filter_expanded) and revives any whose last_seen_at is past the '
  'grace window after their resolve. Flips status=new + regressed_after_fix=TRUE, '
  'emits a regression_after_fix trend, and reopens the matching report '
  'so it shows up in the CMS inbox and next Cursor handoff. NEVER touches '
  'human-resolved rows (auto_resolved_reason IS NULL means a human clicked '
  'Resolve — sticky). Mirrors the export-side STALE_FIX_GRACE_MS=48h cutoff.';

REVOKE ALL ON FUNCTION bug_intel_revive_regressed_fingerprints(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_revive_regressed_fingerprints(INT) TO service_role;

-- ----------------------------------------------------------------------------
-- 2. pg_cron schedule — :20 past every hour, after compute_daily_bug_rollup (:00).
--    `cron.schedule` is idempotent on the job name; re-running this
--    migration just updates the schedule.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  -- pg_cron may not be installed in every dev environment; only schedule
  -- when the extension is present.
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'bug-intel-revive-regressed-fingerprints';

    PERFORM cron.schedule(
      'bug-intel-revive-regressed-fingerprints',
      '20 * * * *',
      $cron$ SELECT bug_intel_revive_regressed_fingerprints(48); $cron$
    );

    RAISE NOTICE '[20260623] Scheduled bug-intel-revive-regressed-fingerprints @ :20 hourly.';
  ELSE
    RAISE NOTICE '[20260623] pg_cron not installed — skipped scheduling. RPC is callable manually.';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Smoke test — confirm RPC exists and returns the expected JSONB shape.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- Service-role guard means we run this body as service_role here.
  v_result := bug_intel_revive_regressed_fingerprints(48);

  IF NOT (v_result ? 'revived_count')
     OR NOT (v_result ? 'trends_emitted')
     OR NOT (v_result ? 'grace_hours') THEN
    RAISE EXCEPTION '[20260623 audit] revival RPC returned unexpected shape: %', v_result;
  END IF;

  RAISE NOTICE '[20260623 audit] Auto-revive cron installed. First run result: %', v_result;
  RAISE NOTICE '✅ Phase 13 close-the-loop installed: pipeline-resolved fingerprints now '
               'auto-revive when last_seen_at exceeds resolve+48h grace. Dashboard / export '
               'no longer hide silent regressions on the migration_resolved / code_fix track.';
END $$;

COMMIT;
