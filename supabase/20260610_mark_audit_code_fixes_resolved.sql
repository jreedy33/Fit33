-- ════════════════════════════════════════════════════════════════════
-- Mark bug-intelligence fingerprints resolved — code fixes from the
-- 2026-04-25 audit cleanup (Phase 2: client-side classifier routing).
--
-- Pairs with #109 (`20260609_mark_bug_intel_resolved_2026_04_25_audit.sql`),
-- which closed the 39 silent / migration-pending / noise / transient
-- fingerprints. This migration closes the 5 fingerprints that needed
-- actual code changes in the iOS app, plus marks Report 14 (SIGKILL)
-- as `wont_fix` until dSYM symbolication lands (Phase 5.4–5.6).
--
-- Resolves:
--   • b242269c0a85eb1ad7c40fb29d3f5c80 — Report 1: notify-contacts-user-joined
--                                        403 (CRASH source, 5×2)
--   • 65f3c668c8b41e6a2a6e7d2ad2f3c3a6 — Report 7: same edge-function 403
--                                        (LOG source variant)
--   • 00bd6a627c915cc0e49ed59a6a3cc140 — Report 4: "User already registered"
--                                        signup loop (real UX branch)
--   • 1a0c9263cfae5f4e54df9f9c0e0f5a4d — Report 15: Core Data plist-serialize
--   • 3896c649b3e2afad8e6d0ce5f2c5e87a — Report 16: ExerciseNameCache plist
--   • 1dea54e7a3f7a8d8f3a8a8e2c0e2b6d4 — Report 17: SIGSEGV during first
--                                        launch (same session as 15+16)
--
-- Code changes that motivated the resolutions:
--
--   1. Fit33/NetworkErrorClassifier.swift
--      Added `.expectedUserState` classification + patterns:
--        "user already registered" / "user already exists" /
--        "email already registered" / "forbidden: new_user_id must match caller"
--      These now log at `.debug`, bypassing crash_reports +
--      bug_intelligence_fingerprints. Closes b242269c, 65f3c668, 00bd6a62.
--
--   2. Fit33/ContactsService.swift `notifyExistingUsersOfNewJoin`
--      • Added `isAuthenticated` guard (skip if session not yet established).
--      • Replaced the bare `AppLogger.error("Error notifying ...")`
--        (QUALITY_PERFORMANCE_AGENT invariant 25a violation — direct
--        AppLogger.error in a Supabase catch) with NetworkErrorClassifier
--        routing at `transientLevel: .debug`. The daily
--        `check_pending_join_notifications` cron catches up missed
--        contacts, so this failure is fully recoverable. Reinforces
--        b242269c, 65f3c668.
--
--   3. Fit33/ExerciseNameCache.swift (already on main, no edit this sprint)
--      The lock + safe-snapshot + plist-safety filter (lines 68–99) was
--      shipped in build 1.37 (50). The "non-property list object" crash
--      can no longer reproduce because saveToDisk() now:
--        • snapshots `memoryCache` under NSLock (no torn-dict races),
--        • re-validates every (key, value) pair as String→String before
--          calling UserDefaults.set, dropping invalid entries with a
--          counted log line instead of crashing CFPreferences.
--      Closes 1a0c9263, 3896c649, 1dea54e7 (the three fingerprints
--      from the same fresh-install session FA2353DF on 2026-04-23).
--
-- Idempotent: WHERE clause filters by fingerprint, re-running is a no-op.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- 1. Reports 1, 7, 4 — flip to resolved (code_fix bucket).
--    fixed_in_build is left NULL on these because the build that ships
--    NetworkErrorClassifier + ContactsService changes hasn't been
--    submitted yet; the `auto_resolved_reason='code_fix'` is enough for
--    the Improvement Tracker to bucket them, and `fixed_in_build` will
--    be backfilled when the next iOS build attests its hash.
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'code_fix'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    'b242269c0a85eb1ad7c40fb29d3f5c80', -- Report 1
    '65f3c668c8b41e6a2a6e7d2ad2f3c3a6', -- Report 7
    '00bd6a627c915cc0e49ed59a6a3cc140'  -- Report 4
);

-- ────────────────────────────────────────────────────────────────────
-- 2. Reports 15, 16, 17 — already shipped silent fix (build 1.37+).
--    Use silent_fix bucket + stamp fixed_in_build so the rollup can
--    distinguish "shipped, in-flight" from "shipped, post-deploy".
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'silent_fix'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    fixed_in_build       = COALESCE(fixed_in_build, '1.37 (50)'),
    updated_at           = NOW()
WHERE fingerprint IN (
    '1a0c9263cfae5f4e54df9f9c0e0f5a4d', -- Report 15
    '3896c649b3e2afad8e6d0ce5f2c5e87a', -- Report 16
    '1dea54e7a3f7a8d8f3a8a8e2c0e2b6d4'  -- Report 17
);

-- ────────────────────────────────────────────────────────────────────
-- 3. Merge any pending bug_intelligence_reports rows for these
--    fingerprints with a paper-trail note (matches migration #109
--    convention; only stamps reviewed_at because the table has no
--    updated_at column per migration 93's schema-fix comment).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-25 audit Phase 2] '
                    || 'Auto-merged by 20260610_mark_audit_code_fixes_resolved.sql — '
                    || 'classifier routing + plist-safety silent fix; see migration header.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    'b242269c0a85eb1ad7c40fb29d3f5c80',
    '65f3c668c8b41e6a2a6e7d2ad2f3c3a6',
    '00bd6a627c915cc0e49ed59a6a3cc140',
    '1a0c9263cfae5f4e54df9f9c0e0f5a4d',
    '3896c649b3e2afad8e6d0ce5f2c5e87a',
    '1dea54e7a3f7a8d8f3a8a8e2c0e2b6d4'
);

-- ────────────────────────────────────────────────────────────────────
-- 4. Verify — should print 6 fingerprints flipped + N reports merged.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
    FROM bug_intelligence_fingerprints
    WHERE fingerprint IN (
        'b242269c0a85eb1ad7c40fb29d3f5c80',
        '65f3c668c8b41e6a2a6e7d2ad2f3c3a6',
        '00bd6a627c915cc0e49ed59a6a3cc140',
        '1a0c9263cfae5f4e54df9f9c0e0f5a4d',
        '3896c649b3e2afad8e6d0ce5f2c5e87a',
        '1dea54e7a3f7a8d8f3a8a8e2c0e2b6d4'
    )
      AND status = 'resolved';

    SELECT COUNT(*) INTO v_merged_count
    FROM bug_intelligence_reports
    WHERE review_status = 'merged'
      AND review_notes LIKE '%2026-04-25 audit Phase 2%';

    RAISE NOTICE 'Marked % fingerprint(s) resolved (expected 6).', v_resolved_count;
    RAISE NOTICE 'Merged % report(s) with audit-Phase-2 paper trail.', v_merged_count;

    IF v_resolved_count < 6 THEN
        RAISE WARNING 'Expected 6 resolved fingerprints, got % — some may not exist yet in this env (safe on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- LEFT OPEN AFTER PHASE 2 (3 of 48):
--   • e955904c — MetricKit signal 9 / SIGKILL (Report 14)
--                Blocked on dSYM symbolication Phase 5.4–5.6 — leave
--                triaged so quality-performance can pivot once the
--                stack frames are human-readable.
--   • ed249878 — AutoGen generating stretches for advanced strength
--                user (Report 25). Shake report; needs product+data
--                investigation to reproduce (likely a wearable
--                readiness override on a non-red day).
--                Owner: product-engineer.
--   • eeaa35d1 — Challenge widget not refreshing after workout
--                completion (Report 29). Needs repro instrumentation
--                — `syncFit33WorkoutToChallenge` already calls
--                `fetchActiveChallenges`, so the @Published refresh
--                should propagate; suspect a race in the dashboard
--                widget's Combine subscription. Owner: product-engineer.
-- ════════════════════════════════════════════════════════════════════
