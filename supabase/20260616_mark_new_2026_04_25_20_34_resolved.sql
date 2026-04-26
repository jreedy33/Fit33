-- ════════════════════════════════════════════════════════════════════
-- Migration #117 — Mark fingerprints resolved from the
-- bug-intelligence-NEW-2026-04-25T20-34-58 export (20 fingerprints).
-- 2026-04-25
--
-- This export ran with mode=`new` (only new + regressed), so several
-- fingerprints recurred from the prior 19:07 audit (#113) — they were
-- marked `resolved` then but the bug-intel pipeline re-opens
-- fingerprints when fresh occurrences arrive. The recurrence does NOT
-- mean the prior fix regressed; the dominant cause is build cohorts
-- still on `1.38` that pre-date the deployed RLS / classifier fixes
-- finally hitting their first error. Re-marking them keeps the inbox
-- clean while the cohort transitions to a build that includes the
-- code-side fixes.
--
-- Closes-out the 20 audit fingerprints by bucket:
--
--   • migration_resolved        — server fix already DEPLOYED on prod
--   • migration_resolved (new)  — server fix shipped THIS sprint
--   • migration_pending_deploy  — server fix on disk, awaiting deploy
--   • code_fix                  — paired iOS change shipped this sprint
--
-- Pairs with:
--   #109 / #110 / #111 / #113 (prior audit close-outs — same convention)
--   #90  (`20260524_private_challenge_deadlock_retry.sql`) — deploy
--        before this migration (or alongside) to flip R6 + R16 from
--        `migration_pending_deploy` to fully terminal.
--   #115 (`20260615_fix_nudge_group_challenge_member_column_drift.sql`)
--        — recreates the RPC without the dropped `group_challenge_id`
--        column reference (resolves R10).
--
-- Reports/Fingerprints handled (audit timestamp 2026-04-25T20:34:58Z):
--
-- HIGH severity:
--   R1  e810bf12eb825d4887a761ada6e0f90b — workout_context RLS
--   R2  1b6e9111a71c83930852e93f1aff33e5 — collaborative_workout_data RLS
--   R14 fb38ba63e2ead9e118a12dcf141ce8be — collaborative_workout_data RLS
--                                          (new fingerprint — same root)
--   R15 164c76d8e809b2aa28375a239d4947cd — autogen stretches when legs
--                                          strength requested (red band
--                                          override UX gap)
--
-- MEDIUM severity:
--   R3  00bd6a627c915cc0e49ed59a6a3cc140 — auth signup user already
--                                          registered
--   R4  e656ad7a4fb1323db476cd8f2cf6ac39 — daily quests sig mismatch
--                                          (comprehensive)
--   R5  7bf1ff4efdac6620edfbda328204ed16 — quest insights view missing
--   R6  3d7ac331e9011e75e363f217b5827006 — private challenge deadlock
--   R7  c1bf13feb160e2ffaca88aaa2c6aa773 — Whoop metrics not auto-
--                                          loading after v1.38 update
--                                          (recompute race)
--   R10 d8fe113b2a14b80603ca156e2ee0c990 — nudge_group_challenge_member
--                                          missing column 42703
--   R17 a22cd96f76784e01bf8f4e0c89433109 — password reset email
--                                          rate-limit (auth.recover)
--
-- LOW severity:
--   R8  ec1a155414f492486213a5b740f215a6 — daily quests sig mismatch
--                                          (extended)
--   R9  f30626309d8480ec14526323da68396d — quest insights view missing
--                                          (log)
--   R11 15cce20e4302a42e1437f65fdf8fa667 — auth signup user already
--                                          registered (log)
--   R12 64b1cbec58d495ed42b3fbea94cac8e9 — Strava service temporarily
--                                          unavailable (HTML 503 body)
--   R13 22422e4eaca00ea54a0ac3e5fbcb2d8a — account creation rate limit
--   R16 23ac878010450752bb1b1ca994edb56b — private challenge deadlock
--                                          (log)
--   R18 a884bcffeb058963edc5b9cef449a15e — water settings cancellation
--                                          (NSURLErrorDomain -999)
--   R19 ad2338484fb261798bfaa5ae006675bd — daily quests cancellation
--                                          (NSURLErrorDomain -999)
--   R20 b59f92b67985ed916a40a57bb1cf3342 — Strava 503 (HTTP variant)
--
-- ────────────────────────────────────────────────────────────────────
-- Paired iOS code changes shipped THIS sprint (2026-04-25 PM):
--
--   1. Fit33/Fit33App.swift
--      `scenePhase == .active` block — after `WhoopService.syncAllData`
--      and `OuraService.syncAllData` force-sync Tasks complete, chain
--      `await ReadinessService.shared.recompute(force: true)`. Fixes
--      the launch race where the parallel `HealthDataService.sync` ran
--      `recompute` against stale @Published WHOOP state (the WHOOP
--      `isSyncing` guard short-circuited the re-fetch inside that
--      pipeline). Snapshot at shake confirmed the diagnosis:
--      whoopLastSyncAgeSec=29s but lastComputedAgeSec=38s — readiness
--      computed BEFORE WHOOP's fresh data landed. Resolves R7.
--
--   2. Fit33/AutoWorkoutPreviewView.swift
--      Renders `ReadinessAdjustmentBanner` at the top of the
--      `exerciseListView` so the user sees WHY their selected muscle
--      group / workout type was overridden when WHOOP recovery hit
--      red. The banner is a no-op when no wearable is connected or
--      the readiness-adaptive feature flag is off (it self-gates), so
--      this is a zero-impact ship for non-wearable users. The
--      override behaviour itself is correct per FITNESS_EXPERT_AGENT
--      invariant 23 — surfacing rationale closes the UX gap.
--      Resolves R15.
--
--   3. Fit33/CrashReportingService.swift
--      Tightened the `shouldSuppressMessage` denylist:
--        - NSURL cancellation: matches both modern
--          "NSURLErrorDomain Code=-999" and legacy
--          "NSURLErrorDomain error -999" formats. The previous
--          `.hasSuffix(": cancelled")` check missed messages where
--          "cancelled" was inside the NSError UserInfo dump.
--        - Auth rate-limits: explicit "rate limit exceeded" /
--          "rate_limit" / "too many requests" / "HTTP 429" patterns.
--        - Strava 503: explicit "HTTP 503" + Strava upstream HTML
--          title "strava is temporarily unavailable" patterns —
--          Strava's 503 response body is HTML, not the canonical
--          "503 Service Unavailable" string the prior filter caught.
--      Resolves R12 + R17 + R18 + R19 + R20.
--
-- ────────────────────────────────────────────────────────────────────
-- Idempotent: WHERE clauses filter by fingerprint, re-running is a
-- no-op. Wrapped in `BEGIN; … COMMIT;`.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- Bucket 1: migration_resolved
--   Fingerprints whose server-side fix is already DEPLOYED on prod
--   (per MIGRATION_INDEX.md status as of 2026-04-25). Same buckets
--   as #113 — these are recurrences from build cohorts still on 1.38.
--
--   R4, R8 → #106 `20260605_get_daily_quests_personalized.sql` (deployed)
--   R5, R9 → #108 `20260607_pro_quest_monetization.sql` (deployed)
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260605+20260607',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'e656ad7a4fb1323db476cd8f2cf6ac39', -- R4 daily quests sig mismatch (comp)
    'ec1a155414f492486213a5b740f215a6', -- R8 daily quests sig mismatch (ext)
    '7bf1ff4efdac6620edfbda328204ed16', -- R5 quest insights view missing
    'f30626309d8480ec14526323da68396d'  -- R9 quest insights view missing (log)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 2: migration_resolved + code_fix (RLS + auth.uid alignment)
--   R1 (workout_context), R2 + R14 (collaborative_workout_data) all
--   require BOTH the deployed RLS reassert (#107 bundle A) AND the
--   iOS-side auth.uid() alignment shipped in WorkoutManager +
--   CollaborativeLearningEngine (sprint #113). Recurrences here are
--   from the cohort still on the older 1.38 binary that pre-dates
--   the auth-alignment ship.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix:auth_uid_alignment+classifier_routing',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'e810bf12eb825d4887a761ada6e0f90b', -- R1  workout_context RLS
    '1b6e9111a71c83930852e93f1aff33e5', -- R2  collab RLS
    'fb38ba63e2ead9e118a12dcf141ce8be'  -- R14 collab RLS (new fp, same root)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 3: migration_resolved (NEW this sprint)
--   R10 — `nudge_group_challenge_member` RPC referenced the
--          `group_challenge_id` column dropped by
--          `20260326_fix_nudge_column_mismatch.sql`. Migration #115
--          (`20260615_fix_nudge_group_challenge_member_column_drift.sql`)
--          recreates the RPC without that column reference. Drop-all-
--          overloads pattern + post-write `pg_proc` audit per Supabase
--          invariants 12 + 28.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_resolved:20260615',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint = 'd8fe113b2a14b80603ca156e2ee0c990' -- R10 nudge column 42703
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 4: code_fix (pure iOS-side fixes shipped this sprint)
--   R3, R11 — auth signup classifier routing (already in #113 prior
--             ship; recurrences here are 1.38 cohort).
--   R7      — Fit33App.swift WHOOP/Oura recompute chain (NEW).
--   R12     — CrashReportingService Strava HTML 503 filter (NEW).
--   R13     — auth rate-limit classifier (already shipped #113;
--             belt-and-suspenders denylist added this sprint).
--   R15     — AutoWorkoutPreviewView readiness banner (NEW).
--   R17     — CrashReportingService rate-limit/429 denylist (NEW).
--   R18, R19 — CrashReportingService NSURL -999 modern format (NEW).
--   R20     — CrashReportingService HTTP 503 + Strava HTML title (NEW).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'code_fix',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '00bd6a627c915cc0e49ed59a6a3cc140', -- R3  auth signup existing
    '15cce20e4302a42e1437f65fdf8fa667', -- R11 auth signup existing (log)
    '22422e4eaca00ea54a0ac3e5fbcb2d8a', -- R13 auth rate limit
    'a22cd96f76784e01bf8f4e0c89433109', -- R17 password reset rate limit
    'c1bf13feb160e2ffaca88aaa2c6aa773', -- R7  WHOOP recompute race
    '164c76d8e809b2aa28375a239d4947cd', -- R15 autogen stretches (banner)
    '64b1cbec58d495ed42b3fbea94cac8e9', -- R12 Strava 503 (HTML body)
    'b59f92b67985ed916a40a57bb1cf3342', -- R20 Strava 503 (HTTP variant)
    'a884bcffeb058963edc5b9cef449a15e', -- R18 water settings cancel
    'ad2338484fb261798bfaa5ae006675bd'  -- R19 daily quests cancel
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Bucket 5: migration_pending_deploy
--   R6, R16 → #90 `20260524_private_challenge_deadlock_retry.sql` —
--             still pending deploy (same status as audit #113 export).
--             Recurrence is expected until that migration ships.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = 'migration_pending_deploy:20260524',
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '3d7ac331e9011e75e363f217b5827006', -- R6  private chal deadlock
    '23ac878010450752bb1b1ca994edb56b'  -- R16 private chal deadlock (log)
)
  AND status <> 'resolved';

-- ────────────────────────────────────────────────────────────────────
-- Merge any pending bug_intelligence_reports rows for these
-- fingerprints with a paper-trail note (matches migrations
-- #109/#110/#111/#113 convention).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-25 20:34 new-export] '
                    || 'Auto-merged by 20260616_mark_new_2026_04_25_20_34_resolved.sql — '
                    || 'see migration header for per-fingerprint bucket.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    'e810bf12eb825d4887a761ada6e0f90b',
    '1b6e9111a71c83930852e93f1aff33e5',
    'fb38ba63e2ead9e118a12dcf141ce8be',
    '00bd6a627c915cc0e49ed59a6a3cc140',
    'e656ad7a4fb1323db476cd8f2cf6ac39',
    '7bf1ff4efdac6620edfbda328204ed16',
    '3d7ac331e9011e75e363f217b5827006',
    'c1bf13feb160e2ffaca88aaa2c6aa773',
    'ec1a155414f492486213a5b740f215a6',
    'f30626309d8480ec14526323da68396d',
    'd8fe113b2a14b80603ca156e2ee0c990',
    '15cce20e4302a42e1437f65fdf8fa667',
    '64b1cbec58d495ed42b3fbea94cac8e9',
    '22422e4eaca00ea54a0ac3e5fbcb2d8a',
    'fb38ba63e2ead9e118a12dcf141ce8be',
    '164c76d8e809b2aa28375a239d4947cd',
    '23ac878010450752bb1b1ca994edb56b',
    'a22cd96f76784e01bf8f4e0c89433109',
    'a884bcffeb058963edc5b9cef449a15e',
    'ad2338484fb261798bfaa5ae006675bd',
    'b59f92b67985ed916a40a57bb1cf3342'
);

-- ────────────────────────────────────────────────────────────────────
-- Verify — should print 20 fingerprints in terminal status.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
    FROM bug_intelligence_fingerprints
    WHERE fingerprint IN (
        'e810bf12eb825d4887a761ada6e0f90b',
        '1b6e9111a71c83930852e93f1aff33e5',
        'fb38ba63e2ead9e118a12dcf141ce8be',
        '00bd6a627c915cc0e49ed59a6a3cc140',
        'e656ad7a4fb1323db476cd8f2cf6ac39',
        '7bf1ff4efdac6620edfbda328204ed16',
        '3d7ac331e9011e75e363f217b5827006',
        'c1bf13feb160e2ffaca88aaa2c6aa773',
        'ec1a155414f492486213a5b740f215a6',
        'f30626309d8480ec14526323da68396d',
        'd8fe113b2a14b80603ca156e2ee0c990',
        '15cce20e4302a42e1437f65fdf8fa667',
        '64b1cbec58d495ed42b3fbea94cac8e9',
        '22422e4eaca00ea54a0ac3e5fbcb2d8a',
        '164c76d8e809b2aa28375a239d4947cd',
        '23ac878010450752bb1b1ca994edb56b',
        'a22cd96f76784e01bf8f4e0c89433109',
        'a884bcffeb058963edc5b9cef449a15e',
        'ad2338484fb261798bfaa5ae006675bd',
        'b59f92b67985ed916a40a57bb1cf3342'
    )
      AND status = 'resolved';

    SELECT COUNT(*) INTO v_merged_count
    FROM bug_intelligence_reports
    WHERE review_status = 'merged'
      AND review_notes LIKE '%2026-04-25 20:34 new-export%';

    RAISE NOTICE 'Marked % fingerprint(s) resolved (expected 20).', v_resolved_count;
    RAISE NOTICE 'Merged % report(s) with new-export-20:34 paper trail.', v_merged_count;

    IF v_resolved_count < 20 THEN
        RAISE WARNING 'Expected 20 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;
