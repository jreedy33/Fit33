-- ════════════════════════════════════════════════════════════════════
-- Mark bug-intelligence fingerprints resolved — 2026-04-25 17:58 audit.
--
-- Source: bug-intelligence-audit-2026-04-25T17-58-50.md (48 reports).
--
-- This is the second-pass cleanup that runs alongside migration 91
-- (20260525_mark_bug_intel_resolved_2026_04_25.sql, the 13:16 export
-- sweep). The 17:58 export was generated AFTER 91 was authored but
-- BEFORE it deployed, so most of the 48 reports here are either:
--   (a) silent-fixed by a migration on disk that hasn't deployed yet,
--   (b) noise-filtered by 83 / 85 once the noise_filter table catches up,
--   (c) single-incident transients that the new auto-drainer 93 will
--       catch on day-14, OR
--   (d) duplicates of a fingerprint already in 91.
-- Marking them resolved here keeps the inbox honest while the deploy
-- train (75/77/78/81/82/83/85/89/90/91/93/95/106/108/20260608) catches up.
--
-- Idempotent: WHERE clause filters by fingerprint, so re-running this
-- once a row already has status='resolved' is a no-op.
-- ════════════════════════════════════════════════════════════════════
--
-- RESOLVED — silent-fixed by an already-deployed migration (status emoji
-- ✅ in MIGRATION_INDEX.md):
--   • bb8db6c1 — Daily Quest dup-key 23505 (Report 28)
--                Fixed by #75 `20260509b_get_daily_quests_has_wearable_body.sql`
--                (deployed 2026-04-23): added `ON CONFLICT (user_id, quest_date,
--                quest_key) DO NOTHING` to user_daily_quests insert.
--   • e3388d03 — friend_activity_feed cardio_completed 23514 (Report 18)
--   • b66f6c07 — same constraint, log-source variant (Report 26)
--                Both fixed by #81 `20260515_friend_activity_feed_cardio_check.sql`
--                (deployed 2026-04-23): added 'cardio_completed' to the
--                friend_activity_feed_activity_type_check allow-set.
--
-- RESOLVED — silent-fixed by a 🆕 Ready migration on disk (deploys
-- alongside this cleanup pass):
--   • 1b6e9111 — collaborative_workout_data RLS (Report 2)
--   • e810bf12 — workout_context RLS (Report 3)
--   • 1b5116cd — CrashReporter `crash_reports` RLS (Report 9)
--                All three fixed by 20260608_workout_intelligence_rls_audit.sql:
--                root cause was Core Data `User.id` generating a fresh UUID
--                during onboarding instead of using `auth.uid()` (fixed in
--                Fit33/UserManager.swift) + RLS policies re-asserted across
--                the eight workout intelligence tables.
--   • 5b97a3bc — step_tracking RLS (Report 12)
--   • 7f062850 — Health step sync RLS, log variant (Report 13)
--                Same UUID-mismatch root cause; the `step_tracking` writes
--                go through the same Core Data `User.id` path. Last seen
--                build 1.37, which matches the build_freshness=0.5 floor.
--   • 3d7ac331 — Private challenge progress deadlock (Report 8)
--   • 23ac8780 — Same deadlock, log variant (Report 22)
--                Both fixed by #90 `20260524_private_challenge_deadlock_retry.sql`
--                (Resolves: directive added in same sprint).
--   • e656ad7a — get_daily_quests PGRST202 (extended error, Report 5)
--   • 486b89c0 — Same, log variant (Report 20)
--                Both fixed by #106 `20260605_get_daily_quests_personalized.sql`
--                (drops every prior overload, recreates with the v3 19-arg
--                body). PGRST202 surfaced only because the 9 new params
--                temporarily had no matching server function.
--   • 7bf1ff4e — v_user_quest_personalization_summary missing (Report 6)
--   • f3062630 — Same, log variant (Report 11)
--                Both created by #108 `20260607_pro_quest_monetization.sql`
--                (the view is part of the Smart Adaptive Daily Goals deploy).
--
-- RESOLVED — noise-filtered (handled by tier=hard rows seeded in
-- migrations 83 + 85; will not re-fingerprint after deploy):
--   • 97f51f02 — Watchdog "main thread blocked >30s" (Report 10)
--   • 18ff0951 — Same watchdog, distinct fingerprint (Report 24)
--                Filtered by 83's `watchdog_*` tier=hard rows. The
--                AppPerformanceSystem watchdog logs are a performance
--                signal, not a bug — they will continue to fire on iOS
--                lifecycle freezes (debugger pauses, OS thermals) but
--                are dropped before fingerprinting.
--   • a580c35a — 502 from get_my_activity_reactions (Report 19)
--                Filtered by 83's `cloudflare_5xx` rows + the classifier
--                already routes 502/503/504 as transientNetwork.
--   • 9a4b5b9e — JWT expired during challenge progress (Report 27)
--                Filtered by 83's P0001 rows + classifier routes
--                "JWT expired" as authExpired (warning, not error).
--
-- RESOLVED — single-incident transient network errors (will be caught
-- by 93 `bug_intel_resolve_single_incident_transients` on day-14 of
-- last_seen, but no reason to wait two weeks):
--   • 22422e4e — Auth rate limit during account creation (Report 23)
--   • 0080557f — Password reset rate limit, build 1.32 (Report 30)
--   • 1edfaad0 — Password reset rate limit simplified (Report 31)
--   • a22cd96f — Password reset rate limit failure (Report 32)
--                All three of 30/31/32 are 0-user fingerprints from a
--                build (1.32) that has 0 active users today.
--   • a884bcff — Water settings cancelled during tab switch (Report 33)
--   • 6121691f — Weight logs 502 (Report 34)
--   • 90386263 — Profile sync retry triggered (Report 35)
--   • 1fb4a278 — Weight logs 502 variant (Report 36)
--   • b706265b — Network connection lost during favorites sync (Report 37)
--   • ad233848 — Daily quests cancelled during tab switch (Report 38)
--   • 4ba1e2c3 — Exercise history save timeout (Report 39)
--   • c46485c6 — Strava sync timeout (Report 40)
--   • b6a8bec9 — Push notification token save timeout (Report 41)
--   • 5c4c3e1f — Exercise mapping timeout (Report 42)
--   • 52d0423e — Daily quests RPC timeout on dashboard (Report 43)
--   • 3a510abf — Hydration logs API timeout on dashboard (Report 44)
--   • a28bc5f8 — Ranked friends timeout during dashboard load (Report 45)
--   • 18a4b0fc — Insights streak fetch fails when offline (Report 46)
--   • 3d3e3978 — Water settings update fails offline (Report 47)
--   • bd382acb — Water streaks load cancelled, log variant (Report 48)
--                All 33–48 are 1-occurrence × 1-user transient
--                NSURLError / 502 / cancelled / timeout signals on build
--                1.37 (or older). The classifier already routes them
--                as transientNetwork at .warning post-deploy of #83/#85;
--                marking resolved here drains the back-catalog.
--
-- RESOLVED — duplicate of a fingerprint already counted above (the log
-- variant of a crash variant, etc.). The dup-fingerprints list is
-- intentionally explicit so a future audit doesn't have to re-derive
-- the duplication graph:
--   • 15cce20e — Duplicate sign-up log entries (Report 21)
--                Same root cause as Report 4 (`00bd6a62`), but Report 4
--                is LEFT OPEN below for product-engineer follow-up;
--                the LOG version is just classifier noise from
--                SupabaseManager retrying. Resolved here, parent open.
--
-- LEFT OPEN (8) — NOT marked resolved here. These are real bugs (or
-- need a code fix beyond the scope of a SQL cleanup pass):
--   • b242269c — Edge function 403 for notify-contacts-user-joined
--                (Report 1, 5 occurrences × 2 users, CRASH source).
--                Routes through ContactsService.swift:659 with
--                AppLogger.error directly — invariant 25a violation
--                (classifier bypass). Needs an `isAuthenticated` guard
--                + classifier route + edge function auth review.
--                Owner: infra-security.
--   • 65f3c668 — Same edge function 403, log-source variant (Report 7)
--                Sibling of Report 1; left open with parent.
--   • 00bd6a62 — Duplicate sign-up "User already registered"
--                (Report 4). Real UX bug — onboarding doesn't gracefully
--                handle "this email already has an account" and silently
--                retries. Needs SupabaseManager.swift signup path to
--                detect AuthError.userAlreadyExists and route to login.
--                Owner: product-engineer.
--   • e955904c — MetricKit signal 9 / SIGKILL (Report 14)
--                Single occurrence, no_dsym. Build 1.39. OS-initiated
--                termination (memory / background time / health
--                exception). Leaving open until dSYM symbolication
--                Phase 5.4–5.6 catches up so we can tell whether this
--                was a watchdog freeze or a memory crash.
--                Owner: quality-performance.
--   • 1a0c9263 — Core Data cross-context relationship crash (Report 15)
--   • 3896c649 — ExerciseNameCache property-list serialization
--                (Report 16). NSInvalidArgumentException: attempting to
--                insert NSManagedObject into UserDefaults plist.
--   • 1dea54e7 — SIGSEGV during first app launch (Report 17)
--                All three are the SAME session
--                (FA2353DF-BDBA-479B-86BB-AB0CED005A98 on 2026-04-23
--                03:32:27, fresh install, session #3, 0 workouts). Real
--                bug — the cache is trying to put Core Data managed
--                objects into UserDefaults. Needs a guard in
--                ExerciseNameCache.saveToDisk + JSONSerialization
--                isValidJSONObject check. Owner: data-backend.
--   • ed249878 — AutoGen generating stretches instead of strength
--                exercises for advanced user (Report 25). Shake report,
--                product bug. Owner: product-engineer.
--   • eeaa35d1 — Challenge widget not updating after workout completion
--                (Report 29). Shake report, UX bug — same one left open
--                by migration 91. Owner: product-engineer.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- 1. Flip status='resolved' on the 39 silent-fixed fingerprints.
--    auto_resolved_reason annotates which bucket each fell into so
--    the CMS Improvement Tracker counts them correctly (silent_fix vs
--    noise_filter_expanded vs transient_single_incident vs
--    migration_resolved).
-- ────────────────────────────────────────────────────────────────────

-- Bucket A: deployed-migration silent fix
UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'silent_fix'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    fixed_in_build       = COALESCE(fixed_in_build, '1.38 (51)'),
    updated_at           = NOW()
WHERE fingerprint IN (
    'bb8db6c13848652a253a41efbadc871d', -- Report 28 → migration 75
    'e3388d0313f3684927989494c3c72464', -- Report 18 → migration 81
    'b66f6c070ced888a9dc85867ec79ed1b'  -- Report 26 → migration 81
);

-- Bucket B: 🆕 Ready migration on disk silent fix (auto_resolved_reason
-- distinguishes "fix is committed but not yet deployed" from "fix
-- already shipped"; the next deploy turns these into hard truths).
UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'migration_pending_deploy'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    -- Reports 2, 3, 9 → 20260608 (workout intelligence RLS audit)
    '1b6e9111a71c83930852e93f1aff33e5',
    'e810bf12eb825d4887a761ada6e0f90b',
    '1b5116cd10eb5a9c3e903bd3def97592',
    -- Reports 12, 13 → same UUID-mismatch root cause
    '5b97a3bcdc24d7cb1ed70d8609c8d6b2',
    '7f0628508cb50b9ca5be19dde3536fc1',
    -- Reports 8, 22 → migration 90 (private challenge deadlock retry)
    '3d7ac331e9011e75e363f217b5827006',
    '23ac878010450752bb1b1ca994edb56b',
    -- Reports 5, 20 → migration 106 (get_daily_quests v3)
    'e656ad7a4fb1323db476cd8f2cf6ac39',
    '486b89c025c019b7f2b6c427a437811e',
    -- Reports 6, 11 → migration 108 (creates v_user_quest_personalization_summary)
    '7bf1ff4efdac6620edfbda328204ed16',
    'f30626309d8480ec14526323da68396d'
);

-- Bucket C: noise-filtered by 83 / 85 noise_filter rows
UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'noise_filter_expanded'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    '97f51f027eb90d963fd22675590ad3bb', -- Report 10 — watchdog
    '18ff0951f7151b55cb7bbe25d0a72d19', -- Report 24 — watchdog dup
    'a580c35a1ea16b28e9cf79bb56a8788b', -- Report 19 — Cloudflare 502
    '9a4b5b9e58d06c908692f28684a024f1'  -- Report 27 — JWT expired transient
);

-- Bucket D: single-incident transient network noise (would auto-resolve
-- via 93 on day-14, marking now to drain the audit immediately).
UPDATE bug_intelligence_fingerprints
SET status               = 'resolved',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'transient_single_incident'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint IN (
    -- Reports 23, 30, 31, 32 — auth / password rate limits
    '22422e4eaca00ea54a0ac3e5fbcb2d8a',
    '0080557f0dc278d22c345638b8e7d280',
    '1edfaad0c87c90a26f1fb59fb5cbc983',
    'a22cd96f76784e01bf8f4e0c89433109',
    -- Reports 33–48 — single-occurrence transient network/timeout/cancelled
    'a884bcffeb058963edc5b9cef449a15e',
    '6121691fd4ebfc9ca28b56e5f919b865',
    '90386263253e07724dae0af4adafd574',
    '1fb4a278f13adafd8acb2e9cf77470b2',
    'b706265b818c1b0c6ef8938e81142d71',
    'ad2338484fb261798bfaa5ae006675bd',
    '4ba1e2c3d9af2e2a2544d3e972dad671',
    'c46485c6a966d1890a5131fdf969e345',
    'b6a8bec9302467aec7f86cc83c1d2090',
    '5c4c3e1f4c2d46a9d049112e9ffb5f2c',
    '52d0423e83c1844095e0bd9e0531aeee',
    '3a510abf019dcf2838f80003ec3c0469',
    'a28bc5f83b1f6138fa52209670ce6f33',
    '18a4b0fc76b0cf6a17702443b82feb15',
    '3d3e397881fa4624f26384c1e69962cf',
    'bd382acbe87d224cf88183e36318ab47'
);

-- Bucket E: duplicate of a fingerprint left open above
UPDATE bug_intelligence_fingerprints
SET status               = 'duplicate',
    duplicate_of         = '00bd6a627c915cc0e49ed59a6a3cc140',
    auto_resolved_reason = COALESCE(auto_resolved_reason, 'duplicate'),
    auto_resolved_at     = COALESCE(auto_resolved_at, NOW()),
    resolved_at          = COALESCE(resolved_at, NOW()),
    updated_at           = NOW()
WHERE fingerprint = '15cce20e4302a42e1437f65fdf8fa667';

-- ────────────────────────────────────────────────────────────────────
-- 2. Merge any pending bug_intelligence_reports for the resolved
--    fingerprints with a paper-trail note (matches migration 91/93/95
--    convention — only stamps `reviewed_at` because the table has no
--    `updated_at` column per migration 93's schema-fix comment).
-- ────────────────────────────────────────────────────────────────────

UPDATE bug_intelligence_reports r
SET review_status = 'merged',
    review_notes  = COALESCE(review_notes, '')
                    || E'\n[2026-04-25 17:58 audit cleanup] '
                    || 'Auto-merged by 20260609_mark_bug_intel_resolved_2026_04_25_audit.sql — '
                    || 'fingerprint flipped to resolved/duplicate; see migration header for bucket rationale.',
    reviewed_at   = COALESCE(reviewed_at, NOW())
WHERE r.review_status IN ('pending', 'approved')
  AND r.fingerprint IN (
    -- Bucket A
    'bb8db6c13848652a253a41efbadc871d',
    'e3388d0313f3684927989494c3c72464',
    'b66f6c070ced888a9dc85867ec79ed1b',
    -- Bucket B
    '1b6e9111a71c83930852e93f1aff33e5',
    'e810bf12eb825d4887a761ada6e0f90b',
    '1b5116cd10eb5a9c3e903bd3def97592',
    '5b97a3bcdc24d7cb1ed70d8609c8d6b2',
    '7f0628508cb50b9ca5be19dde3536fc1',
    '3d7ac331e9011e75e363f217b5827006',
    '23ac878010450752bb1b1ca994edb56b',
    'e656ad7a4fb1323db476cd8f2cf6ac39',
    '486b89c025c019b7f2b6c427a437811e',
    '7bf1ff4efdac6620edfbda328204ed16',
    'f30626309d8480ec14526323da68396d',
    -- Bucket C
    '97f51f027eb90d963fd22675590ad3bb',
    '18ff0951f7151b55cb7bbe25d0a72d19',
    'a580c35a1ea16b28e9cf79bb56a8788b',
    '9a4b5b9e58d06c908692f28684a024f1',
    -- Bucket D
    '22422e4eaca00ea54a0ac3e5fbcb2d8a',
    '0080557f0dc278d22c345638b8e7d280',
    '1edfaad0c87c90a26f1fb59fb5cbc983',
    'a22cd96f76784e01bf8f4e0c89433109',
    'a884bcffeb058963edc5b9cef449a15e',
    '6121691fd4ebfc9ca28b56e5f919b865',
    '90386263253e07724dae0af4adafd574',
    '1fb4a278f13adafd8acb2e9cf77470b2',
    'b706265b818c1b0c6ef8938e81142d71',
    'ad2338484fb261798bfaa5ae006675bd',
    '4ba1e2c3d9af2e2a2544d3e972dad671',
    'c46485c6a966d1890a5131fdf969e345',
    'b6a8bec9302467aec7f86cc83c1d2090',
    '5c4c3e1f4c2d46a9d049112e9ffb5f2c',
    '52d0423e83c1844095e0bd9e0531aeee',
    '3a510abf019dcf2838f80003ec3c0469',
    'a28bc5f83b1f6138fa52209670ce6f33',
    '18a4b0fc76b0cf6a17702443b82feb15',
    '3d3e397881fa4624f26384c1e69962cf',
    'bd382acbe87d224cf88183e36318ab47',
    -- Bucket E
    '15cce20e4302a42e1437f65fdf8fa667'
);

-- ────────────────────────────────────────────────────────────────────
-- 3. Verify — should print 39 fingerprints flipped + N reports merged.
-- ────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_resolved_count INT;
    v_merged_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_resolved_count
    FROM bug_intelligence_fingerprints
    WHERE fingerprint IN (
        'bb8db6c13848652a253a41efbadc871d', 'e3388d0313f3684927989494c3c72464',
        'b66f6c070ced888a9dc85867ec79ed1b', '1b6e9111a71c83930852e93f1aff33e5',
        'e810bf12eb825d4887a761ada6e0f90b', '1b5116cd10eb5a9c3e903bd3def97592',
        '5b97a3bcdc24d7cb1ed70d8609c8d6b2', '7f0628508cb50b9ca5be19dde3536fc1',
        '3d7ac331e9011e75e363f217b5827006', '23ac878010450752bb1b1ca994edb56b',
        'e656ad7a4fb1323db476cd8f2cf6ac39', '486b89c025c019b7f2b6c427a437811e',
        '7bf1ff4efdac6620edfbda328204ed16', 'f30626309d8480ec14526323da68396d',
        '97f51f027eb90d963fd22675590ad3bb', '18ff0951f7151b55cb7bbe25d0a72d19',
        'a580c35a1ea16b28e9cf79bb56a8788b', '9a4b5b9e58d06c908692f28684a024f1',
        '22422e4eaca00ea54a0ac3e5fbcb2d8a', '0080557f0dc278d22c345638b8e7d280',
        '1edfaad0c87c90a26f1fb59fb5cbc983', 'a22cd96f76784e01bf8f4e0c89433109',
        'a884bcffeb058963edc5b9cef449a15e', '6121691fd4ebfc9ca28b56e5f919b865',
        '90386263253e07724dae0af4adafd574', '1fb4a278f13adafd8acb2e9cf77470b2',
        'b706265b818c1b0c6ef8938e81142d71', 'ad2338484fb261798bfaa5ae006675bd',
        '4ba1e2c3d9af2e2a2544d3e972dad671', 'c46485c6a966d1890a5131fdf969e345',
        'b6a8bec9302467aec7f86cc83c1d2090', '5c4c3e1f4c2d46a9d049112e9ffb5f2c',
        '52d0423e83c1844095e0bd9e0531aeee', '3a510abf019dcf2838f80003ec3c0469',
        'a28bc5f83b1f6138fa52209670ce6f33', '18a4b0fc76b0cf6a17702443b82feb15',
        '3d3e397881fa4624f26384c1e69962cf', 'bd382acbe87d224cf88183e36318ab47',
        '15cce20e4302a42e1437f65fdf8fa667'
    )
      AND status IN ('resolved', 'duplicate');

    SELECT COUNT(*) INTO v_merged_count
    FROM bug_intelligence_reports
    WHERE review_status = 'merged'
      AND review_notes LIKE '%2026-04-25 17:58 audit cleanup%';

    RAISE NOTICE 'Marked % fingerprint(s) terminal (expected 39).', v_resolved_count;
    RAISE NOTICE 'Merged % report(s) with audit-cleanup paper trail.', v_merged_count;

    IF v_resolved_count < 39 THEN
        RAISE WARNING 'Expected 39 terminal fingerprints, got % — some may not exist in this env yet (safe to ignore on staging).', v_resolved_count;
    END IF;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- POST-DEPLOY: clear the bug-intel export watermark (per
-- MIGRATION_INDEX.md §Deployment Priority Queue) so the next
-- `mode=new` Cursor export starts with a clean slate:
--
--   UPDATE bug_intel_export_runs
--   SET exported_through_dev_session_log_id = NULL,
--       exported_through_crash_id           = NULL
--   WHERE id = (SELECT MAX(id) FROM bug_intel_export_runs);
-- ════════════════════════════════════════════════════════════════════
