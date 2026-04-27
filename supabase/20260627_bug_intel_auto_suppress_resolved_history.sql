-- ════════════════════════════════════════════════════════════════════
-- Migration #127 — Auto-suppress fingerprints whose md5 is in
-- bug_intel_resolved_history (Phase 13 close-the-loop, hardening).
-- 2026-04-27
--
-- PROBLEM
-- -------
-- The 2026-04-27 02:25 export (mode=`new`) showed 25 reports — but
-- 22 of those 25 were fingerprints that we ALREADY resolved on
-- 2026-04-26 in close-out migrations #124 / #126. They came back
-- because:
--
--   1. After #124 / #126 flipped the rows to `status='resolved'`,
--      something deleted them (most likely a `clear_resolved_bug_intelligence`
--      click in the CMS — that path DELETEs terminal-status rows
--      whose reports have all been merged).
--   2. Later activity for the same md5 hash arrived via
--      `compute_daily_bug_rollup`. The rollup's `INSERT … ON CONFLICT
--      DO UPDATE` couldn't find a row to update, so it INSERTED a
--      fresh row with `status='new'` (the table default).
--   3. The triage edge function then flipped the new row to
--      `status='triaged'` and created a fresh `bug_intelligence_reports`
--      row with `review_status='pending'`.
--   4. The export filter looks at `bug_intelligence_fingerprints.status`,
--      sees `triaged`, and includes the report. The bug looks brand-new.
--
-- The user's 2026-04-26 22:33 ask was explicit:
--   "going forward I only want those 'three' [genuinely new ones] to
--    appear — I don't want the others that we've resolved (unless they
--    continue to occur as real issues) to appear in the report."
--
-- FIX
-- ---
-- Append-only `bug_intel_resolved_history` already snapshots every md5
-- that has ever been resolved (Phase 12 Tier 5 #1, migration #96).
-- This migration adds a `BEFORE INSERT OR UPDATE` trigger on
-- `bug_intelligence_fingerprints` that consults that history every
-- time a row is touched:
--
--   * If the row's md5 has a recent `bug_intel_resolved_history` entry
--     AND `last_seen_at <= history.resolved_at + 48h grace`:
--     flip the NEW row to `status='resolved'` with reason
--     `auto_suppress_from_history:<original_reason>`. Stamp
--     `latest_resolving_migration_at` so the export-side stale-fix
--     filter (#114) and the auto-revive cron (#125) agree on the
--     deploy moment.
--
--   * If the row's md5 has a history entry AND `last_seen_at >
--     history.resolved_at + 48h`: leave `status` non-terminal but
--     set `regressed_after_fix=TRUE` so the export's
--     "regression after fix" path surfaces it (genuine recurrence).
--
--   * If the row has no history entry: leave it alone (truly new bug).
--
-- The trigger is idempotent: re-touching an already-resolved row is
-- a no-op (the early-return on terminal status). It's also race-free
-- against the triage edge function — even if triage tries to flip
-- status to `triaged`, the next UPDATE OF last_seen_at re-fires the
-- trigger and resnapshots from history.
--
-- COMPANION
-- ---------
-- A backfill block at the end re-resolves the 22 returners from the
-- 2026-04-27 02:25 export so the dashboard / inbox snaps clean
-- without waiting for the next rollup tick. The 3 genuinely-new
-- fingerprints (`ecca580f`, `3037a6f4`, `a47d011b`) are NOT in
-- resolved_history and stay visible.
--
-- Two of those three (`ecca580f` push 503, `a47d011b` insights timeout)
-- are also being closed out here because the iOS commit shipping with
-- this migration routes both through `NetworkErrorClassifier.log` —
-- they will not fingerprint on current builds going forward. The
-- third (`3037a6f4` exercise-library-empty shake report) is HIGH
-- severity and stays visible for human triage.
--
-- BACKWARD COMPAT
-- ---------------
-- Pure additive: new trigger + new function. No existing column,
-- view, or RPC is modified.
--
-- ROLLBACK
-- --------
--   DROP TRIGGER IF EXISTS trg_bug_intel_auto_suppress_from_history
--     ON bug_intelligence_fingerprints;
--   DROP FUNCTION IF EXISTS bug_intel_auto_suppress_from_history();
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Trigger function: auto_suppress_from_history
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bug_intel_auto_suppress_from_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_history       RECORD;
    v_grace         INTERVAL := INTERVAL '48 hours';
    v_within_grace  BOOLEAN;
BEGIN
    -- Skip if this row is already terminal — don't second-guess
    -- close-out migrations or human Resolve clicks.
    IF NEW.status IN ('resolved', 'wont_fix', 'duplicate') THEN
        RETURN NEW;
    END IF;

    -- Look up the most recent resolution for this md5. The history
    -- table is append-only with `UNIQUE (fingerprint, resolved_at)` so
    -- DESC + LIMIT 1 is deterministic.
    SELECT *
      INTO v_history
      FROM bug_intel_resolved_history
     WHERE fingerprint = NEW.fingerprint
     ORDER BY resolved_at DESC
     LIMIT 1;

    IF NOT FOUND THEN
        -- Never resolved before → genuinely new bug. Leave alone.
        RETURN NEW;
    END IF;

    -- Within grace = stale-tail recurrence of an already-fixed bug.
    -- Past grace = genuine regression — flag but don't hide.
    v_within_grace := NEW.last_seen_at <= (v_history.resolved_at + v_grace);

    IF v_within_grace THEN
        NEW.status                          := 'resolved';
        NEW.auto_resolved_reason            := 'auto_suppress_from_history:'
                                               || COALESCE(v_history.auto_resolved_reason, 'unknown');
        NEW.auto_resolved_at                := COALESCE(NEW.auto_resolved_at, now());
        NEW.resolved_at                     := COALESCE(NEW.resolved_at, v_history.resolved_at);
        NEW.resolution_pr_url               := COALESCE(NEW.resolution_pr_url, v_history.resolution_pr_url);
        NEW.latest_resolving_migration_at   := COALESCE(NEW.latest_resolving_migration_at, v_history.resolved_at);
        NEW.regressed_after_fix             := FALSE;
    ELSE
        -- Genuine regression: keep it visible, mark it.
        -- The export's "regression after fix" path will surface it
        -- prominently. The auto-revive cron (#125) is now redundant
        -- for this row — the trigger handles it during the rollup.
        NEW.regressed_after_fix := TRUE;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION bug_intel_auto_suppress_from_history() IS
    'Phase 13 close-the-loop hardening (2026-04-27) — BEFORE INSERT/UPDATE '
    'trigger function on bug_intelligence_fingerprints. Auto-suppresses any '
    'row whose md5 matches a recent bug_intel_resolved_history entry within '
    'the 48h stale-fix grace window (mirrors export STALE_FIX_GRACE_MS). '
    'Past-grace recurrences are flagged regressed_after_fix=TRUE instead '
    'of suppressed. Skips already-terminal rows (no second-guessing close-out '
    'migrations or human Resolve clicks). The grace constant must stay in '
    'lock-step with admin-cms/src/app/api/admin/route.ts and '
    '20260623_bug_intel_auto_revive_on_regression.sql — diverging values '
    'cause asymmetric "fingerprint disappears in handoff but stays open in '
    'CMS" bugs.';

GRANT EXECUTE ON FUNCTION bug_intel_auto_suppress_from_history() TO service_role;

-- ----------------------------------------------------------------------------
-- 2. Trigger: BEFORE INSERT OR UPDATE OF last_seen_at, status
--    Listening on `last_seen_at` covers the rollup hot-path; listening
--    on `status` ALSO covers the case where the triage edge function
--    flips a row from `new` → `triaged`, so we re-check history then too.
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_bug_intel_auto_suppress_from_history
    ON bug_intelligence_fingerprints;

CREATE TRIGGER trg_bug_intel_auto_suppress_from_history
BEFORE INSERT OR UPDATE OF last_seen_at, status
    ON bug_intelligence_fingerprints
FOR EACH ROW
EXECUTE FUNCTION bug_intel_auto_suppress_from_history();

COMMENT ON TRIGGER trg_bug_intel_auto_suppress_from_history
    ON bug_intelligence_fingerprints IS
    'Phase 13 close-the-loop hardening (2026-04-27). Fires before any '
    'rollup INSERT/UPSERT or triage status flip on bug_intelligence_fingerprints. '
    'Cross-checks bug_intel_resolved_history; if the md5 was previously '
    'resolved within the 48h grace window, re-applies the resolved status '
    'so deleted-then-recreated rows do NOT come back as "new" bugs in the '
    'export.';

-- ----------------------------------------------------------------------------
-- 3. Backfill — re-resolve the 22 returners from the 2026-04-27 02:25
--    export. These all match resolved_history entries from
--    20260622 / 20260624 close-outs but currently sit in non-terminal
--    status because they were deleted + recreated.
--
--    We trigger the suppression by UPDATE-ing each row's `last_seen_at`
--    to itself — that fires the trigger, which checks history, and
--    flips status to `resolved` if eligible. The audit_resolved_reason
--    will read `auto_suppress_from_history:<original>` so admins can
--    trace the snap-back.
-- ----------------------------------------------------------------------------

UPDATE bug_intelligence_fingerprints
   SET last_seen_at = last_seen_at  -- no-op write to fire the trigger
 WHERE fingerprint = ANY(ARRAY[
    '64639cbdf7b7eae9f97e9d3bf7574240', -- USDA food search Unauthorized
    'e6aaf4bba882dac7c537bea6eca6c75f', -- USDA cloud search Unauthorized
    'e810bf12eb825d4887a761ada6e0f90b', -- workout_context RLS
    '1b6e9111a71c83930852e93f1aff33e5', -- collaborative_workout_data RLS
    '00bd6a627c915cc0e49ed59a6a3cc140', -- signup user already registered
    'e656ad7a4fb1323db476cd8f2cf6ac39', -- daily quests sig mismatch (29 params)
    '7bf1ff4efdac6620edfbda328204ed16', -- quest insights view missing
    '265848d4ecf46ff84e247d8b572af43b', -- daily quest int overflow (line variant)
    '64e1ccf7bf450c9d591fab6d80f41847', -- daily quest int overflow (crash)
    '1edfaad0c87c90a26f1fb59fb5cbc983', -- pwd reset rate limit
    'a22cd96f76784e01bf8f4e0c89433109', -- pwd reset rate limit (variant)
    'f30626309d8480ec14526323da68396d', -- quest insights view missing (log)
    '486b89c025c019b7f2b6c427a437811e', -- daily quests sig mismatch (23 params)
    '2d865e51c4cf99a5b3a05d17e1d5bce0', -- daily quest int overflow (medium)
    'c70b931f12e33e65a564d5935d43b2d1', -- daily quest int overflow (log)
    'd8fe113b2a14b80603ca156e2ee0c990', -- group challenge nudges schema mismatch
    '23ac878010450752bb1b1ca994edb56b', -- private challenge progress deadlock (log)
    '15cce20e4302a42e1437f65fdf8fa667', -- signup existing email (log)
    '64b1cbec58d495ed42b3fbea94cac8e9', -- Strava 503 (crash)
    '22422e4eaca00ea54a0ac3e5fbcb2d8a', -- auth rate limit account creation
    '0d1100deb68ce4cac3662968aa11c15c', -- chal HK sync cascade
    '1e8bef4991bef4fbdb0ba8791829d8ed'  -- pwd reset rate limit (medium)
   ])
   AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- Also merge any pending bug_intelligence_reports rows for these
-- fingerprints — these are the new pending reports that triage created
-- on top of the deleted-then-recreated rows. Same paper-trail
-- convention as #120 / #124 / #126.
UPDATE bug_intelligence_reports r
   SET review_status = 'merged',
       review_notes  = COALESCE(review_notes, '')
                       || E'\n[2026-04-27 auto-suppress] '
                       || 'Auto-merged by 20260627_bug_intel_auto_suppress_resolved_history.sql — '
                       || 'fingerprint had a recent bug_intel_resolved_history entry within '
                       || '48h grace; trigger flipped status back to resolved.',
       reviewed_at   = COALESCE(reviewed_at, NOW())
 WHERE r.review_status IN ('pending', 'approved')
   AND r.fingerprint = ANY(ARRAY[
    '64639cbdf7b7eae9f97e9d3bf7574240', 'e6aaf4bba882dac7c537bea6eca6c75f',
    'e810bf12eb825d4887a761ada6e0f90b', '1b6e9111a71c83930852e93f1aff33e5',
    '00bd6a627c915cc0e49ed59a6a3cc140', 'e656ad7a4fb1323db476cd8f2cf6ac39',
    '7bf1ff4efdac6620edfbda328204ed16', '265848d4ecf46ff84e247d8b572af43b',
    '64e1ccf7bf450c9d591fab6d80f41847', '1edfaad0c87c90a26f1fb59fb5cbc983',
    'a22cd96f76784e01bf8f4e0c89433109', 'f30626309d8480ec14526323da68396d',
    '486b89c025c019b7f2b6c427a437811e', '2d865e51c4cf99a5b3a05d17e1d5bce0',
    'c70b931f12e33e65a564d5935d43b2d1', 'd8fe113b2a14b80603ca156e2ee0c990',
    '23ac878010450752bb1b1ca994edb56b', '15cce20e4302a42e1437f65fdf8fa667',
    '64b1cbec58d495ed42b3fbea94cac8e9', '22422e4eaca00ea54a0ac3e5fbcb2d8a',
    '0d1100deb68ce4cac3662968aa11c15c', '1e8bef4991bef4fbdb0ba8791829d8ed'
   ]);

-- ----------------------------------------------------------------------------
-- 4. Close out 2 of the 3 genuinely-new noisy fingerprints from the
--    2026-04-27 02:25 export. Both were classifier bypasses — the
--    iOS commit shipping with this migration routes them through
--    NetworkErrorClassifier.log so future occurrences won't fingerprint
--    on current builds.
--
--    The third (`3037a6f4` Exercise Library empty) stays visible for
--    human triage — it's a HIGH severity shake report that needs
--    investigation, not a noise downgrade.
-- ----------------------------------------------------------------------------

UPDATE bug_intelligence_fingerprints
   SET status                          = 'resolved',
       auto_resolved_reason            = 'code_fix:classifier_routing',
       auto_resolved_at                = COALESCE(auto_resolved_at, NOW()),
       resolved_at                     = COALESCE(resolved_at, NOW()),
       latest_resolving_migration_at   = COALESCE(latest_resolving_migration_at, NOW()),
       latest_resolving_migration_id   = COALESCE(latest_resolving_migration_id,
                                                  '20260627_bug_intel_auto_suppress_resolved_history'),
       updated_at                      = NOW()
 WHERE fingerprint IN (
    'ecca580f3e339245f1f88579b3dbefa2', -- Push 503 — PushNotificationService:93 routed through NetworkErrorClassifier
    'a47d011b84011282c7e81d7634bf76db'  -- Insights timeout — PersonalizedInsightsService:290 routed through NetworkErrorClassifier
 )
   AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

UPDATE bug_intelligence_reports r
   SET review_status = 'merged',
       review_notes  = COALESCE(review_notes, '')
                       || E'\n[2026-04-27 close-out] '
                       || 'Auto-merged by 20260627_bug_intel_auto_suppress_resolved_history.sql — '
                       || 'iOS code_fix:classifier_routing shipping in same commit prevents future fingerprinting.',
       reviewed_at   = COALESCE(reviewed_at, NOW())
 WHERE r.review_status IN ('pending', 'approved')
   AND r.fingerprint IN (
    'ecca580f3e339245f1f88579b3dbefa2',
    'a47d011b84011282c7e81d7634bf76db'
 );

-- ----------------------------------------------------------------------------
-- 5. Verify
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_returners_resolved INT;
    v_new_resolved       INT;
    v_remaining_open     INT;
BEGIN
    SELECT COUNT(*) INTO v_returners_resolved
      FROM bug_intelligence_fingerprints
     WHERE status = 'resolved'
       AND auto_resolved_reason LIKE 'auto_suppress_from_history:%'
       AND auto_resolved_at >= NOW() - INTERVAL '5 minutes';

    SELECT COUNT(*) INTO v_new_resolved
      FROM bug_intelligence_fingerprints
     WHERE fingerprint IN (
        'ecca580f3e339245f1f88579b3dbefa2',
        'a47d011b84011282c7e81d7634bf76db'
     )
       AND status = 'resolved';

    SELECT COUNT(*) INTO v_remaining_open
      FROM bug_intelligence_fingerprints
     WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate')
       AND last_seen_at >= NOW() - INTERVAL '24 hours';

    RAISE NOTICE '[20260627] Returners auto-suppressed via trigger: %', v_returners_resolved;
    RAISE NOTICE '[20260627] New fingerprints close-out resolved: % / 2', v_new_resolved;
    RAISE NOTICE '[20260627] Remaining open fingerprints (24h activity): %', v_remaining_open;
    RAISE NOTICE '✅ Phase 13 hardening installed: bug_intel_resolved_history is now '
                 'authoritative for "what has been fixed". Deleted-then-recreated '
                 'fingerprints can no longer leak through as new bugs. Past-grace '
                 'recurrences flip regressed_after_fix=TRUE instead of being hidden.';
END $$;

COMMIT;

-- Resolves: ecca580f3e339245f1f88579b3dbefa2 push notification 503 (classifier bypass fix)
-- Resolves: a47d011b84011282c7e81d7634bf76db insights fetch timeout (classifier bypass fix)
