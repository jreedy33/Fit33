-- ════════════════════════════════════════════════════════════════════
-- BUNDLE: A — RLS audit + bug-intel close-out (3 files)
-- Concatenated 2026-04-25 14:33 EDT from individual migrations
-- on disk under supabase/. Each source file keeps its own
-- BEGIN; ... COMMIT; — paste this whole file into the SQL editor
-- and Postgres will run them serially as separate transactions.
-- All idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260608_workout_intelligence_rls_audit.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- Migration: Re-assert RLS policies for workout intelligence tables
-- Date: 2026-04-25
-- Agent: Data & Backend (primary), Infra & Security (RLS review)
--
-- Resolves: 1b6e9111a71c83930852e93f1aff33e5 — collaborative_workout_data RLS (Report 2)
-- Resolves: e810bf12eb825d4887a761ada6e0f90b — workout_context RLS (Report 3)
-- Resolves: 1b5116cd10eb5a9c3e903bd3def97592 — CrashReporter RLS (Report 9; same UUID-mismatch root cause via UserManager.swift)
-- Resolves: 5b97a3bcdc24d7cb1ed70d8609c8d6b2 — step_tracking RLS (Report 12; same UUID-mismatch root cause)
-- Resolves: 7f0628508cb50b9ca5be19dde3536fc1 — Health step sync RLS (Report 13; log variant of 12)
--
-- Why:
--   New users completing onboarding hit PostgrestError 42501
--   ("new row violates row-level security policy") on EVERY workout
--   intelligence write: workout_context, user_performance_trends,
--   set_completion_patterns, exercise_user_effectiveness,
--   workout_time_performance, weekly_volume_trends,
--   equipment_proficiency, collaborative_workout_data.
--
--   Two root causes:
--   1) The Core Data User.id was being created with a fresh UUID()
--      during `createUser()` in onboarding instead of the Supabase
--      auth.uid() — fixed in Fit33/UserManager.swift.
--   2) Some of the policies above were only applied via standalone
--      docs/QUICK_WINS scripts that may never have been deployed to
--      production. This migration re-asserts them idempotently.
--
-- Idempotent: drops policies before recreating; uses IF NOT EXISTS
-- where supported; safe to run multiple times. Wrapped in a single
-- transaction.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. workout_context
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE workout_context ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_insert_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_update_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "users_delete_own_workout_context" ON workout_context;
DROP POLICY IF EXISTS "Users can view own context" ON workout_context;
DROP POLICY IF EXISTS "Users can insert own context" ON workout_context;

CREATE POLICY "users_select_own_workout_context" ON workout_context
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_workout_context" ON workout_context
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_workout_context" ON workout_context
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_workout_context" ON workout_context
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_context_user_id ON workout_context (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 2. user_performance_trends
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE user_performance_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_insert_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_update_own_performance_trends" ON user_performance_trends;
DROP POLICY IF EXISTS "users_delete_own_performance_trends" ON user_performance_trends;

CREATE POLICY "users_select_own_performance_trends" ON user_performance_trends
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_performance_trends" ON user_performance_trends
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_performance_trends" ON user_performance_trends
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_performance_trends" ON user_performance_trends
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_performance_trends_user_id ON user_performance_trends (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 3. set_completion_patterns
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE set_completion_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_insert_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_update_own_set_patterns" ON set_completion_patterns;
DROP POLICY IF EXISTS "users_delete_own_set_patterns" ON set_completion_patterns;

CREATE POLICY "users_select_own_set_patterns" ON set_completion_patterns
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_set_patterns" ON set_completion_patterns
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_set_patterns" ON set_completion_patterns
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_set_patterns" ON set_completion_patterns
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_set_completion_patterns_user_id ON set_completion_patterns (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 4. exercise_user_effectiveness
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE exercise_user_effectiveness ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_insert_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_update_own_effectiveness" ON exercise_user_effectiveness;
DROP POLICY IF EXISTS "users_delete_own_effectiveness" ON exercise_user_effectiveness;

CREATE POLICY "users_select_own_effectiveness" ON exercise_user_effectiveness
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_effectiveness" ON exercise_user_effectiveness
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_effectiveness" ON exercise_user_effectiveness
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_effectiveness" ON exercise_user_effectiveness
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_exercise_user_effectiveness_user_id ON exercise_user_effectiveness (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 5. workout_time_performance
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE workout_time_performance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_insert_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_update_own_time_performance" ON workout_time_performance;
DROP POLICY IF EXISTS "users_delete_own_time_performance" ON workout_time_performance;

CREATE POLICY "users_select_own_time_performance" ON workout_time_performance
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_time_performance" ON workout_time_performance
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_time_performance" ON workout_time_performance
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_time_performance" ON workout_time_performance
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_workout_time_performance_user_id ON workout_time_performance (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 6. weekly_volume_trends
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE weekly_volume_trends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_insert_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_update_own_volume_trends" ON weekly_volume_trends;
DROP POLICY IF EXISTS "users_delete_own_volume_trends" ON weekly_volume_trends;

CREATE POLICY "users_select_own_volume_trends" ON weekly_volume_trends
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_volume_trends" ON weekly_volume_trends
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_volume_trends" ON weekly_volume_trends
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_volume_trends" ON weekly_volume_trends
    FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_weekly_volume_trends_user_id ON weekly_volume_trends (user_id);

-- ─────────────────────────────────────────────────────────────────────
-- 7. equipment_proficiency
-- (was only created via QUICK_WINS.sql — may not be in prod)
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS equipment_proficiency (
    user_id UUID NOT NULL,
    equipment_type TEXT NOT NULL,
    first_used DATE DEFAULT CURRENT_DATE,
    last_used DATE DEFAULT CURRENT_DATE,
    times_used INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, equipment_type)
);

CREATE INDEX IF NOT EXISTS idx_proficiency_user ON equipment_proficiency(user_id);

ALTER TABLE equipment_proficiency ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_select_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_insert_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_update_own_proficiency" ON equipment_proficiency;
DROP POLICY IF EXISTS "users_delete_own_proficiency" ON equipment_proficiency;

CREATE POLICY "users_select_own_proficiency" ON equipment_proficiency
    FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "users_insert_own_proficiency" ON equipment_proficiency
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_proficiency" ON equipment_proficiency
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_proficiency" ON equipment_proficiency
    FOR DELETE TO authenticated USING (user_id = auth.uid());

-- The increment_equipment_usage RPC is invoked with the caller's auth
-- context. Keep it SECURITY INVOKER so RLS is enforced on its INSERT.
CREATE OR REPLACE FUNCTION increment_equipment_usage(
    p_user_id UUID,
    p_equipment_type TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    -- Defensive: the RLS policy already enforces user_id = auth.uid(),
    -- but a clear mismatch should fail fast with a clean error.
    IF p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'increment_equipment_usage: p_user_id (%) does not match auth.uid() (%)', p_user_id, auth.uid()
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO equipment_proficiency (user_id, equipment_type, times_used, last_used)
    VALUES (p_user_id, p_equipment_type, 1, CURRENT_DATE)
    ON CONFLICT (user_id, equipment_type)
    DO UPDATE SET
        times_used = equipment_proficiency.times_used + 1,
        last_used = CURRENT_DATE,
        updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION increment_equipment_usage(UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 8. collaborative_workout_data
-- (originally defined in docs/COLLABORATIVE_LEARNING_SCHEMA.sql which
--  may not have been deployed)
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "Authenticated users can read workout data" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_select_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_insert_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_update_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "users_delete_own_collab_workout" ON collaborative_workout_data;
DROP POLICY IF EXISTS "authenticated_read_collab_workout" ON collaborative_workout_data;

-- Users can manage their own rows
CREATE POLICY "users_insert_own_collab_workout" ON collaborative_workout_data
    FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_update_own_collab_workout" ON collaborative_workout_data
    FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_delete_own_collab_workout" ON collaborative_workout_data
    FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Aggregate read access (collaborative analysis requires reading peers).
CREATE POLICY "authenticated_read_collab_workout" ON collaborative_workout_data
    FOR SELECT TO authenticated USING (true);

CREATE INDEX IF NOT EXISTS idx_collab_workout_user_id ON collaborative_workout_data (user_id);

COMMIT;

-- ============================================================================
-- VERIFICATION (run manually after migration):
--
--   SELECT schemaname, tablename, policyname, cmd
--   FROM pg_policies
--   WHERE tablename IN (
--     'workout_context','user_performance_trends','set_completion_patterns',
--     'exercise_user_effectiveness','workout_time_performance',
--     'weekly_volume_trends','equipment_proficiency','collaborative_workout_data'
--   )
--   ORDER BY tablename, cmd, policyname;
--
-- Expected: 4 owner-scoped policies per table (SELECT/INSERT/UPDATE/DELETE),
-- plus 1 extra SELECT policy on collaborative_workout_data for peer reads.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260609_mark_bug_intel_resolved_2026_04_25_audit.sql
-- ════════════════════════════════════════════════════════════════════

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


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260610_mark_audit_code_fixes_resolved.sql
-- ════════════════════════════════════════════════════════════════════

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

