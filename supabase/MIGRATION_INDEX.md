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
| 10 | `fix_account_deletion.sql` | ✅ Deployed | `delete_user_account()` RPC + auth cascade trigger |
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
| `delete_user_account` | `complete_account_deletion.sql` | `fix_account_deletion.sql` |
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

---

## Process for New Migrations

1. Create a new file: `YYYY_MM_DD_description.sql`
2. Wrap DDL in `BEGIN; ... COMMIT;` for transactional safety
3. Add the file to this index with status 🆕
4. Test in a staging project first
5. Deploy via Supabase SQL Editor
6. Update status to ✅ Deployed
