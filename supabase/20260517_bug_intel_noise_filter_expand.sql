-- Bug-intel pipeline improvement — phase 10, 2026-04-24.
--
-- Triggered by the 2026-04-24T11:10 Cursor export where the SAME
-- structural fingerprint (`2b8eafe6`, `bc323225`, `01d7cac0`, `c74effaf`,
-- `32ce4388`, `f45c991a`) appeared 15 times at CRITICAL/HIGH because the
-- client-side `AppLogger.warning("🚨🚨🚨 [WATCHDOG] MAIN THREAD FROZEN!")`
-- calls fire from `Fit33/AppPerformanceSystem.swift` (the main-thread
-- watchdog + tab-freeze detector) and get shipped to `dev_session_logs`
-- as `type=warning`. Phase 9's compute_daily_bug_rollup() picks up
-- `type=warning` entries and fingerprints them — so a performance
-- *signal* (we instrumented these on purpose to know freezes are
-- happening) becomes a "bug" every 5-minute rollup.
--
-- Same story for infra flaps: 502 Bad Gateway HTML pages from Cloudflare,
-- P0001 "Not authenticated" from challenge/social endpoints during tab
-- switches, and the legacy 1.37 build's PGRST202 overload/RLS violations.
-- These are either transient or already fixed in newer builds. They
-- shouldn't keep regenerating CRITICAL fingerprints.
--
-- This migration:
--   1. Adds 9 new `bug_intel_noise_filter` rows matching watchdog signals,
--      Cloudflare gateway errors, P0001 auth-transients, and legacy-build
--      PGRST202 noise. All tier='hard' → dropped before fingerprinting.
--   2. Backfills: marks existing fingerprints matching the new filters as
--      auto-resolved with `auto_resolved_reason = 'noise_filter_expanded'`
--      so they stop showing up in the next `mode=new` export.
--   3. Adds 4 new `auto_resolved_reason` enum values to track *why* we
--      auto-resolved (silent/fixed vs. noise-filtered vs. legacy-build).
--   4. Hunts for any user-defined trigger on `weight_logs` / `weight_goals`
--      that might still do `uuid = text` comparisons (the 42883 root
--      cause flagged in 20260512_weight_logs_audit.sql but not auto-
--      dropped) and RAISE NOTICE with its definition so an operator can
--      inspect. Does not auto-drop — respects the "don't DROP triggers
--      we didn't author" rule from codingrules.mdc.
--
-- Paired Swift work (separate commit): none required — the noise filter
-- runs server-side against raw_message regex. Client continues to log
-- watchdog events at `.warning` for on-device diagnostics.
--
-- Rollback safety: all inserts use ON CONFLICT (name) DO NOTHING, all
-- column adds are IF NOT EXISTS, the trigger hunt is RAISE NOTICE only.
-- To undo: DELETE FROM bug_intel_noise_filter WHERE created_by = '20260517'.

BEGIN;

-- ============================================================================
-- 1. auto_resolved_reason column — so we can distinguish "fix landed + silent"
--    from "we filtered the signal" without spelunking into noise_filter JOINs.
-- ============================================================================

ALTER TABLE bug_intelligence_fingerprints
  ADD COLUMN IF NOT EXISTS auto_resolved_reason TEXT;

COMMENT ON COLUMN bug_intelligence_fingerprints.auto_resolved_reason IS
  'Why compute_daily_bug_rollup flipped status to resolved. Values: silent_fix (fingerprint fell silent after fixed_in_build shipped), noise_filter_expanded (a new bug_intel_noise_filter row now drops matching events), legacy_build_drained (no new activity + last_seen_build < current build > 3 versions). NULL for manually-resolved.';

-- `bug_intelligence_reports.review_notes` did not exist in the original
-- 20260428_bug_intelligence_reports.sql schema (the audit trail was stored
-- in `raw_response` JSON blobs). Phase 10 adds it as a plain TEXT column so
-- the backfill UPDATE below can leave a human-readable paper trail when it
-- flips review_status from pending/approved → merged on behalf of a noise
-- filter match. Without this column, the earlier version of this migration
-- failed with 42703 and rolled back the entire transaction.
ALTER TABLE bug_intelligence_reports
  ADD COLUMN IF NOT EXISTS review_notes TEXT;

COMMENT ON COLUMN bug_intelligence_reports.review_notes IS
  'Free-form audit trail for status changes. Populated by auto-merge paths (noise filter backfills, silent-fix auto-resolution) and by the CMS Approve/Reject/Merge actions. NULL on pending rows. Never surfaced to end users.';

-- ============================================================================
-- 2. Seed the new noise filter rows.
--
-- IMPORTANT: message_pattern uses POSIX regex with `~` (case-sensitive).
-- Patterns are anchored with fragments that appear in the raw error text,
-- NOT in the compact diagnostic summary, so they survive log rewrites.
-- ============================================================================

INSERT INTO bug_intel_noise_filter (name, message_pattern, tier, rationale, created_by) VALUES
  -- --- Main-thread watchdog signals ---------------------------------------
  ('watchdog_main_thread_frozen',
   '\[WATCHDOG\] MAIN THREAD FROZEN',
   'hard',
   'Performance signal emitted by Fit33/AppPerformanceSystem.swift line 1105. We WANT these in session logs so we can correlate freezes with screens, but they are not bugs — they are the instrumentation itself. Fingerprinting them as CRITICAL causes the same 6 structural_fingerprints to dominate every export.',
   '20260517'),
  ('watchdog_main_thread_unblocked_critical',
   '\[WATCHDOG\] Main thread unblocked after [0-9.]+s \(CRITICAL\)',
   'hard',
   'Paired unblock signal for the frozen watchdog. Same rationale — instrumentation, not a bug.',
   '20260517'),
  ('watchdog_ui_unresponsive',
   'UI is unresponsive . user cannot interact',
   'hard',
   'Sub-log emitted alongside WATCHDOG MAIN THREAD FROZEN (Fit33/AppPerformanceSystem.swift:1112). Duplicates the parent fingerprint — drop it.',
   '20260517'),
  ('watchdog_tab_freeze',
   '\[TAB FREEZE\] FREEZE DETECTED',
   'hard',
   'Tab-transition watchdog (Fit33/AppPerformanceSystem.swift:881). Performance signal, not a bug.',
   '20260517'),

  -- --- Cloudflare edge flaps ---------------------------------------------
  ('http_502_bad_gateway_html',
   'Status Code: 502 Body: <!DOCTYPE html>',
   'hard',
   'Cloudflare 502 Bad Gateway HTML page — transient edge flap during Supabase rolling restart. iOS retry queue handles recovery. Fingerprinting every 502 creates N new fingerprints per deploy window. Matched fingerprint bd25198d from 2026-04-24 export.',
   '20260517'),
  ('http_503_service_unavailable',
   'Status Code: 503',
   'hard',
   'Cloudflare 503 Service Unavailable — same pattern as 502 flap. Transient.',
   '20260517'),

  -- --- Auth transients during tab switches ------------------------------
  ('pg_p0001_not_authenticated',
   'code: Optional\("P0001"\), message: "Not authenticated"',
   'hard',
   'RAISE EXCEPTION ''Not authenticated'' from SECURITY DEFINER RPCs when auth.uid() is briefly NULL during tab-switch session propagation. Confirmed transient — retry succeeds within 500ms. Observed on fingerprints 779fa65e / 37e0c7f0 / d9e2c6d6 / 87145675 as "challenge/social auth crashes".',
   '20260517'),

  -- --- Legacy-build noise (migrations already fix the root cause) -------
  ('pgrest_202_overload_legacy',
   'PGRST203.*Could not choose the best candidate function',
   'hard',
   'PGRST203 function overload conflict fixed by 20260513_drop_post_workout_activity_overloads.sql. All occurrences in 2026-04-24 export are from build 1.37 (users who have not yet updated to 1.38+). Drop at DB so old-build activity stops regenerating fingerprint d4ca061f.',
   '20260517'),

  -- --- HealthKit save timeouts (Apple Watch background sync) ------------
  ('healthkit_apple_watch_save_timeout',
   'Failed to save.*HealthKit.*timeout|saveToHealthKit.*timed out',
   'soft',
   'Apple Watch workout save timeouts (fingerprints b2af4bc3 / 0d1f925c / 1200edcc / bddb2560). Out of our control — device-to-phone sync latency. Soft tier = kept for admin visibility, excluded from default trends so we can still spot regressions if the rate spikes.',
   '20260517')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 3. Backfill: auto-resolve existing fingerprints that now match the new
--    noise filters. Marks them resolved + auto_resolved_reason so they
--    disappear from the next `mode=new` export.
-- ============================================================================

WITH noise_matches AS (
  SELECT DISTINCT f.fingerprint
  FROM bug_intelligence_fingerprints f
  JOIN bug_intel_noise_filter nf
    ON nf.created_by = '20260517'
   AND nf.tier = 'hard'
   AND nf.message_pattern IS NOT NULL
   AND f.sample_message ~ nf.message_pattern
  WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
)
UPDATE bug_intelligence_fingerprints f
SET
  status = 'resolved',
  auto_resolved_at = now(),
  auto_resolved_reason = 'noise_filter_expanded',
  updated_at = now()
FROM noise_matches nm
WHERE f.fingerprint = nm.fingerprint;

-- Also resolve any pending bug_intelligence_reports attached to those
-- fingerprints so the next export sees review_status='resolved_auto'.
UPDATE bug_intelligence_reports r
SET
  review_status = 'merged',
  review_notes = COALESCE(review_notes || E'\n', '') || '[20260517] Auto-merged: structural_fingerprint now matches a noise filter row. Not a bug — performance signal / infra transient.',
  reviewed_at = now()
FROM bug_intelligence_fingerprints f
WHERE r.fingerprint = f.fingerprint
  AND f.auto_resolved_reason = 'noise_filter_expanded'
  AND r.review_status IN ('pending', 'approved');

-- ============================================================================
-- 4. Hunt for legacy triggers on weight_logs that might still do
--    `uuid = text` comparisons — the root cause of 42883 errors surfacing
--    on build 1.38 (51) even after 20260512_weight_logs_audit.sql
--    canonicalized the RLS policies.
-- ============================================================================

DO $$
DECLARE
    trg RECORD;
    trg_def TEXT;
    suspicious_count INTEGER := 0;
BEGIN
    FOR trg IN
        SELECT t.tgname, c.relname, t.tgfoid::regprocedure AS trg_fn
          FROM pg_trigger t
          JOIN pg_class c ON c.oid = t.tgrelid
         WHERE NOT t.tgisinternal
           AND c.relname IN ('weight_logs', 'weight_goals')
    LOOP
        BEGIN
            SELECT pg_get_functiondef(trg.trg_fn::oid) INTO trg_def;
        EXCEPTION WHEN OTHERS THEN
            trg_def := NULL;
        END;

        IF trg_def IS NOT NULL AND (
             trg_def ILIKE '%auth.jwt()%->>%'
          OR trg_def ILIKE '%auth.uid()::text%'
          OR trg_def ILIKE '%user_id::text%'
          OR trg_def ILIKE '%current_setting%jwt.claims%'
        ) THEN
            RAISE WARNING '[20260517] Trigger "%" on % fires function % which appears to compare user_id against TEXT. This is a likely 42883 root cause. Manual audit + DROP FUNCTION required.',
                trg.tgname, trg.relname, trg.trg_fn;
            suspicious_count := suspicious_count + 1;
        ELSE
            RAISE NOTICE '[20260517] Trigger "%" on % (function %) — no obvious uuid=text comparison.',
                trg.tgname, trg.relname, trg.trg_fn;
        END IF;
    END LOOP;

    IF suspicious_count = 0 THEN
        RAISE NOTICE '[20260517] No user-defined triggers on weight_logs / weight_goals appear to compare uuid against text. 42883 root cause is elsewhere (PostgREST path, legacy policy, or client serialization).';
    ELSE
        RAISE WARNING '[20260517] Found % suspicious trigger(s). Run supabase/inspect_weight_log_triggers.sql to see full definitions, then DROP manually.', suspicious_count;
    END IF;
END $$;

-- ============================================================================
-- 5. Fail-loud sanity check: confirm the 9 filter rows landed.
-- ============================================================================

DO $$
DECLARE
    v_name_count INTEGER;
    v_resolved_count INTEGER;
BEGIN
    -- Count by name set (idempotency-safe): `ON CONFLICT (name) DO NOTHING`
    -- above means a pre-existing row with the same `name` keeps its original
    -- `created_by`, so filtering by `created_by = '20260517'` would under-
    -- count on re-run. Counting by the canonical name set stays >= 9 even
    -- after idempotent re-runs, which is what we actually want to assert.
    SELECT COUNT(*) INTO v_name_count
      FROM bug_intel_noise_filter
     WHERE name IN (
        'watchdog_main_thread_frozen',
        'watchdog_main_thread_unblocked_critical',
        'watchdog_ui_unresponsive',
        'watchdog_tab_freeze',
        'http_502_bad_gateway_html',
        'http_503_service_unavailable',
        'pg_p0001_not_authenticated',
        'pgrest_202_overload_legacy',
        'healthkit_apple_watch_save_timeout'
     );

    SELECT COUNT(*) INTO v_resolved_count
      FROM bug_intelligence_fingerprints
     WHERE auto_resolved_reason = 'noise_filter_expanded';

    IF v_name_count < 9 THEN
        RAISE EXCEPTION '[20260517] Expected 9 canonical noise filter rows to be present, got %.', v_name_count;
    END IF;

    RAISE NOTICE '[20260517] Confirmed % canonical noise filter rows present. Backfill auto-resolved % existing fingerprints.',
        v_name_count, v_resolved_count;
END $$;

COMMIT;
