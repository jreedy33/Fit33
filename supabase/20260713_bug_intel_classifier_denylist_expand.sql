-- 20260713_bug_intel_classifier_denylist_expand.sql
-- Bug-Intel Classifier — Phase 12 noise filter expansion (2026-04-29)
--
-- Drains three transient-network / OS-environment classes that the
-- 2026-04-29T04:13 export keeps regenerating fingerprints for:
--
--   1. `BGTaskSchedulerErrorDomain` code 1 (BGTaskSchedulerErrorCodeUnavailable)
--      — iOS Background App Refresh disabled, Low Power Mode, simulator,
--      or "rate-limit / unavailable" responses from the scheduler when
--      the user has been heavy-rotating apps. NEVER a bug. Apple
--      documents code 1 as "device is currently unavailable for
--      background tasks". `BackgroundChallengeSyncService.scheduleNext()`
--      already swallows this internally, but legacy log paths surfaced
--      it as `.error` and it kept fingerprinting.
--
--   2. `NSURLErrorDomain` -1017 (cannotParseResponse) — server returned
--      a body PostgREST / our edge functions couldn't parse. Almost
--      always a Cloudflare flap mid-restart returning truncated JSON
--      or an HTML error page. Same shape as the existing 502/503 HTML
--      filters from `20260517_bug_intel_noise_filter_expand.sql`. Retry
--      queue picks it up on the next foreground.
--
--   3. `NSURLErrorDomain` -1001 (timedOut) — was kept on `soft` tier
--      by `20260516_bug_intel_structural_fingerprint.sql` so the trend
--      detector could flag op-specific regressions. In practice every
--      -1001 occurrence we've reviewed across 2026-04 has been a
--      transient handled by `CloudSyncRetryQueue`, and 247-item
--      classifier_lint backlog still surfaces it as CRITICAL through
--      legacy log paths (`AppLogger.error`). Flipping to `hard` lets
--      the classifier focus on real failures; we keep the per-op
--      regression signal via `bug_intel_severity_weights` instead.
--
-- Already on `hard` from `20260516`:
--   * NSURLErrorDomain -1009 (`nsurl_offline`) ✅
--   * NSURLErrorDomain -1005 (`nsurl_connection_lost`) ✅
--   * NSURLErrorDomain -999  (`nsurl_cancelled_tab_switch`) ✅
--
-- Schema reference (from `20260516_bug_intel_structural_fingerprint.sql`):
--   bug_intel_noise_filter (
--     name TEXT UNIQUE, op TEXT, pg_code TEXT, nsurl_code INT,
--     http_status INT, message_pattern TEXT,
--     tier TEXT CHECK (tier IN ('hard','soft')),
--     rationale TEXT, created_by TEXT
--   )
--
-- Match precedence is AND-of-non-NULL columns (an event matches a
-- filter row when every non-NULL column on the row equals the event's
-- corresponding extracted field). `nsurl_code = -1017` matches every
-- iOS NSURL -1017 regardless of op/endpoint.
--
-- INVARIANTS
-- ----------
--   * Idempotent — `ON CONFLICT (name) DO NOTHING` for adds, explicit
--     `UPDATE` for the soft→hard flip. Wrapped BEGIN/COMMIT.
--   * Backfill auto-resolves matching fingerprints with
--     `auto_resolved_reason = 'noise_filter_expanded'` (mirrors the
--     20260517 / 20260519 convention so the existing rollup audit
--     works unchanged).
--   * Trailing `DO $$` audit fails loud if the post-state doesn't
--     show all four expected canonical names + the -1001 row on
--     `tier = 'hard'`.
--
-- Rollback: `DELETE FROM bug_intel_noise_filter WHERE created_by = '20260713'`
-- plus restore `tier = 'soft'` on `nsurl_timeout_short`.

BEGIN;

-- ============================================================================
-- 1. Seed new noise filter rows.
-- ============================================================================

INSERT INTO bug_intel_noise_filter (name, nsurl_code, message_pattern, tier, rationale, created_by) VALUES

  -- --- Family 1: BGTaskScheduler unavailable (no nsurl_code; message-only) -----
  ('bgtask_scheduler_unavailable',
   NULL,
   'BGTaskSchedulerErrorDomain.*Code=1',
   'hard',
   'BGTaskSchedulerErrorCodeUnavailable (Apple BGTaskSchedulerError.unavailable). Device is currently unavailable for background tasks — Low Power Mode, Background App Refresh OFF in Settings, simulator, or scheduler rate-limit. Confirmed transient: BackgroundChallengeSyncService.scheduleNext() already swallows the throw internally; this filter cleans the back-catalog of legacy AppLogger.error call sites. Apple ref: https://developer.apple.com/documentation/backgroundtasks/bgtaskschedulererror/code/unavailable',
   '20260713'),

  -- --- Family 2: NSURL cannotParseResponse ------------------------------------
  ('nsurl_cannot_parse_response',
   -1017,
   NULL,
   'hard',
   'NSURLErrorCannotParseResponse (-1017) — server returned a body PostgREST / edge functions could not parse, almost always a Cloudflare flap mid-restart returning truncated JSON or an HTML error page. Pairs with the existing http_502_bad_gateway_html / http_503_service_unavailable filters from 20260517. Retry queue (CloudSyncRetryQueue) recovers automatically on the next foreground. Drains 2026-04-29 export fingerprints surfacing as "cannotParseResponse" / "unexpected end of JSON input".',
   '20260713')

ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 2. Flip nsurl_timeout_short (-1001) from soft → hard.
--
--    The 20260516 row was deliberately on `soft` so per-op regressions
--    surfaced in the trend detector. Three months of triage shows zero
--    real-bug signal from NSURL -1001 — every reviewed instance was a
--    transient already absorbed by CloudSyncRetryQueue. Per-op
--    regression sensitivity now lives in
--    bug_intel_severity_weights.class_amp_transient (default 0.5).
-- ============================================================================

UPDATE bug_intel_noise_filter
   SET tier = 'hard',
       rationale = 'NSURLErrorTimedOut (-1001) — transient network. Was on soft tier per 20260516 (kept signal for op-specific regressions) but every reviewed instance across 2026-02 → 2026-04 has been a transient handled by CloudSyncRetryQueue. Flipped to hard on 20260713 so the classifier focuses on real failures; per-op regression sensitivity now lives in bug_intel_severity_weights.class_amp_transient.'
 WHERE name = 'nsurl_timeout_short'
   AND tier <> 'hard';

-- ============================================================================
-- 3. Backfill: auto-resolve existing fingerprints matching the new filters
--    AND any open NSURL -1001 fingerprint that the soft tier let through.
-- ============================================================================

WITH noise_matches AS (
  SELECT DISTINCT f.fingerprint
    FROM bug_intelligence_fingerprints f
    JOIN bug_intel_noise_filter nf
      ON (
           nf.created_by = '20260713'
           AND (
             (nf.nsurl_code IS NOT NULL AND f.nsurl_code = nf.nsurl_code)
             OR (nf.message_pattern IS NOT NULL AND f.sample_message ~ nf.message_pattern)
           )
         )
    WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')

  UNION

  -- The flipped -1001 row was authored under created_by='migration_20260516'
  -- (canonical seed). Match it explicitly so the back-catalog drains.
  SELECT DISTINCT f.fingerprint
    FROM bug_intelligence_fingerprints f
    WHERE f.nsurl_code = -1001
      AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
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
         '[20260713] Auto-merged: structural_fingerprint now matches a Phase 12 noise filter (BGTaskSchedulerErrorDomain code 1, NSURLError -1017, or NSURL -1001 flipped soft→hard). Transient OS / network signal — not a bug.',
       reviewed_at = now()
  FROM bug_intelligence_fingerprints f
 WHERE r.fingerprint = f.fingerprint
   AND f.auto_resolved_reason = 'noise_filter_expanded'
   AND r.review_status IN ('pending', 'approved')
   AND f.updated_at >= now() - interval '1 minute';

-- ============================================================================
-- 4. Audit — confirm the post-state. Fail loud if anything is missing.
-- ============================================================================

DO $$
DECLARE
    v_bgtask_present  BOOLEAN;
    v_n1017_present   BOOLEAN;
    v_n1001_is_hard   BOOLEAN;
    v_resolved_count  INTEGER;
BEGIN
    SELECT EXISTS (SELECT 1 FROM bug_intel_noise_filter
                    WHERE name = 'bgtask_scheduler_unavailable'
                      AND tier = 'hard')
      INTO v_bgtask_present;

    SELECT EXISTS (SELECT 1 FROM bug_intel_noise_filter
                    WHERE name = 'nsurl_cannot_parse_response'
                      AND tier = 'hard'
                      AND nsurl_code = -1017)
      INTO v_n1017_present;

    SELECT (tier = 'hard')
      INTO v_n1001_is_hard
      FROM bug_intel_noise_filter
     WHERE name = 'nsurl_timeout_short';

    SELECT COUNT(*) INTO v_resolved_count
      FROM bug_intelligence_fingerprints
     WHERE auto_resolved_reason = 'noise_filter_expanded'
       AND updated_at >= now() - interval '1 minute';

    IF NOT v_bgtask_present THEN
        RAISE EXCEPTION '[20260713] bgtask_scheduler_unavailable filter missing or not hard';
    END IF;

    IF NOT v_n1017_present THEN
        RAISE EXCEPTION '[20260713] nsurl_cannot_parse_response (-1017) filter missing or not hard';
    END IF;

    IF v_n1001_is_hard IS NULL THEN
        RAISE EXCEPTION '[20260713] nsurl_timeout_short row not found — 20260516 seed missing';
    END IF;

    IF NOT v_n1001_is_hard THEN
        RAISE EXCEPTION '[20260713] nsurl_timeout_short still on soft tier after migration';
    END IF;

    RAISE NOTICE '[20260713] ✅ Phase 12 classifier denylist live: bgtask_scheduler_unavailable + nsurl_cannot_parse_response (-1017) seeded; nsurl_timeout_short flipped soft→hard; backfill auto-resolved % fingerprints',
        v_resolved_count;
END $$;

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- -- Confirm the three rules are in place:
-- SELECT name, nsurl_code, message_pattern, tier, created_by
--   FROM bug_intel_noise_filter
--  WHERE name IN ('bgtask_scheduler_unavailable',
--                 'nsurl_cannot_parse_response',
--                 'nsurl_timeout_short')
--  ORDER BY name;
--
-- -- Audit recent auto-resolutions tagged to this sweep:
-- SELECT fingerprint, sample_message, occurrence_count,
--        nsurl_code, error_domain, auto_resolved_at
--   FROM bug_intelligence_fingerprints
--  WHERE auto_resolved_reason = 'noise_filter_expanded'
--    AND updated_at >= now() - interval '1 day'
--  ORDER BY occurrence_count DESC
--  LIMIT 25;
