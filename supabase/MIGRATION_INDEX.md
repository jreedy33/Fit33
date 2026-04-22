# Supabase Migration Index — Canonical Source of Truth

> **Rule**: All new schema changes MUST be added as a new timestamped file.
> Never modify an already-deployed migration. If a fix is needed, create a new file.

## Scope & Policy (Q2-85, Sprint 8 — 2026-04-27)

This index is the **canonical release-train** for Supabase migrations. It is
NOT a line-by-line listing of every file under `supabase/*.sql` — there are
~175 files on disk; this document tracks ~60 release-train entries.

**In scope (MUST be indexed here):**
- Any new `YYYYMMDD_…` migration that creates tables, alters schema, creates
  RPCs, touches RLS, or enables Realtime publications.
- Any bug-fix / security hotfix migration that is expected to be run on prod.
- Each entry gets a numbered row, a status emoji, and a "What it does" note
  covering the invariants the app relies on.

**Out of scope (tracked in the §Legacy / Bulk Ledger below, not inline):**
- Pre-`YYYYMMDD_` naming era files (e.g. `challenge_rpc_functions.sql`,
  `friend_request_system.sql`). Historic, mostly already-absorbed by later
  hotfixes. Kept on disk for audit; do not edit.
- Bulk data scripts — `exercise_replace_{01..15}.sql`,
  `update_exercises_*.sql`, `exercises_update_*.sql` — one-shot exercise CSV
  loads.
- Read-only auditors / verifiers — `audit_before.sql`, `audit_after.sql`,
  `verify_query_performance.sql`, `verify_*.sql`, `sim_test_helpers.sql`.
- Private-challenge / weekly-league foundational migrations that pre-dated
  the index (already superseded or consolidated by later `YYYYMMDD_` files).

**Authoring rule for new migrations:**
1. New file name format: `YYYYMMDD_short_description.sql`.
2. Append a new numbered row to the dated section at the bottom (create a
   new section for the date if needed).
3. Never retroactively edit a deployed migration — create a new hotfix file
   and reference the supersession in both files.
4. If the migration is a bulk data load or a one-shot audit query, it stays
   in the §Legacy / Bulk Ledger.

---

## Deployed Migrations (in order)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 1 | `fix_contact_matching_rls.sql` | ✅ Deployed | RLS policies for contact discovery |
| 2 | `cascade_delete_incomplete_profiles.sql` | ✅ Deployed | Cascade delete for incomplete onboarding profiles |
| 3 | `cleanup_incomplete_onboarding.sql` | ✅ Deployed | Auto-cleanup abandoned profiles (30 min) |
| 4 | `complete_account_deletion.sql` | ✅ Deployed | Full data wipe on account delete |
| 5 | `friend_request_system.sql` | ✅ Deployed | Friend request CRUD (send/accept/reject/cancel) |
| 6 | `friend_request_notifications.sql` | ✅ Deployed | Push notifications for friend requests |
| 7 | `fix_friend_safety.sql` | ✅ Deployed | Safety fixes for decline/cancel friend requests |
| 8 | `create_friend_rpc_functions.sql` | ✅ Deployed | `get_friends()`, `get_received_workouts()`, `get_sent_workouts()` |
| 9 | `fix_data_relationships.sql` | ✅ Deployed | FK constraints and orphan data cleanup |
| 10 | ~~`fix_account_deletion.sql`~~ | 🗑️ Removed 2026-04-17 | Duplicate of `complete_account_deletion.sql`. Canonical `delete_user_account()` RETURNS `jsonb` lives in that file. |
| 11 | `fix_trigger_conflicts.sql` | ✅ Deployed | Resolve conflicting auth deletion triggers |
| 12 | `challenge_type_migration.sql` | ✅ Deployed | Challenge type enum + leaderboard tables |
| 13 | `challenge_rpc_functions.sql` | ✅ Deployed | **Canonical challenge RPCs** (create, respond, log, cancel, leave, etc.) |
| 14 | `community_challenges_migration.sql` | ✅ Deployed | Community challenge tables + RPCs |
| 15 | `fix_create_group_challenge.sql` | ✅ Deployed | Fix group challenge creation |
| 16 | `fix_ambiguous_columns.sql` | ✅ Deployed | Resolve ambiguous column references |
| 17 | `fix_group_challenge_timezone.sql` | ✅ Deployed | Timezone handling for group challenges |
| 18 | `fix_leave_group_challenge.sql` | ✅ Deployed | Fix leave/cancel group challenge RPCs |
| 19 | `fix_challenge_cascade_delete.sql` | ✅ Deployed | Cascade deletes for challenge-related tables |
| 20 | `fix_challenge_participants.sql` | ✅ Deployed | Fix challenge participant constraints |
| 21 | `fix_comprehensive_audit.sql` | ✅ Deployed | Comprehensive fixes from audit |
| 22 | `fix_cardio_workouts_constraint.sql` | ✅ Deployed | Deduplicate cardio workout rows |
| 23 | `fix_materialized_view.sql` | ✅ Deployed | Fix/refresh materialized views |
| 24 | `refresh_exercise_view.sql` | ✅ Deployed | Refresh exercise materialized view |
| 25 | `program_templates_migration.sql` | ✅ Deployed | Program templates table + seed data |
| 26 | `global_food_popularity.sql` | ✅ Deployed | Food popularity tracking tables |
| 27 | `verify_critical_functions.sql` | ✅ Deployed | Verification checks for critical RPCs |

## Exercise Data (bulk updates — run once)

| File | Status | Notes |
|------|--------|-------|
| `update_exercises_from_csv.sql` | ✅ Deployed | Initial exercise data load |
| `update_exercises_batch2.sql` | ✅ Deployed | Batch 2 updates |
| `update_exercises_batch3.sql` | ✅ Deployed | Batch 3 updates |
| `update_exercises_final_fixed.sql` | ✅ Deployed | Final exercise data with lever name fixes |

---

## Duplicated Function Definitions (Canonical Owners)

These functions are defined in multiple files due to historical hotfixes.
The **canonical version** is the one in the latest file listed below.

| Function | Canonical File | Also in (superseded) |
|----------|---------------|---------------------|
| `get_active_group_challenges` | `fix_group_challenge_timezone.sql` | `challenge_rpc_functions.sql`, `fix_comprehensive_audit.sql` |
| `log_challenge_progress` | `fix_ambiguous_columns.sql` | `challenge_rpc_functions.sql`, `challenge_type_migration.sql` |
| `cancel_group_challenge` | `fix_leave_group_challenge.sql` | `challenge_rpc_functions.sql`, `fix_ambiguous_columns.sql` |
| `reject_friend_request` | `fix_comprehensive_audit.sql` | `fix_friend_safety.sql`, `friend_request_system.sql` |
| `decline_friend_request` | `fix_comprehensive_audit.sql` | `fix_friend_safety.sql` |
| `cancel_friend_request` | `fix_comprehensive_audit.sql` | `fix_friend_safety.sql` |
| `delete_user_account` | `complete_account_deletion.sql` | `fix_account_deletion.sql` (deleted 2026-04-17) |
| `delete_auth_user_on_profile_delete` | `complete_account_deletion.sql` | `cascade_delete_incomplete_profiles.sql` |
| `send_friend_request` | `friend_request_notifications.sql` | `friend_request_system.sql` |
| `cleanup_auth_on_profile_delete` | `fix_trigger_conflicts.sql` | `fix_account_deletion.sql` |
| `create_group_challenge` | `fix_create_group_challenge.sql` | `challenge_rpc_functions.sql` |
| `leave_group_challenge` | `fix_leave_group_challenge.sql` | `challenge_rpc_functions.sql` |
| `log_group_challenge_progress` | `fix_group_challenge_timezone.sql` | `challenge_rpc_functions.sql` |
| `get_active_challenges` | `fix_comprehensive_audit.sql` | `challenge_rpc_functions.sql` |

---

## Database Audit Remediation (2026-03-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 28 | `audit_before.sql` | 🆕 Ready | Baseline snapshot (read-only, run first) |
| 29 | `20260320_drop_dead_tables.sql` | 🆕 Ready | DROP 13 dead tables (0 rows, 0 code refs) with safety guards |
| 30 | `20260320_add_missing_fk_constraints.sql` | 🆕 Ready | FK CASCADE on 11 analytics tables + exercise_videos + indexes |
| 31 | `20260320_sync_profiles_progress.sql` | 🆕 Ready | Bidirectional sync trigger for user_profiles <-> user_progress |
| 32 | `20260320_consolidate_food_history.sql` | 🆕 Ready | user_food_history_v view from meal_logs |
| 33 | `audit_after.sql` | 🆕 Ready | 7-test verification suite (read-only, run last) |

**Run order**: 28 → 29 → 30 → 31 → 32 → 33

## Smart Insights Enhancement (2026-03-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 34 | `20260320_smart_insights_schema.sql` | 🆕 Ready | Phase 1: completion_rate, opened_at, referral_source columns + subscription_events table |
| 35 | `20260320_smart_insights_views.sql` | 🆕 Ready | Phase 2: 5 cross-table correlation views (nutrition, hydration, social, challenge, sleep) |
| 36 | `20260320_smart_nudge_notifications.sql` | 🆕 Ready | Phase 4.3: generate_smart_nudges() RPC for targeted push notifications |

**Run order**: 34 → 35 → 36

## USDA Food Search Integrity (2026-03-21)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 37 | `20260321_food_search_integrity.sql` | 🆕 Ready | Cache TTL column, frequent foods RPC, user_food_history index, user_favorite_foods UNIQUE |

**Run order**: 37 (standalone, no dependencies on 28-36)

## Notification Preferences (2026-03-21)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 38 | `20260321_notification_preferences.sql` | 🆕 Ready | user_notification_preferences table + RLS for server-side push preference enforcement |

**Run order**: 38 (standalone)

## Activity Feed / Privacy / Leagues (2026-03-30 → 2026-03-31)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 39 | `20260330_activity_feed_exercises.sql` | 🆕 Ready | Activity feed exercise rows + RPC additions |
| 40 | `20260330_add_cover_image_to_rpcs.sql` | 🆕 Ready | Include cover_image field in challenge list RPCs |
| 41 | `20260330_league_privacy_realtime.sql` | 🆕 Ready | Weekly league privacy + realtime subscriptions |
| 42 | `20260330_privacy_photo_all_rpcs.sql` | 🆕 Ready | Photo privacy enforcement across all profile RPCs |
| 43 | `20260330_privacy_rpc_enforcement.sql` | 🆕 Ready | RPC-level privacy enforcement for shared RPCs |
| 44 | `20260330_privacy_settings.sql` | 🆕 Ready | `privacy_settings` table + RLS + RPCs |
| 45 | `20260331_league_auto_placement.sql` | 🆕 Ready | `auto_place_all_league_members()` pg_cron job (Monday 00:15 UTC) |

**Run order**: 39 → 40 → 41 → 42 → 43 → 44 → 45 (each is idempotent; 45 installs pg_cron schedule)

## Sprint 1 Lockdown (2026-04-17)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 46 | `20260417_secure_get_friend_ids.sql` | 🆕 Ready | IDOR guard: `get_friend_ids(p_user_id)` now rejects other users |
| 47 | `20260417_phone_verification_rate_limit.sql` | 🆕 Ready | DB-backed Twilio rate limit table + `check_phone_verification_rate_limit()` RPC |
| 48 | `20260417_ai_insights_admin_emails.sql` | 🆕 Ready | Admin allowlist for `generate-ai-insights` edge function |

**Run order**: 46 → 47 → 48 (standalone, idempotent).
**Paired code changes**: edge functions `moderate-content`, `send-verification`, `generate-ai-insights`, `usda-food-search`, `notify-contacts-user-joined`, `send-push-notification` all redeploy this sprint with tightened auth.

## Sprint 2 Submit-Ready (2026-04-18)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 49 | `20260418_blocking_and_reporting.sql` | 🆕 Ready | `get_blocked_users()` + `report_content()` RPCs for App Review social compliance |
| 50 | `20260418_group_challenge_members_invariant.sql` | 🆕 Ready | Legacy `group_challenge_members` hardening: REVOKE direct writes + COMMENT invariant |
| 51 | `20260418_post_cardio_activity.sql` | 🆕 Ready | `post_cardio_activity()` RPC — cardio parity in friend activity feed |

**Run order**: 49 → 50 → 51 (standalone, idempotent).
**Paired code changes**: `BlockedUsersView`, Settings integration, Report+Block sheets in chat & activity feed (Q2-7); cardio gamification wires (`UserManager.completeCardioWorkout`, Q2-5); `verify-code` / `send-push-notification` CORS migration (Q2-22).

## Challenge Background Refresh (2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 52 | `20260420_challenge_opponent_wake.sql` | 🆕 Ready | `silent_push_wake_log` table + RLS + 7-day prune cron; `trigger_challenge_opponent_wake()` pg_cron every 30 min invokes `wake-challenge-opponents` edge function. |

**Run order**: 52 (standalone, idempotent). Requires `internal_config` rows `supabase_url`, `service_role_key`, `anon_key` (already seeded by migration 20260324_push_notification_cron.sql).
**Paired code changes**:
- New edge function: `supabase/functions/wake-challenge-opponents/index.ts` (deploy with `supabase functions deploy wake-challenge-opponents` — uses same APNS_* secrets as `send-push-notification`).
- New Swift files: `Fit33/SilentPushHandler.swift`, `Fit33/ChallengeOpponentWakeService.swift`.
- Modified: `Fit33/BackgroundChallengeSyncService.swift` (adds `BGProcessingTask` + per-source throttle + post-sync opponent-wake call), `Fit33/Fit33App.swift` (AppDelegate `didReceiveRemoteNotification` + scenePhase `.active` wake trigger), `Fit33/Info.plist` (adds `com.gofit.app.challengeSyncProcessing` BGTask identifier + `remote-notification` UIBackgroundMode).

## Cardio History Cleanup (2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 53 | `20260420_cardio_workouts_overlap_dedup.sql` | 🆕 Ready | One-time cleanup of duplicate WHOOP `cardio_workouts` rows (same user, same origin, overlapping time windows). Keeps the richest row via a scored comparison (specific `activity_type`, heart-rate, distance, calories). Client-side dedup now lives in `HealthDataService.syncWhoopData`; this migration fixes the rows that were already inserted before the fix. |

**Run order**: 53 (standalone, idempotent). Safe to re-run — the CTE compares every row against every other row in the same (user, origin) window and deletes only the loser.
**Paired code changes**: `Fit33/HealthDataService.swift` — `syncWhoopData` time-overlap dedup + scoring.

## Daily Quest Overhaul (2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 54 | `20260420_daily_quests_actionable_fixes.sql` | 🆕 Ready | Fixes three UX bugs in `get_daily_quests`: (1) honour `quest_templates.requires_context` gates so users without a program stop seeing "Program Day"; (2) retires the "Double Session — 2 workouts today" template; (3) restores `tracking` / `wildcard` / `social` pool categories that the prior pool-builder was silently dropping. |

**Run order**: 54 (standalone, idempotent). Supersedes selector logic from `20260325_quest_challenge_sync.sql` — no paired code change needed; app reads quests via the same RPC signature.
**Paired code changes**: none (RPC signature unchanged).

## Exercise Library Realtime (2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 55 | `20260420_exercises_realtime.sql` | ✅ Deployed | Enables Realtime REPLICA IDENTITY FULL on `exercises` so admin CMS edits live-sync to the iOS app; covered by commit `403d1ee`. |

**Paired code changes**: `Fit33/ExerciseLibraryView.swift` realtime subscription wiring.

## Atomic Challenge Accept/Decline (C-6, Sprint 5 — 2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 56 | `20260420_atomic_challenge_rpcs.sql` | 🆕 Ready | New `accept_challenge(uuid)` + `decline_challenge(uuid)` RPCs with `SELECT ... FOR UPDATE` on the caller's `challenge_participants` row. Idempotent (returns `already_accepted` / `already_declined` instead of raising) and structured (`jsonb` with `status`/`all_accepted`/`cancelled`). Legacy `respond_to_challenge` left in place for older installed clients. |

**Paired code changes**: `Fit33/ChallengeService.respondToChallenge` now calls the new RPCs and interprets the structured status, skipping heavy post-accept sync on idempotent replays.

## Index Verification (DB-5, Sprint 5 — 2026-04-20)

| # | File | Status | What it does |
|---|------|--------|-------------|
| — | `verify_query_performance.sql` | 🛠️ Verifier (not a migration) | Read-only audit that lists every expected index on hot tables (challenges, friendships, shared_workouts, daily rollups, push log, moderation, workout_history, etc.) and marks each row `OK` or `MISSING`. Replaces the never-created `optimize_query_performance.sql` from MASTER_TODO. Run ad hoc or in CI: `psql $SUPABASE_DB_URL -f supabase/verify_query_performance.sql | grep MISSING`. Extend the `expected_indexes` CTE whenever a new hot-path index ships. |

## Daily Quest Program + Focus Aware (2026-04-21)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 57 | `20260421_daily_quests_program_and_focus_aware.sql` | 🟡 Superseded by 58 | Added two optional params to `get_daily_quests` (`p_suggested_split TEXT`, `p_fatigued_regions TEXT[]`) and used them to force slot 1 to a region-specific quest (`lower_body_workout`, `upper_body_workout`, …). Replaced because the region-specific slot penalized users who did an excellent workout in a different split — "Leg Day" stayed 0/1 when the user did arms + back. Migration 58 keeps the copy but rewires the quest_key. |

## Daily Quest Workout Slot Flexibility (2026-04-22)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 58 | `20260422_daily_quest_workout_slot_flexibility.sql` | 🟡 Superseded by 59 | Same 18-arg signature as migration 57, but slot 1's `quest_key` for non-program users is now ALWAYS `complete_workout` (or `complete_program_day` for program users). The personalized "Leg Day — legs are fresh" title/description is preserved as guidance, but any completed workout ticks the quest off so users aren't penalized for doing a substantive workout in a different split. Also removes `upper_body_workout` / `lower_body_workout` from the eligible pool so the same single-region penalty can't creep in via other slots. The underlying `p_suggested_split` / `p_fatigued_regions` contract is unchanged. |

**Run order**: 58 (standalone, idempotent). Drops both the 16-arg and 18-arg overloads before recreating, so safe to re-run.
**Paired code changes**: `Fit33/DailyQuestViews.swift` adds the new "any workout counts" marker to `isPersonalizedWorkoutDescription`. `Fit33/AdvancedIntelligenceService.swift` (`getPersonalizedRecommendation`) now sources its workout suggestion from `WorkoutSuggestionEngine.suggestForTodayAsync()` — the same engine that feeds `DailyQuestService.gatherUserContext`'s `suggestedSplit` — so the dashboard welcome widget and the daily quest card agree on today's split (no more "Lower Abs need work" vs "Leg Day" contradiction).

## Daily Quest Smart Hierarchy (2026-04-23)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 59 | `20260423_daily_quest_smart_hierarchy.sql` | 🆕 Ready | Three new intelligence layers on top of migration 58. (1) **Redundancy matrix**: when slot 1 is a workout quest (`complete_workout` / `complete_program_day` / `complete_2_workouts`), slots 2/3 no longer pick `active_minutes_30`, `burn_300_calories`, `workout_30_min`, `exercise_sets_{15,25}`, `beat_volume_pr`, `stretch_session`, `maintain_streak`, `league_3_workouts`, or `early_bird_workout` — finishing any workout subsumes all of them. Same applies when slot 1 is a step-goal quest (10K steps already covers active-minutes + burned-cal goals). (2) **Challenge override**: new optional `p_active_challenge_types TEXT[]` param mirrors the user's active 1v1/group `challenge_type` set. For each active type the matching quest is force-placed in slot 2/3 even if the redundancy matrix would have stripped it — priority order `active_minutes > calories > hydrate > protein > workout_streak > lift`. Step challenges keep flowing through `p_active_step_challenge_target`. (3) **Category diversity**: if the final 3 quests span fewer than 2 distinct categories (`workout / nutrition / steps / tracking / social`), slot 3 is swapped for the highest-priority unrepresented category via a ladder that depends on what slot 1 is (workout anchor → prefer nutrition; steps anchor → prefer nutrition; other → prefer nutrition). Net effect: instead of "Crush a Workout + Get Moving + Burn 300 cal" (all redundant), users see "Crush a Workout + Log 3 Meals + 8 Glasses of Water" — or when a challenge is live, "Crush a Workout + Catch KC in Steps + Beat KC's Active Minutes". Signature is 19 args; drops 16/18-arg overloads before recreating. |

**Run order**: 59 (standalone, idempotent). Safe to re-run.

| 60 | `20260424_exercises_manually_updated.sql` | 🆕 Ready | Adds `exercises.manually_updated BOOLEAN NOT NULL DEFAULT FALSE` + `manually_updated_at TIMESTAMPTZ` columns and a partial index `idx_exercises_manually_updated_at` (where `manually_updated = TRUE`). Powers the new "Updated" checkbox on the admin CMS exercise detail page — the API auto-stamps `manually_updated = TRUE` + `manually_updated_at = now()` on every `update_exercise` save (or clears both when the admin explicitly unchecks the box). No RLS change: the existing `exercises` policies already cover admin writes via service role. |

**Run order**: 60 (standalone, idempotent). Safe to re-run.
**Paired code changes**: `admin-cms/src/app/api/admin/route.ts` — `get_exercises` select now includes both columns; `update_exercise` allowed-fields list includes `manually_updated` and the handler auto-stamps the flag + timestamp on save (clears them when the admin unchecks). `admin-cms/src/app/exercises/[id]/page.tsx` — new top-right "Updated" checkbox auto-checks on any unsaved content edit, shows the saved date next to it, and is clickable (when no pending edits) to clear the manual-edit flag.
**Paired code changes**: `Fit33/DailyQuestService.swift` — `UserQuestContext.activeChallengeTypes` gathered from `ChallengeService.activeChallenges` + `activeGroupChallenges`, then encoded as `p_active_challenge_types` in the RPC payload. `Fit33/DailyQuestViews.swift` — `dynamicDescription` now rewrites step / active-minute / calorie / water / protein / streak quest copy with opponent deficit ("5K to catch KC" / "Lead KC by 200 cal" / "Tied with KC") via the new `firstActiveChallenge(matching:)` + `challengeDeficitCopy(...)` helpers. Every quest description string is capped at ~35 chars so the single-line card layout never truncates.

## Sprint 6 Security Hardening (2026-04-25)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 61 | `20260425_secure_definer_rpc_idor_fixes.sql` | 🆕 Ready | Inserts the canonical IDOR guard (`IF auth.uid() IS NOT NULL AND <user_param> <> auth.uid() THEN RAISE 42501`) into two remaining SECURITY DEFINER RPCs that accepted a `user_id` parameter but never verified the caller: `delete_user_account(user_id_to_delete UUID)` (P0 — any signed-in user could wipe any other account) and `get_user_achievements(p_user_id UUID DEFAULT NULL)` (P1 — any signed-in user could read any other user's progress). service_role / pg_cron (where `auth.uid() IS NULL`) keep full access so admin cleanup + backfills still work. Pattern mirrors 20260417_secure_get_friend_ids.sql. |

**Run order**: 61 (standalone, idempotent). Safe to re-run.

## Sprint 7 Security + Realtime Hygiene (2026-04-26)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 62 | `20260426_sprint7_security_hygiene.sql` | 🆕 Ready | (Q2-72) Extends the IDOR guard from migration 61 to the last three SECURITY DEFINER RPCs that accept a user_id: `get_daily_quests(TEXT, ...)`, `get_or_join_weekly_league(UUID)`, `get_league_leaderboard(UUID, UUID)`. Each historical overload is DROPped first per supabase-rules §12, then the latest signature is recreated with the guard inserted at the top of `BEGIN`. Non-auth callers (service_role / pg_cron contexts where `auth.uid() IS NULL`) keep full access so auto-placement, cleanup, and cron-driven refreshes still work. (Q2-73) Adds `private_challenge_chat` to the `supabase_realtime` publication — the table already had `REPLICA IDENTITY FULL` from `private_challenges_migration.sql` but was missed by `fix_private_realtime_publication.sql`, so moderation UPDATE events were silently dropped at the client. Idempotent via `EXCEPTION WHEN duplicate_object`. |

**Run order**: 62 (standalone, idempotent). Safe to re-run.
**Paired file edits (no DB migration needed)**:
- Q2-93: added `IF NOT EXISTS` to every `CREATE INDEX` in `20260328_content_moderation.sql`, `migrations/20260226_crash_reports.sql`, `20260325_version_changelogs.sql`.
- Q2-95: header comment on `20260324_adaptive_quest_selection.sql` marks it superseded by the 2026-04-25+ `get_daily_quests` rewrites so the `ROW(0,0,0)` anti-pattern on line 246 isn't mistaken for live code.
- Q2-96: `20260307_friend_activity_realtime.sql` replaced with a superseded-by-20260307_activity_feed_realtime.sql breadcrumb so re-running the duplicate ADD can't fail.

## Sprint 8 — Bug Intelligence Pipeline (2026-04-27)

| # | File | Status | What it does |
|---|------|--------|-------------|
| 66 | `20260430_bug_intel_feedback_loop.sql` | 🆕 Ready | (Q2-97 Phase 4) Knowledge feedback loop — closes the bug pipeline cycle when a BugIntel PR merges on GitHub. (1) Adds lifecycle columns to `bug_intelligence_reports`: `github_pr_number INTEGER`, `github_pr_merged_at TIMESTAMPTZ`, `feedback_applied_at TIMESTAMPTZ`, `docs_commit_sha TEXT` (last one reserved for Phase 4.1 docs auto-commit). Two partial indexes on `github_pr_number` and `github_pr_merged_at` (both `WHERE <col> IS NOT NULL`) for fast webhook lookups + time-to-fix sorts. (2) `v_bug_intelligence_metrics` view (`security_invoker = on` per supabase-rules.mdc) — per-agent leaderboard over last 30 days with: reports_total, unique_fingerprints, review_status breakdown (pending / approved / rejected / merged), severity breakdown (critical / high), avg_confidence, fix_rate_pct (merged / (merged+rejected+approved) excluding pending), median_time_to_fix_hours via `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY github_pr_merged_at - first_seen_at)`, total_occurrences_affected, total_users_affected. Ordered by merged count DESC, total DESC. (3) Admin CMS Bug Intelligence page renders this as an agent leaderboard table under the existing overview row. No new tables — additive columns + view only. |
| 65 | `20260429_bug_intelligence_crash_enrichment.sql` | 🆕 Ready | (Q2-97 Phase 3) Crash enrichment + log↔crash correlation so Phase 2 Claude triage produces PR-ready file_path + code_diff fields. (1) `crash_reports.bi_fingerprint` generated column `GENERATED ALWAYS AS (bug_intelligence_fingerprint(bug_intelligence_normalize(error_message), 'crash', NULLIF(error_domain, ''))) STORED` + btree index `idx_crash_reports_bi_fingerprint`. Joins `crash_reports` to `bug_intelligence_fingerprints` in O(1) — this is separate from `crash_reports.fingerprint` which is a client-side stack-trace hash. Works because Phase 1 `bug_intelligence_normalize()` and `bug_intelligence_fingerprint()` are both IMMUTABLE. (2) `fn_backfill_crash_session_snippet()` SECURITY DEFINER BEFORE INSERT trigger on `crash_reports` — when `session_id` is set and `session_log_snippet` is empty, stitches the last 100 `error` / `screen` / `tap` / `warning` / `api` entries from `dev_session_logs` for that session (bounded to `occurred_at + 5 minutes` window). Wrapped in `BEGIN / EXCEPTION / END` so a failed enrichment NEVER blocks the crash insert — the crash matters more than the snippet. Uses `bug_intelligence_ensure_array()` from Phase 1 to handle both JSONB-array and string-wrapped entries formats. (3) One-shot backfill: updates all crashes from the last 30 days with `session_id IS NOT NULL` and empty `session_log_snippet`. Bounded to 30 days because `dev_session_logs` rolls off. (4) Final sanity-check `DO $$` block reports counts (`total / with bi_fingerprint / with session snippet`). |
| 64 | `20260428_bug_intelligence_reports.sql` | 🆕 Ready | (Q2-97 Phase 2) Claude-driven bug triage + agent-owner routing. (1) New table `bug_intelligence_reports` — one row per triage run per fingerprint (`fingerprint` FK → `bug_intelligence_fingerprints`, `trigger_trend_id` FK → `bug_intelligence_trends`, `trigger_reason` CHECK in `('new', 'regression', 'scheduled', 'manual')`); stores the Claude output fields `agent_owner` (CHECK constrained to the exact roster in `ENGINEERING_TEAM.md`: `quality-performance` / `product-engineer` / `data-backend` / `infra-security` / `supabase-expert` / `design-system` / `design` / `fitness-expert` / `device-compatibility` / `support` / `unknown`), `invariant_violated`, `severity` (`critical` / `high` / `medium` / `low`), `confidence` (NUMERIC 0-1), `title`, `summary`, `file_path`, `code_diff`, `pain_point_candidate`, `suggested_todo`, plus PR / review lifecycle (`review_status` IN `pending` / `approved` / `rejected` / `merged` / `stale`, `pr_url`, `pr_branch`, `reviewed_by` FK → `user_profiles`, `reviewed_at`), full raw Claude response in `raw_response JSONB`, and `example_entry_ids` for auditability. RLS enabled, no policies → service-role only. (2) `trigger_triage_bugs()` SECURITY DEFINER wrapper — follows the canonical `internal_config` + `x-cron-key` pattern from `20260420_challenge_opponent_wake.sql` — reads `supabase_url` / `service_role_key` / `anon_key` from `internal_config` and `PERFORM net.http_post()` to `/functions/v1/triage-bugs`. (3) `cleanup_bug_intelligence_reports()` — 90-day prune for rejected / stale / merged reports (pending reports never pruned). (4) pg_cron schedules: `triage-bugs-run` every 4h at `:17` (offset from the Phase 1 hourly rollup at `:00` to avoid connection contention), `cleanup-bug-intelligence-reports` daily at `03:45 UTC`. (5) `v_bug_intelligence_inbox` view (`security_invoker = on`) — pending reports sorted by severity then confidence — is the admin CMS triage inbox surface. Indexes on `(fingerprint, created_at DESC)`, `(agent_owner, review_status, created_at DESC)`, `(severity, confidence DESC, created_at DESC)`, and `(review_status, created_at DESC)`. |
| 63 | `20260427_bug_intelligence.sql` | 🆕 Ready | (Q2-97 Phase 1) Foundations for the automated bug-trend / regression-detection pipeline. (1) Three new tables — `bug_intelligence_fingerprints` (deduplicated bug signatures across `dev_session_logs` errors + `crash_reports`, with admin-managed fields `status` / `assigned_agent` / `pain_point_id` / `resolution_pr_url` / `duplicate_of`), `bug_intelligence_daily_rollup` (per `fingerprint × day × screen × app_version` counts), and `bug_intelligence_trends` (append-only `'new'` / `'regression'` signals). All three are RLS-enabled, service-role-only. (2) Two immutable helpers: `bug_intelligence_normalize(msg)` masks `<id>` (long hex) and `<n>` (numbers) so `"user abc12345 failed"` and `"user def67890 failed"` fingerprint together (mirrors the JS normalizer in `admin-cms/src/app/dev-logs/page.tsx`), and `bug_intelligence_fingerprint(normalized, source, domain)` produces an `md5` hash. (3) Main worker `compute_daily_bug_rollup()` SECURITY DEFINER function — pg_cron-scheduled hourly at `0 * * * *` — scans the last 5 days of `dev_session_logs` (entries where `type='error'`) and `crash_reports`, UPSERTs fingerprints (preserving admin-managed fields), rewrites the rolling 5-day rollup, and appends trend signals (`new` when `first_seen_at >= today` AND `today_count >= 3`; `regression` when `today_count >= 3` AND `today_count > 3 × mean(days 1-4 ago)`). Skips fingerprints already marked `resolved` / `wont_fix` / `duplicate`. (4) Retention cleaner `cleanup_bug_intelligence_rollup()` — pg_cron daily at `30 3 * * *` — drops rollup rows > 30 days and trend rows > 90 days. (5) Forward-compat: adds `dev_logging_users.cohort TEXT NOT NULL DEFAULT 'beta'` column. (6) Cohort policy: one-shot INSERT enrolls **every existing `user_profiles` row** into `dev_logging_users` with `enabled = TRUE` (TestFlight-era — all current users OK to track per user confirmation 2026-04-27). (7) `auto_enroll_dev_logging()` SECURITY DEFINER trigger on `user_profiles INSERT` auto-adds future signups to cohort=beta. At GA, swap the trigger for a sampled variant or drop it. (8) Primes the pipeline with one initial call inside the migration so the rollup / trend tables aren't empty on deploy. |

**Run order**: 63 → 64 → 65 → 66 (all standalone, idempotent). Safe to re-run. Preserves admin-managed fingerprint fields (`status` / `assigned_agent` / `pain_point_id` / `resolution_pr_url`) across runs.
**Paired code changes**:
- Phase 2: `supabase/functions/triage-bugs/index.ts` + `admin-cms/src/app/bug-intelligence/page.tsx` + new admin API actions. Requires `ANTHROPIC_API_KEY` secret + `internal_config` rows.
- Phase 3: updates `supabase/functions/triage-bugs/index.ts` to use `crash_reports.bi_fingerprint` for O(1) crash lookup, include `stack_trace` / `breadcrumbs` / `session_log_snippet` in Claude input, cross-correlate log ↔ crash via the `bug_intelligence_fingerprint()` RPC.
- Phase 3.1: prompt tweak in `triage-bugs` — unsymbolicated hex stacks are NOT used to guess file names; falls back to error-message tags + current_screen + session_log_snippet with confidence ≤0.70.
- Phase 4 (this sprint): `supabase/functions/github-pr-webhook/index.ts` — HMAC-verified GitHub PR webhook handler that flips `review_status` → `merged` and `fingerprint.status` → `resolved` when a BugIntel PR lands. `admin-cms/src/app/bug-intelligence/page.tsx` gains an `AgentLeaderboard` row reading from `v_bug_intelligence_metrics`. `admin-cms/src/app/api/admin/route.ts` gains `get_bug_intelligence_metrics` action (read-only). Requires `GITHUB_WEBHOOK_SECRET` secret + manual webhook registration on `jreedy33/Fit33` (gh api command documented in the edge function header).
- Phase 5 (planned): server-side dSYM symbolication — see `docs/history/PHASE_5_SYMBOLICATION_PLAN.md`.

---

## Legacy / Bulk Ledger (Q2-85, Sprint 8 — 2026-04-27)

This section documents `supabase/*.sql` files that are **intentionally not in
the numbered release-train above**. They are either pre-`YYYYMMDD_` legacy
migrations, one-shot bulk data loads, or read-only auditors. They live on
disk for audit / history only — do NOT re-run on prod without checking
§Process below first.

### Pre-`YYYYMMDD_` era (historic)

Ship order is lost; effects have been absorbed / superseded by the numbered
release-train migrations above. Kept for historical audit.

| File | Category | Notes |
|------|----------|-------|
| `challenge_rpc_functions.sql` | Challenges (legacy) | Canonical owners for most of these RPCs are now the `fix_*` files listed in §Duplicated Function Definitions above. |
| `challenge_type_migration.sql` | Challenges (legacy) | Superseded by `fix_challenge_cascade_delete.sql` + `fix_challenge_participants.sql`. |
| `challenge_reactions.sql` | Challenges (legacy) | Schema live; no further changes expected. |
| `community_challenges_migration.sql` | Challenges (legacy) | Schema live; later hotfixes consolidated. |
| `community_friends_gating.sql` | Friends (legacy) | Gating now enforced by RPCs in `create_friend_rpc_functions.sql` + `fix_friend_safety.sql`. |
| `create_friend_rpc_functions.sql` | Friends (legacy) | Canonical RPC shapes live; later hotfixes add IDOR guards. |
| `fix_friend_safety.sql` | Friends (legacy) | Layered on by `fix_comprehensive_audit.sql`. |
| `friend_request_system.sql` | Friends (legacy) | Superseded by `friend_request_notifications.sql`. |
| `friend_request_notifications.sql` | Friends (legacy) | Canonical owner of `send_friend_request`. |
| `cascade_delete_incomplete_profiles.sql` | Auth / profile | Paired with `cleanup_incomplete_onboarding.sql`. |
| `cleanup_incomplete_onboarding.sql` | Auth / profile | pg_cron-driven cleanup job; still live. |
| `cleanup_test_accounts.sql` | Ops | Manual cleanup helper. Run ad hoc only. |
| `complete_account_deletion.sql` | Auth / profile | Canonical owner of `delete_user_account`. |
| `daily_quests_migration.sql` | Daily Quests | Superseded by 2026-04-xx quest migrations (#54, #57–#59). |
| `daily_quests_v2_migration.sql` | Daily Quests | Superseded by 2026-04-xx quest migrations. |
| `fix_account_deletion.sql` | Auth / profile | DELETED 2026-04-17 (see §Duplicated Function Definitions). |
| `fix_ambiguous_columns.sql` | Challenges (legacy) | Canonical owner of `log_challenge_progress`. |
| `fix_cardio_workouts_constraint.sql` | Cardio | Canonical; absorbed into release-train. |
| `fix_challenge_cascade_delete.sql` | Challenges (legacy) | Canonical owner of cascade policies. |
| `fix_challenge_participants.sql` | Challenges (legacy) | Canonical owner of participant constraints. |
| `fix_comprehensive_audit.sql` | Multi | Canonical owner of several friend RPCs. |
| `fix_contact_matching_rls.sql` | Contacts | Canonical RLS for contact discovery. |
| `fix_create_group_challenge.sql` | Challenges (legacy) | Canonical owner of `create_group_challenge`. |
| `fix_data_relationships.sql` | Multi | FK + orphan cleanup. |
| `fix_group_challenge_timezone.sql` | Challenges (legacy) | Canonical owner of `get_active_group_challenges` + `log_group_challenge_progress`. |
| `fix_leave_group_challenge.sql` | Challenges (legacy) | Canonical owner of `leave_group_challenge`. |
| `fix_materialized_view.sql` | Multi | One-shot MV refresh. |
| `fix_private_realtime_publication.sql` | Realtime | Private challenge realtime bootstrap (missed `private_challenge_chat` — closed by 20260426_sprint7_security_hygiene.sql). |
| `fix_trigger_conflicts.sql` | Auth / profile | Canonical owner of `cleanup_auth_on_profile_delete`. |
| `global_food_popularity.sql` | Nutrition | Canonical schema live. |
| `private_challenges_migration.sql` | Private Challenges | Canonical schema; realtime bootstrap above. |
| `program_templates_migration.sql` | Programs | Canonical schema live. |
| `refresh_exercise_view.sql` | Exercises | Manual MV refresh helper. |
| `verify_critical_functions.sql` | Audit | Read-only verifier. |
| `weekly_leagues_migration.sql` | Weekly Leagues | Canonical schema; later hotfixes layered on. |

### Bulk exercise data loads (one-shot)

These files ship thousands of `INSERT … ON CONFLICT` statements for the
exercise library. Already applied on prod; do not re-run unless re-seeding
a fresh Supabase project.

| Pattern | Count | Purpose |
|---------|-------|---------|
| `exercise_replace_{01..15}.sql` | 15 | Generational CSV re-import (15 batches). |
| `update_exercises_{csv,batch2,batch3,final_fixed}.sql` | 4 | Incremental CSV corrections. Canonical final batch is `update_exercises_final_fixed.sql`. |
| `exercises_update_*.sql`, `update_2_exercises_*.sql` | misc | Targeted string fixes (lever names, spaces, etc.). |

### Auditors / verifiers (read-only)

| File | Purpose |
|------|---------|
| `audit_before.sql` | Baseline snapshot; runs before `20260320_*` audit remediation. |
| `audit_after.sql` | 7-test verification suite; runs after. |
| `verify_query_performance.sql` | Indexes-present audit; extend when adding hot-path indexes. See DB-5 entry above. |
| `sim_test_helpers.sql` | Fixture / simulation helpers for automated QA only. Never ship to prod. |
| `migrations/*.sql` | Legacy CLI-style migrations (pre-SQL Editor workflow); canonical files are all in `supabase/*.sql` today. |

---

## Process for New Migrations

1. Create a new file: `YYYYMMDD_description.sql`
2. Wrap DDL in `BEGIN; ... COMMIT;` for transactional safety
3. DROP all overloads before `CREATE OR REPLACE FUNCTION` (see supabase-rules §12)
4. Add `IF NOT EXISTS` to every `CREATE INDEX` / `CREATE TABLE` for idempotency
5. Add the file to the numbered release-train above with status 🆕
6. Test in a staging project first
7. Deploy via Supabase SQL Editor
8. Update status to ✅ Deployed
