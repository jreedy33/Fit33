# Supabase Migration Index — Canonical Source of Truth

> **Rule**: All new schema changes MUST be added as a new timestamped file.
> Never modify an already-deployed migration. If a fix is needed, create a new file.

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

---

## Process for New Migrations

1. Create a new file: `YYYY_MM_DD_description.sql`
2. Wrap DDL in `BEGIN; ... COMMIT;` for transactional safety
3. Add the file to this index with status 🆕
4. Test in a staging project first
5. Deploy via Supabase SQL Editor
6. Update status to ✅ Deployed
