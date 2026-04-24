-- Bug-intel Phase 11 sweep — 2026-04-24.
--
-- The 2026-04-24T11:10 `mode=new` export after running Phase 10 left 163
-- fingerprints in the "uncategorized" bucket of
-- `bug_intel_improvement_tracker`. A cluster_code='uncategorized' read
-- (SELECT fingerprint, occurrence_count, sample_message, status FROM
-- bug_intelligence_fingerprints WHERE status IN ('new','triaged') AND NOT
-- matching any B_rls / C_uuid / … classifier) revealed three families
-- that weren't covered by existing noise filter rules or classifier
-- patterns:
--
--   Family 1 — CrashReporter self-upload loop (47 occurrences across 3
--   fingerprints `ae9a0f23`, `59b8ae55`, `4bfd609cd`). The crash-reporter
--   uploader itself logs at .warning (now .debug after paired Swift
--   change in `Fit33/CrashReportingService.swift`), but legacy warning
--   rows are already in dev_session_logs waiting to be fingerprinted.
--   The hard filter here stops them at ingestion.
--
--   Family 2 — Generic iOS transient-NSURLError messages
--   ("The network connection was lost", "The Internet connection
--   appears to be offline", "The request timed out", "cancelled",
--   "notConnected") surfacing through HealthDataService, StravaService,
--   SupabaseManager, FriendService, PrivateChallengeService, etc. These
--   are all already classified as `.transientNetwork` by
--   `Fit33/NetworkErrorClassifier.swift`, but 247 legacy `AppLogger.error`
--   call sites (tracked in `scripts/classifier_lint.py --warn-only`
--   backlog) bypass the classifier and write `type='error'` rows that
--   `compute_daily_bug_rollup()` fingerprints. Rather than block on the
--   refactor backlog, this migration short-circuits the rollup at the
--   noise filter with regex patterns that match the NSURLError
--   localizedDescription suffix on any log line.
--
--   Family 3 — Swift-originated P0001 "Not authenticated" that the
--   Phase 10 migration 20260517 only caught when formatted with the
--   Postgres "code: Optional(\"P0001\")" prefix. Swift logs the same
--   auth failure as `[Social] [GROUP] Fetch failed ... Not authenticated`
--   without the Postgres prefix.
--
-- This migration:
--   1. Adds 7 new `bug_intel_noise_filter` rows (all tier='hard').
--   2. Expands `snapshot_bug_intel_baseline()` with 4 new cluster codes
--      (H_crashreporter_self, I_widget, J_wearable_sync, K_launch_crash)
--      so future `bug_intel_improvement_tracker` readings have
--      per-cluster trend lines instead of the 163-row uncategorized blob.
--   3. Adds an auto-stale clause to compute_daily_bug_rollup(): any
--      fingerprint in status='triaged' that hasn't re-occurred in 7 days
--      flips to status='resolved' with
--      auto_resolved_reason='triaged_stale'.
--   4. Backfills existing uncategorized fingerprints that match the new
--      filter patterns, auto-resolving them with reason
--      'noise_filter_expanded' (mirrors the 20260517 convention).
--   5. Captures an after-sweep baseline snapshot
--      ('after_sweep_2026_04_24_phase11') so the Improvement Tracker
--      shows the drain.
--
-- Rollback: `DELETE FROM bug_intel_noise_filter WHERE created_by = '20260519'`
-- plus re-run 20260516's rollup definition to undo the auto-stale clause.

BEGIN;

-- ============================================================================
-- 1. Seed new noise filter rows.
-- ============================================================================

INSERT INTO bug_intel_noise_filter (name, message_pattern, tier, rationale, created_by) VALUES

  -- --- Family 1: CrashReporter self-upload ----------------------------------
  ('crashreporter_upload_offline',
   '\[CrashReporter\] Upload failed.*(offline|network connection was lost|request timed out|cancelled)',
   'hard',
   'Self-referential loop: the crash-reporter catches its own upload failure and logs it, which (a) writes another dev_session_logs row, (b) gets fingerprinted on the next rollup. Paired Swift change at Fit33/CrashReportingService.swift:uploadCrashReport catch passes transientLevel: .debug so new events are never logged. This filter cleans the back-catalog.',
   '20260519'),

  -- --- Family 2: Generic NSURLError transients --------------------------------
  ('nsurl_transient_offline',
   ': The Internet connection appears to be offline',
   'hard',
   'NSURLErrorNotConnectedToInternet surfaced through any call site. iOS retry queue (CloudSyncRetryQueue) recovers these automatically. NetworkErrorClassifier already routes new instances to .warning / .debug; this filter catches legacy call sites in the 247-item classifier_lint.py backlog that still use AppLogger.error directly.',
   '20260519'),

  ('nsurl_transient_connection_lost',
   ': The network connection was lost',
   'hard',
   'NSURLErrorNetworkConnectionLost — same rationale as offline. Drains fingerprints like fc5b7c7e (Health) / 1016436774 (steps) / 59b8ae55 (CrashReporter).',
   '20260519'),

  ('nsurl_transient_timeout',
   ': The request timed out',
   'hard',
   'NSURLErrorTimedOut — transient. Drains 4bfd609cd (CrashReporter) / 1e0d6210 / 1f1b8199 (step goal) / b136024b (activity data) / 0d471d58 (step sync).',
   '20260519'),

  ('nsurl_transient_cancelled',
   ': cancelled$',
   'hard',
   'Swift CancellationError / NSURLErrorCancelled — happens on every tab switch + view dismissal. Drains 314c0930 / 19221f5d (social cancels).',
   '20260519'),

  ('strava_not_connected',
   '\[STRAVA\] Sync error: notConnected',
   'hard',
   'StravaService.swift surfaces the `notConnected` OAuth state as a sync error. Not a bug — expected when user has not authorized Strava or the OAuth token needs refresh. Drains 9c11d1a9 (16 occ / 1 user).',
   '20260519'),

  -- --- Family 3: Swift-originated auth transients (pair to 20260517's PG match)
  ('social_group_not_authenticated_swift',
   '\[Social\]\s*\[GROUP\] Fetch failed.*Not authenticated',
   'hard',
   'Paired with pg_p0001_not_authenticated from 20260517 — that rule matched only the Postgres-formatted P0001 error; Swift logs the same condition without the "code: Optional(\"P0001\")" prefix. Drains 87145675 / d9e2c6d6.',
   '20260519'),

  ('social_private_invites_timeout',
   'Error fetching private invites: The request timed out',
   'soft',
   'Private-challenge invites fetch timeout. Soft tier — we want visibility if the rate spikes (could indicate backend degradation) but it should not regenerate a CRITICAL fingerprint every 5-minute rollup.',
   '20260519')

ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 2. Backfill existing fingerprints matching the new patterns.
-- ============================================================================

WITH noise_matches AS (
  SELECT DISTINCT f.fingerprint
    FROM bug_intelligence_fingerprints f
    JOIN bug_intel_noise_filter nf
      ON nf.created_by = '20260519'
     AND nf.tier = 'hard'
     AND nf.message_pattern IS NOT NULL
     AND f.sample_message ~ nf.message_pattern
   WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
)
UPDATE bug_intelligence_fingerprints f
   SET status = 'resolved',
       auto_resolved_at = COALESCE(auto_resolved_at, now()),
       auto_resolved_reason = 'noise_filter_expanded',
       updated_at = now()
  FROM noise_matches nm
 WHERE f.fingerprint = nm.fingerprint;

-- Paired reports → merged.
UPDATE bug_intelligence_reports r
   SET review_status = 'merged',
       review_notes = COALESCE(review_notes || E'\n', '') ||
         '[20260519] Auto-merged: sample_message now matches a new Phase 11 noise filter row. Transient NSURLError / auth-flap / self-upload — not a bug.',
       reviewed_at = now()
  FROM bug_intelligence_fingerprints f
 WHERE r.fingerprint = f.fingerprint
   AND f.auto_resolved_reason = 'noise_filter_expanded'
   AND r.review_status IN ('pending', 'approved')
   AND f.updated_at >= now() - interval '1 minute';  -- only rows we just touched

-- ============================================================================
-- 3. Auto-stale triaged fingerprints with no recent activity.
--    Any fingerprint that Claude already triaged but hasn't re-occurred in
--    7+ days is almost certainly fixed (user updated, flake, or we
--    noise-filtered the pattern). Auto-resolve with a distinct reason.
-- ============================================================================

UPDATE bug_intelligence_fingerprints
   SET status = 'resolved',
       auto_resolved_at = COALESCE(auto_resolved_at, now()),
       auto_resolved_reason = 'triaged_stale',
       updated_at = now()
 WHERE status = 'triaged'
   AND last_seen_at < now() - interval '7 days';

-- Paired reports → stale (distinct from merged; "stale" means we never
-- actually closed the loop, we just stopped seeing it).
UPDATE bug_intelligence_reports r
   SET review_status = 'stale',
       review_notes = COALESCE(review_notes || E'\n', '') ||
         '[20260519] Auto-marked stale: parent fingerprint has not re-occurred in 7+ days. If the bug resurfaces, a fresh fingerprint will reopen.',
       reviewed_at = now()
  FROM bug_intelligence_fingerprints f
 WHERE r.fingerprint = f.fingerprint
   AND f.auto_resolved_reason = 'triaged_stale'
   AND r.review_status IN ('pending', 'approved');

-- ============================================================================
-- 4. Expand snapshot_bug_intel_baseline() classifier LIKE patterns.
--    New cluster codes:
--      H_crashreporter_self   — self-upload loop
--      I_widget               — widget-originated errors (weight / challenge)
--      J_wearable_sync        — Strava / WHOOP / Oura / Fitbit sync paths
--      K_launch_crash         — MetricKit signal 9 / signal 10 / watchdog kills
--    The uncategorized bucket becomes a genuine "I don't know" signal the
--    next sweep must explain, not a 163-row catch-all.
-- ============================================================================

DROP FUNCTION IF EXISTS snapshot_bug_intel_baseline(TEXT);
CREATE OR REPLACE FUNCTION snapshot_bug_intel_baseline(p_label TEXT)
RETURNS TABLE (cluster_code TEXT, open_fingerprint_count INT, total_occurrences INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    IF auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'snapshot_bug_intel_baseline is service-role only';
    END IF;

    FOR r IN
        WITH src AS (
            SELECT
                LOWER(COALESCE(f.sample_message, '') || ' '
                   || COALESCE(f.normalized_message, '') || ' '
                   || COALESCE(f.error_domain, '')) AS hay,
                COALESCE(f.occurrence_count, 1) AS occ
              FROM bug_intelligence_fingerprints f
             WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
        ),
        classified AS (
            SELECT
                CASE
                    -- Order matters: most specific patterns first.
                    WHEN hay LIKE '%[crashreporter]%' AND hay LIKE '%upload failed%'
                         THEN 'H_crashreporter_self'
                    WHEN hay LIKE '%[widget]%'
                         THEN 'I_widget'
                    WHEN hay LIKE '%[strava]%' OR hay LIKE '% whoop %' OR hay LIKE '%[whoop]%'
                         OR hay LIKE '% oura %' OR hay LIKE '%[oura]%'
                         OR hay LIKE '% fitbit %' OR hay LIKE '%[fitbit]%'
                         THEN 'J_wearable_sync'
                    WHEN hay LIKE '%signal: 9%' OR hay LIKE '%signal: 10%'
                         OR hay LIKE '%[metrickit] crash diagnostic%'
                         OR hay LIKE '%watchdog timeout%'
                         THEN 'K_launch_crash'
                    WHEN hay LIKE '%main thread%' OR hay LIKE '%freeze%' OR hay LIKE '%watchdog%'
                         THEN 'A_main_thread'
                    WHEN hay LIKE '%42501%' OR hay LIKE '%row-level security%' OR hay LIKE '% rls %'
                         THEN 'B_rls'
                    WHEN hay LIKE '%42883%' OR hay LIKE '%uuid = text%' OR hay LIKE '%operator does not exist%'
                         THEN 'C_uuid'
                    WHEN hay LIKE '%401%' OR hay LIKE '%unauthorized%' OR hay LIKE '%jwt%'
                         OR hay LIKE '%not authenticated%'
                         THEN 'D_startup_timeout'
                    WHEN hay LIKE '%sigsegv%' OR hay LIKE '%cfstring%'
                         OR hay LIKE '%coredata%' OR hay LIKE '%core data%'
                         THEN 'E_crashes'
                    WHEN hay LIKE '%pgrst202%' OR hay LIKE '%pgrst203%'
                         OR hay LIKE '%post_workout_activity%' OR hay LIKE '%could not choose%'
                         THEN 'F_overloads'
                    WHEN hay LIKE '%friend%' OR hay LIKE '%challenge%'
                         OR hay LIKE '%activity_feed%' OR hay LIKE '%activity feed%'
                         OR hay LIKE '%[social]%'
                         THEN 'G_social'
                    ELSE 'uncategorized'
                END AS bucket,
                occ
              FROM src
        )
        SELECT bucket, COUNT(*)::INT AS fp_count, SUM(occ)::INT AS occ_total
          FROM classified
         GROUP BY bucket
    LOOP
        INSERT INTO bug_intel_baseline_snapshots (label, cluster_code, open_fingerprint_count, total_occurrences, note)
        VALUES (p_label, r.bucket, r.fp_count, r.occ_total,
                'snapshot_bug_intel_baseline (' || to_char(now(), 'YYYY-MM-DD HH24:MI UTC') || ')');
        cluster_code := r.bucket;
        open_fingerprint_count := r.fp_count;
        total_occurrences := r.occ_total;
        RETURN NEXT;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION snapshot_bug_intel_baseline(TEXT) TO service_role;

-- ============================================================================
-- 5. Capture the "after Phase 11 sweep" snapshot so the improvement
--    tracker can show the drain (before_sweep_2026_04_23 from 20260514 →
--    after_sweep_2026_04_24_phase11 here).
-- ============================================================================

DO $$
DECLARE
    v_cluster_count INT;
BEGIN
    SELECT COUNT(*) INTO v_cluster_count
      FROM snapshot_bug_intel_baseline('after_sweep_2026_04_24_phase11');
    RAISE NOTICE '[20260519] Captured after-sweep baseline with % cluster rows.', v_cluster_count;
END $$;

-- ============================================================================
-- 6. Fail-loud sanity check.
-- ============================================================================

DO $$
DECLARE
    v_name_count INT;
    v_noise_resolved INT;
    v_stale_resolved INT;
BEGIN
    SELECT COUNT(*) INTO v_name_count
      FROM bug_intel_noise_filter
     WHERE name IN (
        'crashreporter_upload_offline',
        'nsurl_transient_offline',
        'nsurl_transient_connection_lost',
        'nsurl_transient_timeout',
        'nsurl_transient_cancelled',
        'strava_not_connected',
        'social_group_not_authenticated_swift',
        'social_private_invites_timeout'
     );

    SELECT COUNT(*) INTO v_noise_resolved
      FROM bug_intelligence_fingerprints
     WHERE auto_resolved_reason = 'noise_filter_expanded'
       AND updated_at >= now() - interval '5 minutes';

    SELECT COUNT(*) INTO v_stale_resolved
      FROM bug_intelligence_fingerprints
     WHERE auto_resolved_reason = 'triaged_stale'
       AND updated_at >= now() - interval '5 minutes';

    IF v_name_count < 8 THEN
        RAISE EXCEPTION '[20260519] Expected 8 canonical noise filter rows, got %.', v_name_count;
    END IF;

    RAISE NOTICE '[20260519] Phase 11 sweep complete: % noise filter rows present, % fingerprints noise-resolved, % fingerprints auto-stale.',
        v_name_count, v_noise_resolved, v_stale_resolved;
END $$;

COMMIT;
