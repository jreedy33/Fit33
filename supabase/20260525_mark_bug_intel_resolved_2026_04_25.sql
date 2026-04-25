-- ════════════════════════════════════════════════════════════════════
-- Mark bug-intelligence fingerprints resolved — 2026-04-25 sweep.
--
-- Source: bug-intelligence-new-2026-04-25T13-16-18.md (24 reports).
--
-- RESOLVED (21):
--   • Reports 3, 4   — HealthKit RLS (fixed by 20260511_health_rls_audit.sql, deployed today)
--   • Reports 5, 18  — DashboardWeightWidget classifier hygiene (already on main, Phase 25a)
--   • Reports 6, 10  — USDAFoodService classifier routing (fixed today)
--   • Reports 7, 9   — FoodDatabaseService classifier routing (fixed today)
--   • Reports 8, 12  — Core Data favorites mergePolicy (already on main, Phase 12c)
--   • Report  11     — ExerciseMappingService classifier routing (already on main)
--   • Reports 14, 15, 16 — "Not authenticated" P0001 RPCs (handled by bug_intel_noise_filter tier=hard)
--   • Report  17     — UserBehaviorLearningEngine classifier routing (already on main)
--   • Reports 19, 24 — HydrationService classifier routing (already on main, .debug)
--   • Report  20     — FriendRankingService classifier routing (already on main, Phase 12c)
--   • Report  21     — DailyQuestService classifier routing (already on main)
--   • Report  22     — SupabaseManager comprehensive sync classifier routing (already on main)
--   • Report  23     — StravaService classifier routing (already on main)
--
-- LEFT OPEN (3) — NOT marked resolved:
--   • Report 1  — SIGKILL signal 9 (no_dsym, blocked on symbolication)
--   • Report 2  — SIGSEGV first launch crash (no_dsym, blocked on symbolication)
--   • Report 13 — Shake feedback: challenge widget didn't refresh after workout
--                 (real UX bug, needs separate investigation in ChallengeWidget.swift)
--
-- Idempotent: the WHERE clause filters by fingerprint, so re-running this
-- is a no-op once status is already 'resolved'.
-- ════════════════════════════════════════════════════════════════════

BEGIN;

UPDATE bug_intelligence_fingerprints
SET status      = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    updated_at  = NOW()
WHERE fingerprint IN (
    -- Reports 3, 4 — HealthKit RLS
    'c0a9d73017e427c2338b624727e74b7e',
    'a5b6830cfc44d4948c164ac410a05ba4',
    -- Reports 5, 18 — DashboardWeightWidget
    '0559291e165fd36a13bfc24a5ac5c4ac',
    '7cc0965a661a315627d7aadbfd313912',
    -- Reports 6, 7, 9, 10 — USDA / FoodDatabase classifier routing (fixed today)
    '0bddbb488c79d073d0f7365cf38e5257',
    '479cf8181fee8649e92cf5b3bc0737c9',
    'd0aaa6e592e15638bdcb4fdb5b123b10',
    'f94ae6fef2a953a2fdbdb29f92cd0d2e',
    -- Reports 8, 12 — Core Data favorites mergePolicy
    '62f8f41180b350a972359bcc1fbd9f9d',
    'a0742a517dd5bea2bfa30ab023696e87',
    -- Report 11 — ExerciseMappingService timeout
    '761a14f1f7a3167aba58abf8300548a8',
    -- Reports 14, 15, 16 — "Not authenticated" P0001 RPCs (noise filter)
    '37e0c7f0d0bba790c0b002daac14937b',
    '779fa65eaba83ed577cae509b9d2bdeb',
    'd9e2c6d66938166ff623e14ed7485cbd',
    -- Report 17 — UserBehaviorLearningEngine
    'c6c5527103a42170cf2a2cf8cecdaa47',
    -- Reports 19, 24 — HydrationService cancellations
    '68852c05e0e97bb4cee513402f35b8d2',
    '7ac34f8960179f77ea0be78f6749c52d',
    -- Report 20 — FriendRankingService offline
    '965f365538f4d0bbc59c2a60275f2798',
    -- Report 21 — DailyQuestService cancellation
    '7f1d1a15f7f805ea15888124980c41d3',
    -- Report 22 — comprehensive sync timeout
    'b51563950846e095a07c583087a8dc4a',
    -- Report 23 — Strava sync timeout
    'd3551be0b75299b9c72cdf576f77daf4'
);

-- Verify the update — should print 21 rows.
DO $$
DECLARE
    resolved_count INT;
BEGIN
    SELECT COUNT(*) INTO resolved_count
    FROM bug_intelligence_fingerprints
    WHERE fingerprint IN (
        'c0a9d73017e427c2338b624727e74b7e','a5b6830cfc44d4948c164ac410a05ba4',
        '0559291e165fd36a13bfc24a5ac5c4ac','7cc0965a661a315627d7aadbfd313912',
        '0bddbb488c79d073d0f7365cf38e5257','479cf8181fee8649e92cf5b3bc0737c9',
        'd0aaa6e592e15638bdcb4fdb5b123b10','f94ae6fef2a953a2fdbdb29f92cd0d2e',
        '62f8f41180b350a972359bcc1fbd9f9d','a0742a517dd5bea2bfa30ab023696e87',
        '761a14f1f7a3167aba58abf8300548a8','37e0c7f0d0bba790c0b002daac14937b',
        '779fa65eaba83ed577cae509b9d2bdeb','d9e2c6d66938166ff623e14ed7485cbd',
        'c6c5527103a42170cf2a2cf8cecdaa47','68852c05e0e97bb4cee513402f35b8d2',
        '7ac34f8960179f77ea0be78f6749c52d','965f365538f4d0bbc59c2a60275f2798',
        '7f1d1a15f7f805ea15888124980c41d3','b51563950846e095a07c583087a8dc4a',
        'd3551be0b75299b9c72cdf576f77daf4'
    )
      AND status = 'resolved';
    RAISE NOTICE 'Marked % fingerprint(s) resolved (expected 21).', resolved_count;
END $$;

COMMIT;
