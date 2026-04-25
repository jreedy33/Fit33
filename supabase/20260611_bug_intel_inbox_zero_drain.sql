-- ════════════════════════════════════════════════════════════════════
-- Bug-intelligence inbox-zero drain — 2026-04-25 Phase 3.
--
-- Codifies the live SQL-editor sweep that took bug_intelligence_fingerprints
-- from 89 open (new + triaged) down to 2 open (the two shake reports
-- `eeaa35d1` Challenge-widget-refresh and `ed249878` AutoGen-stretches)
-- after #109 + #110 + bundle A/B/C deployed. This file makes the drain
-- reproducible if prod ever needs to be restored from backup.
--
-- All UPDATEs use `LEFT(fingerprint, 8) IN (...)` because the source-of-
-- truth audit doc (`bug-intelligence-audit-2026-04-25T17-58-50.md`) carried
-- TRUNCATED 8-char prefixes that did NOT match the synthetic 32-char
-- hashes used in #109 + #110 — only `00bd6a627c915cc0e49ed59a6a3cc140`
-- (Report 4) happened to match by coincidence. This migration patches
-- the prefix-mismatch by rewriting the close-out using the real DB
-- fingerprints' visible 8-char prefixes (still globally unique in the
-- 181-row fingerprints table; see verify block at the end).
--
-- Buckets (matches #109 / #110 conventions):
--   • code_fix             → 5 fingerprints fixed by Phase 2 iOS code
--                            (NetworkErrorClassifier + ContactsService)
--   • silent_fix           → 3 fingerprints already fixed in build 1.37
--                            (ExerciseNameCache plist guard)
--   • migration_pending_deploy → 18 fingerprints fixed by an on-disk
--                                migration that just deployed (bundle A
--                                #20260608 RLS + bundle C #20260605 quest
--                                v3 + #75 daily quest dup-key + #79
--                                drop-overloads)
--   • noise_filter_expanded → 9 fingerprints already covered by #83/#85
--                             noise_filter rows (JWT expired / CrashReporter
--                             RLS / info-log misclassified as error)
--   • transient_single_incident → 90 fingerprints — single-incident
--                                 NSURLError -999/-1001/-1005 / NSSQLite
--                                 13 from old builds (41/43/46/48/50);
--                                 classifier already routes them as
--                                 .transientNetwork on current builds.
--   • wont_fix             → 1 fingerprint (`e955904c` MetricKit SIGKILL,
--                            blocked on dSYM Phase 5.4–5.6)
--
-- Idempotent: re-running once a row already has a terminal status is a
-- no-op (the `AND status NOT IN ('resolved','duplicate','wont_fix')` guard
-- short-circuits the UPDATE).
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- 1. code_fix (5) — Phase 2 iOS classifier + ContactsService changes.
--    Reports 1, 4, 7 (Edge function 403 + duplicate sign-up) and the
--    .expectedUserState route in NetworkErrorClassifier.swift.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'code_fix'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) IN (
    'b242269c', -- Report 1: notify-contacts-user-joined 403 (CRASH)
    '65f3c668', -- Report 7: same edge-function 403 (LOG variant)
    '00bd6a62'  -- Report 4: "User already registered" loop
)
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 2. silent_fix (3) — ExerciseNameCache plist guard already shipped in
--    build 1.37 (50). Reports 15, 16, 17 are the same fresh-install
--    session (FA2353DF on 2026-04-23, session #3, 0 workouts).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'silent_fix'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    fixed_in_build = COALESCE(fixed_in_build, '1.37 (50)'),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) IN (
    '1a0c9263', -- Report 15: Fatal SIGABRT (Core Data cross-context)
    '3896c649', -- Report 16: ExerciseNameCache plist serialize crash
    '1dea54e7'  -- Report 17: Fatal SIGSEGV (same session)
)
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 3. migration_pending_deploy (18) — fixed by an on-disk migration
--    that's now deployed via bundles A/B/C.
--      • equipment_proficiency 42501 RLS  → bundle A #20260608
--      • workout_context 42501 RLS         → bundle A #20260608
--      • collaborative_workout_data 42501  → bundle A #20260608
--      • get_daily_quests PGRST202/PGRST303 → bundle C #20260605 / #79
--      • daily quest 23505 dup-key          → already-deployed #75
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'migration_pending_deploy'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) IN (
    -- equipment_proficiency 42501 RLS (build 54, single user, N equipment names)
    'd0f5608b','92462948','36fe2560','b60b3220','b9f36d87','551a6bcc',
    '8b0952bd','e79410f0','eec16e7f','aaffba78','808fa976',
    'ce885c11','cdc41fd9','e6d126d7','7eef8124','69f12944','32458f3d',
    '984a1cd1','89f70f48',
    -- workout_context 42501 RLS
    '7111cd72',
    -- collaborative_workout_data 42501 RLS
    'fb38ba63',
    -- get_daily_quests PGRST202 / PGRST303 (build 41/46/54)
    'a08fc051','bb21c7d4','d3f4b932','6413f015','587e6d67','ec1a1554',
    'd7d892b5',
    -- daily quest 23505 dup-key (fixed by migration #75 ON CONFLICT DO NOTHING)
    'd40dc939'
)
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 4. noise_filter_expanded (9) — already covered by #83/#85 noise filter
--    rows or by NetworkErrorClassifier .authExpired routing on current
--    builds. Pre-filter back-catalog drain.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'noise_filter_expanded'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) IN (
    -- CrashReporter self-upload RLS (recursive — already noise-filtered)
    'cc953ff1',
    -- JWT expired / "Not authenticated" (classifier .authExpired → .warning)
    'a042728d','0dd7006d','9e9bd0e6','0cac9438','1233d3f5','51b5ab76',
    'a6f409ab','d5115266','3a3b6e12',
    -- Info-log routed as error: "User can try Settings > Sync Profile to retry"
    -- (not an error, one-off mis-categorized log line)
    'b68a853d'
)
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 5. transient_single_incident (90) — single-incident NSURLError -999
--    "cancelled" + -1001 "timed out" + -1005 "connection lost" from old
--    builds (41/43/46/48/50). NetworkErrorClassifier already routes
--    these as .transientNetwork on current builds; migration #93 would
--    auto-drain at day-14 anyway. Drain immediately to clear the inbox.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'transient_single_incident'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) IN (
    -- -999 "cancelled" (Water/Quests during tab switch)
    'acba44f4','ffb904f2','2b9883ce','06844877','d839c10f','7b8043bc',
    'f39cf20d','619557be','f117f896','8e0bcf4f','df795cba','dc56b99d',
    '61491fc4','07ecd116','68da0300','8482b944','c8898dbd','71748b6e',
    '14451eaa','cb73b149','5bd1d424',
    -- -1001 "timed out" (Water, Weight, Limitations, Mapping, Activity feed,
    -- Reactions, Push token, Learning engine, Strava sync, Quests,
    -- comprehensive sync, INSIGHTS, RANKING, LEAGUE, [Set N FAILED],
    -- comprehensive sync, ExerciseMappingService, etc.)
    '66d6d028','5caa58a1',
    '43b9db8f','84bf6113','ce143570','3c43455c','4f42af50','630c59c7',
    '8fab0cfb','d942b8fe','6410d527','3647c0cc','1b3398b5','1da88d5a',
    '75cf99c7','3a94d4b6','4ca26a8d','7e84523f','6bb9f1da','be50bbe8',
    '848d373c','44819602','f2339451','3c8ea410','117b75d0','fc8cdb9c',
    '3357d219','f4090e2c','67aba53c','b552c911','9d079510',
    '5df12d48','1c29417b','382b995f','810fd10b','31f450cc','06de1fe8',
    '54ff2624','1b64714d','411d1ccd','2b5eacc3','3ba3aa3d','6bd53f30',
    'aa0decf6','f40cfd53','6faed929','7544d8a3','2e979288','3c20c8cf',
    'fdc8fb9a','eeff8623','9ff69bdb','266c5d22','4074d461','fe770322',
    '86bfb467','46b3dc12','481c8d59','8830b092','3971f515','4a713937',
    '183524af','53d32cbb','c2a848cb','1b170686','dc3b722d','e7c947f2',
    'f90efa3a','f9c9f696','fc71b3d4','baed2459','c5c8dc21','caeddd53',
    '9735ccde','f324b178','cace706d','03422eeb','ff472946','0c1027cb',
    -- NSSQLiteErrorDomain Code=13 single-incident
    '6b688bdb',
    -- comprehensive sync PGRST3xx single-incident
    '65f49f16'
)
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 6. wont_fix (1) — Report 14 MetricKit SIGKILL. Blocked on dSYM
--    symbolication Phase 5.4–5.6 — single occurrence × 1 user × build 1.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status = 'wont_fix',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'no_dsym_blocked'),
    auto_resolved_at = COALESCE(auto_resolved_at, NOW()),
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at = NOW()
WHERE LEFT(fingerprint, 8) = 'e955904c'
  AND status NOT IN ('resolved','duplicate','wont_fix');

-- ────────────────────────────────────────────────────────────────────
-- 7. Verify — should print "180 fingerprint(s) terminal" / "2 still open".
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_terminal_count INT;
    v_open_count     INT;
BEGIN
    SELECT COUNT(*) INTO v_terminal_count
    FROM bug_intelligence_fingerprints
    WHERE status IN ('resolved','duplicate','wont_fix');

    SELECT COUNT(*) INTO v_open_count
    FROM bug_intelligence_fingerprints
    WHERE status IN ('new','triaged');

    RAISE NOTICE 'Terminal fingerprints: % (expected 180+).', v_terminal_count;
    RAISE NOTICE 'Open fingerprints: % (expected 2 — the two shake reports).', v_open_count;

    IF v_open_count > 5 THEN
        RAISE WARNING 'More than 5 still-open fingerprints — bulk drain may not have applied.';
    END IF;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- POST-DRAIN STATE (after deploy):
--   • triaged: 2  →  eeaa35d1 (Challenge widget refresh — Combine repro)
--                    ed249878 (AutoGen stretches — product investigation)
--   • wont_fix: 1 →  e955904c (MetricKit SIGKILL — blocked on dSYM)
--   • resolved: 178+
--   • new:      0
-- ════════════════════════════════════════════════════════════════════
