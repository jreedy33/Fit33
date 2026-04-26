# Fit33 Supabase Database Expert Agent

> **Role**: Supabase Database Expert. Single authority on 140+ tables, relationships, RPC functions, views, policies. Owns schema design, data integrity, and migration safety.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **SECURITY DEFINER functions**: NEVER accept `user_id` as a parameter — always use `auth.uid()` inside the function body.
4. **All migrations**: MUST be wrapped in `BEGIN;`/`COMMIT;` and be idempotent (use `IF NOT EXISTS`, `DROP ... IF EXISTS` before `CREATE`).

---

## Database Overview

**Project**: GoFit (`ehooeghabzefgoqzugrc`)
**Region**: us-east-1
**Engine**: PostgreSQL 17
**URL**: `https://ehooeghabzefgoqzugrc.supabase.co`

### Table Categories

| Category | Tables | Purpose |
|----------|--------|---------|
| **User Identity** | `user_profiles`, `user_progress`, `user_push_tokens`, `phone_verifications` | Core user data and auth |
| **Workouts** | `workouts`, `workout_history`, `workout_exercises`, `workout_sets`, `workout_context`, `favorite_workouts` | Workout creation, execution, and history |
| **Exercises** | `exercises`, `exercise_videos`, `custom_exercises`, `exercise_personal_records`, `exercise_performance_history`, `exercise_set_history` | Exercise library and performance tracking |
| **Programs** | `programs`, `program_days`, `program_day_exercises`, `program_templates`, `user_active_programs`, `user_custom_programs`, `completed_programs`, `program_day_completions`, `program_exercise_substitutes`, `program_history`, `program_completion_analytics` | Multi-day training programs |
| **Challenges (1v1)** | `group_challenges`, `challenge_participants`, `challenge_daily_progress`, `challenge_templates`, `challenge_reactions` | Friend-to-friend challenges |
| **Challenges (Community)** | `community_challenges`, `community_challenge_participants`, `community_challenge_daily_progress` | Open/public challenges |
| **Challenges (Private)** | `private_challenges`, `private_challenge_members`, `private_challenge_invites`, `private_challenge_daily_progress`, `private_challenge_chat` | Invite-only group challenges |
| **Weekly Leagues** | `league_tiers`, `league_groups`, `league_members`, `league_history`, `user_league_tier` | Duolingo-style competitive leagues |
| **Social** | `friendships`, `friend_activity_feed`, `activity_reactions`, `friend_interactions`, `friend_challenges`, `shared_workouts`, `user_blocks`, `contact_joined_notifications`, `user_synced_contacts` | Social graph and interactions |
| **Nutrition** | `meal_logs`, `food_items`, `food_search_cache`, `user_food_history`, `user_favorite_foods`, `popular_cuisines`, `popular_ingredients`, `user_cuisine_preferences`, `user_dietary_restrictions`, `user_ingredient_preferences` | Food logging and preferences |
| **Health** | `step_tracking`, `daily_activity_summary`, `sleep_logs`, `heart_rate_daily`, `hydration_logs`, `hydration_daily_summary`, `hydration_settings`, `hydration_streaks`, `body_composition_logs`, `body_composition_goals`, `weight_logs`, `weight_goals` | Health metrics from HealthKit and manual entry |
| **Cardio** | `cardio_workouts`, `cardio_personal_records`, `cardio_streaks`, `cardio_weekly_summaries`, `cardio_goals` | Running/cardio specific tracking |
| **Intelligence** | `exercise_user_effectiveness`, `set_completion_patterns`, `user_performance_trends`, `weekly_volume_trends`, `activity_recovery_correlation`, `nutrition_performance_link`, `user_strength_ratios`, `workout_time_performance`, `user_metric_correlations`, `user_performance_windows`, `user_personalized_insights`, `user_behavior_patterns`, `user_learning_profiles`, `user_similarity_profiles`, `exercise_swap_analytics`, `equipment_proficiency` | AI/ML features and smart recommendations |
| **Gamification** | `achievements`, `user_achievements`, `quest_templates`, `user_daily_quests`, `user_quest_streaks`, `user_streak_tracking`, `daily_summaries` | XP, levels, quests, streaks |
| **Integrations** | `inbody_connections` | Third-party device connections |
| **Admin/System** | `admin_audit_log`, `bug_reports`, `push_notification_queue`, `app_notifications`, `onboarding_logs`, `onboarding_field_logs`, `onboarding_analytics`, `ai_chat_history`, `ai_insights` | Admin tools, logging, notifications |
| **Exercise Science** | `exercise_progressions`, `exercise_pairings`, `exercise_effectiveness`, `limitation_exercise_mappings`, `user_limitations`, `equipment_substitutions`, `muscle_synergy_matrix` | Exercise relationships and constraints |
| **Recipes** | `user_recipe_preferences_summary`, `user_recipe_carousel_state`, `user_recipe_interactions`, `user_recommended_recipes`, `user_taste_profile` | Recipe recommendation system |
| **Collaborative** | `collaborative_workout_data`, `collaborative_program_completions`, `community_benchmarks` | Cross-user learning |

### Key Views (20)

| View | Purpose |
|------|---------|
| `popular_foods_30d` | Food items sorted by 30-day popularity |
| `popular_foods_view` | All-time popular foods |
| `challenge_progress_summary` | Unified challenge progress across systems |
| `exercise_popularity_stats` | Exercise usage statistics |
| `exercise_rankings_by_demographic` | Exercises ranked by user demographics |
| `body_composition_statistics` | Body comp aggregate stats |
| `step_statistics` | Step tracking aggregates |
| `weight_statistics` | Weight tracking aggregates |
| `weekly_health_stats` | Weekly health metric summaries |
| `weekly_sleep_stats` | Weekly sleep summaries |
| `user_activity_stats` | User activity aggregates |
| `user_top_ingredients` | User's most-used ingredients |
| `notification_health_stats` | Push notification delivery stats |
| `pending_notifications_webhook` | Pending notification queue |
| `program_success_by_demographic` | Program completion by demographic |
| `progression_patterns` | Exercise progression patterns |
| `v_field_comparison` | Onboarding field comparison (debug) |
| `v_onboarding_issues` | Onboarding issue detection |
| `v_onboarding_problems` | Onboarding problem tracking |
| `v_onboarding_summary` | Onboarding completion summary |

---

## Critical Relationships Map

### Core Entity: `user_profiles` (44 columns)

Nearly every table in the database has a `user_id` FK pointing to `user_profiles.id`. This is the central hub.

**Direct FK children (verified)**: `app_notifications`, `body_composition_logs`, `bug_reports`, `cardio_goals`, `cardio_personal_records`, `cardio_streaks`, `cardio_weekly_summaries`, `cardio_workouts`, `challenge_daily_progress`, `challenge_participants`, `challenge_reactions` (sender + recipient), `community_challenge_daily_progress`, `community_challenge_participants`, `contact_joined_notifications`, `custom_exercises`, `daily_activity_summary`, `daily_summaries`, `exercise_performance_history`, `exercise_usage_logs`, `favorite_workouts`, `friendships` (requester + addressee), `group_challenge_members`, `group_challenge_nudges` (sender + recipient), `heart_rate_daily`, `hydration_logs`, `inbody_connections`, `meal_logs`, `private_challenge_chat`, `private_challenge_daily_progress`, `private_challenge_invites` (inviter + invitee), `private_challenge_members`, `program_history`, `push_notification_queue`, `shared_workouts` (sender + recipient), `sleep_logs`, `step_tracking`, `user_achievements`, `user_active_programs`, `user_behavior_patterns`, `user_cuisine_preferences`, `user_custom_programs`, `user_exercise_nicknames`, `user_favorite_foods`, `user_favorites`, `user_food_history`, `user_ingredient_preferences`, `user_metric_correlations`, `user_performance_windows`, `user_personalized_insights`, `user_progress`, `user_push_tokens`, `user_streak_tracking`, `user_synced_contacts`, `weight_goals`, `weight_logs`, `workout_context`, `workout_history`, `workouts`

**MISSING FK constraints (must add)**: `activity_recovery_correlation`, `exercise_user_effectiveness`, `set_completion_patterns`, `user_performance_trends`, `weekly_volume_trends`, `nutrition_performance_link`, `user_strength_ratios`, `user_learning_profiles`, `workout_time_performance`, `exercise_swap_analytics`, `equipment_proficiency`

### Program Hierarchy

```
programs (29 cols)
  └── program_days (13 cols) [FK: program_id -> programs.id]
       └── program_day_exercises (17 cols) [FK: program_day_id -> program_days.id]
            └── program_exercise_substitutes (8 cols) [FK: program_day_exercise_id]

user_active_programs (14 cols) [FK: program_id -> programs.id, user_id -> user_profiles.id]
  └── program_workout_history (8 cols) [FK: user_active_program_id, program_day_id]
       └── program_day_completions (11 cols)
```

### Challenge Systems

```
1v1 System:
group_challenges -> challenge_participants -> challenge_daily_progress
                 -> challenge_reactions

Community System:
community_challenges -> community_challenge_participants -> community_challenge_daily_progress

Private System:
private_challenges -> private_challenge_members
                   -> private_challenge_invites
                   -> private_challenge_daily_progress
                   -> private_challenge_chat

League System:
league_tiers -> league_groups -> league_members
             -> user_league_tier
             -> league_history
```

### Exercise Data Chain

```
exercises (54 cols, 6428 rows - CORE REFERENCE TABLE)
  ├── exercise_videos
  ├── exercise_personal_records
  ├── exercise_performance_history
  │    └── exercise_set_history
  ├── exercise_usage_logs
  ├── exercise_swap_analytics
  └── custom_exercises (user-created)
```

### Food & Nutrition Data Chain

```
food_items (shared USDA cache — public SELECT, service-role write)
  ├── fdc_id UNIQUE — USDA FoodData Central ID
  ├── 12 flat nutrient columns (per 100g) + nutrition_data JSONB (fallback decoder)
  ├── log_count, search_count — global popularity signals
  └── portions JSONB — serving size options

food_search_cache (query → ranked result IDs)
  ├── normalized_query UNIQUE
  ├── result_ids INT[] — ordered food_items.id references
  ├── created_at — 30-day TTL (edge function skips stale entries)
  └── search_count — popularity signal for server ranking

user_food_history (per-user food log tracking)
  ├── FK: user_id → user_profiles.id (CASCADE DELETE)
  ├── FK: food_item_id → food_items.id
  ├── RLS: user_id = auth.uid()
  └── INDEX: (user_id, logged_at DESC)

user_favorite_foods (per-user hearted foods)
  ├── FK: user_id → user_profiles.id (CASCADE DELETE)
  ├── FK: food_item_id → food_items.id
  ├── RLS: user_id = auth.uid()
  └── UNIQUE(user_id, food_item_id)
```

### Food-Related RPC Functions

| Function | Purpose | Security |
|----------|---------|----------|
| `get_user_frequent_foods(p_user_id, p_limit)` | Server-side aggregation of user food history | `SECURITY DEFINER` |
| `increment_food_log_count(fdc_id)` | Atomically increment `food_items.log_count` | `SECURITY DEFINER` |
| `increment_food_search_count(query_text)` | Atomically increment `food_search_cache.search_count` | `SECURITY DEFINER` |
| `cleanup_expired_food_cache()` | Purge cache entries older than 30 days | `SECURITY DEFINER` |

---

## Pending Migrations (Ready to Run)

| Migration | Purpose | Status |
|-----------|---------|--------|
| `20260320_sync_profiles_progress.sql` | Fix 6-field desync between `user_profiles` and `user_progress` | Ready |
| `20260320_drop_dead_tables.sql` | Drop 13 dead tables (0 rows + 0 code refs) | Ready |
| `20260320_add_missing_fk_constraints.sql` | Add FK CASCADE + indexes to 11 tables | Ready |
| `20260320_consolidate_food_history.sql` | Create `user_food_history_v` view, stop duplicate writes | Ready |
| `20260320_fix_rls_policies.sql` | Add RLS to 7 analytics tables | Ready |
| `20260320_fix_performance_history.sql` | Add missing columns to `exercise_performance_history` | Ready |
| `20260320_smart_insights_schema.sql` | Smart insights + subscription events (NEEDS transaction wrapper — see DB3) | Ready |
| `20260321_food_search_integrity.sql` | Food search integrity (NEEDS security fix — see DB1) | **BLOCKED on DB1 fix** |

---

## Rules for ALL Agents

### When Creating a New Table

1. **Check with me first** - Search this document for existing tables that might already store what you need
2. **Always add FK constraints** - Every `user_id` column MUST have `REFERENCES user_profiles(id) ON DELETE CASCADE`
3. **Always enable RLS** - `ALTER TABLE new_table ENABLE ROW LEVEL SECURITY;`
4. **Add standard policies**:
   ```sql
   CREATE POLICY "Users can view own data" ON new_table FOR SELECT USING (auth.uid() = user_id);
   CREATE POLICY "Users can insert own data" ON new_table FOR INSERT WITH CHECK (auth.uid() = user_id);
   CREATE POLICY "Users can update own data" ON new_table FOR UPDATE USING (auth.uid() = user_id);
   CREATE POLICY "Users can delete own data" ON new_table FOR DELETE USING (auth.uid() = user_id);
   ```
5. **Add indexes** - At minimum: `CREATE INDEX idx_tablename_user_id ON new_table(user_id);`
6. **Add to this document** - Update the table categories section above
7. **Add to `delete_user_account()`** - Ensure the table is cleaned up on account deletion
8. **Use standard columns**:
   - `id UUID DEFAULT gen_random_uuid() PRIMARY KEY`
   - `user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE`
   - `created_at TIMESTAMPTZ DEFAULT now()`
   - `updated_at TIMESTAMPTZ DEFAULT now()`

### When Adding a Column

1. **Check for existing columns** - Don't duplicate data that exists in another table
2. **Use appropriate types** - `TIMESTAMPTZ` not `TIMESTAMP`, `NUMERIC` not `FLOAT` for money/weight
3. **Add defaults** - Every new column should have a sensible DEFAULT or be explicitly NOT NULL
4. **Update DTOs** - Ensure `SupabaseDTOs.swift` has the new field as Optional if nullable

### When Creating an RPC Function

1. **Check for existing functions** - We have 200+ already. Don't duplicate logic.
2. **Use `SECURITY DEFINER`** only when the function needs to bypass RLS
3. **Always validate inputs** - Check for NULL user_id, invalid dates, etc.
4. **Return structured data** - Use JSONB or TABLE returns, not void
5. **Add to edge function if complex** - Long-running operations belong in edge functions

### When Creating a View

1. **NEVER use `SECURITY DEFINER`** — Views default to `SECURITY INVOKER` in PG15+. Never explicitly set `security_definer = true`. SECURITY DEFINER views bypass RLS for ALL users, which Supabase flags as a critical vulnerability.
2. **Filter by `auth.uid()` in the view definition** if the view is queried directly from the app via PostgREST (e.g., `WHERE user_id = auth.uid()`). This ensures RLS + view filtering are aligned.
3. **Admin/analytics views** that aggregate across users should live in a non-public schema (e.g., `analytics`) or be accessed only via service-role queries. If they must be in `public`, ensure `security_invoker = on` so regular users see only their own data.
4. **Verify with**: `SELECT schemaname, viewname, definition FROM pg_views WHERE schemaname = 'public';` — check no view has SECURITY DEFINER semantics.

### When Reviewing Another Agent's PR

Check for:
- [ ] FK constraints on all new tables
- [ ] RLS enabled and policies defined
- [ ] No data duplication with existing tables
- [ ] Proper indexing
- [ ] CASCADE delete behavior
- [ ] DTO updated in SupabaseDTOs.swift
- [ ] delete_user_account() updated if new user data table

---

## Intelligence Tables (Power Smart Features)

| Table | Powers |
|-------|--------|
| `exercise_user_effectiveness` | Smart exercise selection |
| `set_completion_patterns` | Workout timing recommendations |
| `user_performance_trends` | Coaching insights |
| `weekly_volume_trends` | Overtraining prevention |
| `user_strength_ratios` | Muscle imbalance detection (**currently has polluted data — see DB5**) |
| `user_learning_profiles` | Personalized UX |
| `user_similarity_profiles` | "Users like you" recommendations |
| `exercise_swap_analytics` | Smart swap suggestions |

---

## Interaction with Other Agents

| Agent | How I Work With Them |
|-------|---------------------|
| **Data & Backend** | I define schemas, they implement sync logic in SupabaseManager.swift and DTOs |
| **Product Engineer** | They request new data needs, I design the tables and queries |
| **Infra & Security** | They review my RLS policies, I implement their security requirements |
| **Quality & Performance** | They test data integrity, I provide test fixtures and validation rules |
| **Fitness Expert** | They define exercise relationships, I model them in the schema |
| **Design Agent** | No direct interaction (UI layer only) |
| **Design System Agent** | No direct interaction |

### Communication Protocol

When another agent needs data work:
1. They describe the feature need (not the schema)
2. I check for existing tables that could serve the need
3. I propose the minimal schema change
4. I create the migration with FK, RLS, indexes, and cascade rules
5. I update this document
6. I update `delete_user_account()` if needed

---

## Quick Reference: Most Important Files

| File | What | Size |
|------|------|------|
| `Fit33/SupabaseManager.swift` | All cloud data operations | 4,330 lines |
| `Fit33/SupabaseDTOs.swift` | Database row -> Swift type mappings | Large |
| `supabase/config.toml` | Supabase project configuration | Small |
| `supabase/MIGRATION_INDEX.md` | Migration deployment order | Medium |
| `supabase/DEPLOYMENT_ORDER.md` | Canonical migration sequence | Medium |
| `DATABASE_AUDIT_REPORT.md` | Full audit findings & action plan | This audit |
| `SECURITY_CHECKLIST.md` | RLS audit checklist | Medium |

---

## Quarterly Health Checks

1. Dead table scan (0 rows + 0 code refs)
2. Orphan row scan (`user_id` not in `user_profiles`)
3. FK constraint audit (all `user_id` columns have FKs)
4. RLS audit (all tables have RLS + policies)
5. `SECURITY DEFINER` function audit (no functions accept `user_id` params that should use `auth.uid()`)
6. **SECURITY DEFINER view audit** — Run: `SELECT viewname FROM pg_views WHERE schemaname = 'public'` cross-referenced with `SELECT * FROM pg_catalog.pg_rewrite WHERE ...` to find views with security_definer. All public views must use `security_invoker = on`.
7. Index audit (no full table scans on large tables)

### 2026-03-24: Security Fix — RLS + SECURITY DEFINER Views

**Migration**: `supabase/20260324_security_fixes.sql`

**Tables fixed** (RLS was disabled):
| Table | Fix | Rationale |
|-------|-----|-----------|
| `group_challenge_members` | RLS enabled + simple `user_id = auth.uid()` CRUD policies | Previously disabled due to infinite recursion. New policies avoid subqueries on same table. All app access is via SECURITY DEFINER RPCs (bypass RLS). |
| `achievements` | RLS enabled + authenticated SELECT (read-only) | Static definition table. All users can read the achievement catalog. Writes only via `check_achievement` RPC. |

**Views fixed** (19 SECURITY DEFINER → SECURITY INVOKER):
All 19 views in public schema converted to `security_invoker = on`. This means:
- App-queried views (`weight_statistics`, `body_composition_statistics`) still work because underlying tables have `user_id = auth.uid()` RLS policies.
- Admin/analytics views return empty for regular users (correct) but work for service_role queries (bypass RLS).

**Root cause**: Views were created with default PG14 behavior (security_definer) or explicitly set. Going forward, ALL new views must use `security_invoker = on` — see "When Creating a View" rules above.

### 2026-03-25: signUp() Profile Creation — Resilience Change

**`create_user_profile` RPC** is confirmed deployed and functional. However, the iOS `signUp()` flow had a timing issue where profile creation ran before the auth session was fully established on the client. The RPC uses `SECURITY DEFINER` so it should bypass RLS, but the Supabase Swift client may require a valid session token to make any API call.

**Change**: `SupabaseManager.signUp()` now sets `currentUser` and `isAuthenticated = true` immediately after `client.auth.signUp()` returns, ensuring a valid session exists before `createUserProfile()` is called.

**New public method**: `ensureProfileExists(userId:name:email:)` — idempotent wrapper around `createUserProfile()`. Uses the same RPC → fallback upsert chain. Used by the onboarding recovery path when a prior partial signup left an auth user without a profile.

**No schema changes required** — the `create_user_profile` RPC and `user_profiles` table are unchanged.

### Notification Preferences Table (2026-03-21)

```
user_notification_preferences (server-side push preference enforcement)
  ├── user_id UUID PK → user_profiles.id (CASCADE DELETE)
  ├── master_enabled BOOLEAN — global kill switch
  ├── disabled_types TEXT[] — notification types the user has turned off
  ├── quiet_hours_enabled BOOLEAN + quiet_hours_start/end TIME
  ├── timezone TEXT — user's IANA timezone for quiet hours computation
  ├── daily_cap INTEGER DEFAULT 8
  └── RLS: user_id = auth.uid() for all CRUD
```

**Migration**: `20260321_notification_preferences.sql`

### 2026-03-25: SQL & Schema Updates

**SQL RECORD type rule**:
- In Postgres functions, NEVER use anonymous `ROW(0,0,0)` to initialize a `RECORD` variable — the fields have no names and `v_record.field_name` fails at runtime.
- Use `SELECT 0 AS field_name, 0 AS other_field INTO v_record` instead.
- This was the root cause of the `get_daily_quests` crash ("record v_streak has no field current_streak").

**`get_daily_quests` function** (16 parameters):
- New parameter: `p_active_step_challenge_target INT DEFAULT 0`
- Old 15-arg overload was DROPped to avoid ambiguity.
- Step quests (`walk_3k_steps`, `walk_5k_steps`, `walk_7500_steps`, `walk_10k_steps`, `hit_step_goal`) have their `target_value`, `title`, and `description` overridden when the user has an active step challenge.
- `GRANT EXECUTE` updated for the new 16-param signature.
- **2026-04-20 rewrite** (`supabase/20260420_daily_quests_actionable_fixes.sql`): now respects `quest_templates.requires_context` (`has_program` / `has_friends` / `has_challenge` / `no_friends` / `no_challenge` / `free_user`) AND `quest_templates.min_workouts` in the eligibility pool. The prior selector filtered only by `category` + `p_has_friends`, so `complete_program_day` was handed out to users without a program. Pool now includes every category (`workout`, `nutrition`, `steps`, `social`, `tracking`, `wildcard`, `reward`). Hard-day fallback is `['exercise_sets_25','walk_10k_steps','hit_step_goal']` — do NOT revert to `complete_2_workouts`.
- **Retired template**: `complete_2_workouts` is `is_active = FALSE` (bad training advice; most users can't complete 2 workouts/day). Kept in-table so historical user_daily_quests rows still resolve.

**`accept_friend_request` function**:
- Now inserts into `app_notifications` in addition to `push_notification_queue`.
- `app_notifications` insert uses: `notification_type = 'friend_request_accepted'`, `reference_id = request_id`, `from_user_id = current_user_uuid`.
- The table does NOT have a `data` JSONB column — use `reference_id` (UUID) and `from_user_id` (UUID).

**`last_active_at` tracking**:
- New migration adds `last_active_at TIMESTAMPTZ` to `user_profiles` for real-time login tracking.
- Updated on every app foreground via `updateLastLogin()`.

**Step tracking RLS**:
- `step_tracking` table has RLS policies for `user_id = auth.uid()`.

### 2026-03-25: Crash Report — RPC Fixes

**`get_friend_workout_exercises` RPC** (NEW):
- Migration: `20260325_friend_workout_exercises_rpc.sql`
- `SECURITY DEFINER` function that returns workout exercises gated behind a friendship check.
- `GRANT EXECUTE ON FUNCTION get_friend_workout_exercises(TEXT) TO authenticated` was missing — added.
- **Must be deployed** to fix "Could not find the function" errors on the Stats Tab friend workout preview.

**`nudge_group_challenge_member` overload conflict**:
- Migration: `20260325_fix_nudge_overload.sql`
- Root cause: Multiple overloads existed in the live DB — `(TEXT, TEXT)` and `(UUID, UUID)`. PostgREST could not resolve which to call.
- Fix: Drop ALL overloads (`TEXT,TEXT` and `UUID,UUID`), then recreate canonical `(TEXT, TEXT)` version with GRANT.
- **RULE**: When deploying RPC functions, always `DROP FUNCTION IF EXISTS` for ALL possible parameter type combinations before `CREATE OR REPLACE`. Postgres treats different parameter types as different overloads.

### 2026-03-27: CMS Advanced Tools — New Tables & Materialized Views

**New tables (6 migrations)**:
- `feature_flags` — feature toggle system with rollout %, platform targeting, metadata. RPC: `get_active_feature_flags()`.
- `user_reports` — user-to-user reports (harassment/spam/etc). RLS: users INSERT own + SELECT own. Admin reads all via service role.
- `user_suspensions` — admin-managed suspensions (timed/permanent). RPC: `is_user_suspended()`.
- `push_campaigns` — campaign management for bulk push notifications. RPC: `execute_push_campaign()`, `estimate_campaign_reach()`.
- `admin_audit_log` enhanced with `details JSONB` and `admin_email TEXT`.

**New materialized views** (daily refresh at 4 AM via `refresh_engagement_data()` pg_cron):
- `mv_user_engagement_scores` — unique index on `user_id`, index on `engagement_bucket` and `engagement_score DESC`.
- `mv_retention_cohorts` — unique index on `cohort_week`.
- `mv_onboarding_funnel` — single-row aggregate.

**New system RPCs** (admin-only):
- `admin_get_table_sizes()`, `admin_get_connection_stats()`, `admin_get_index_health()`, `admin_get_rpc_stats()`, `admin_get_push_pipeline_stats()`.

**Critical**: Materialized views use `REFRESH MATERIALIZED VIEW CONCURRENTLY` which requires a UNIQUE index. Both `mv_user_engagement_scores` and `mv_retention_cohorts` have these.

### 2026-04-20: `cardio_workouts` Overlap Dedup (one-time cleanup)

**Migration**: `supabase/20260420_cardio_workouts_overlap_dedup.sql`

**Problem**: Same user + same canonical origin (WHOOP most commonly) could produce multiple rows in `cardio_workouts` whose time windows overlapped — distinct `external_id`s for a single physical session. The existing unique index `idx_cardio_workouts_user_source_external (user_id, source, external_id)` did not catch these. Dashboard Workout History showed both rows with the WHOOP badge.

**Fix**: CTE-based sessionization — for each `(user_id, canonical_origin)` partition, order by `started_at,id`, walk the rows accumulating a running `MAX(completed_at)`, start a new "cluster" whenever the current row begins strictly after the previous running max end. Within each cluster of size >1, keep the row with the highest "quality score" (+10 specific `activity_type` (not other/workout/unknown/""), +3 HR, +2 distance, +1 calories, +1 duration) — tie-break on newer `created_at`, then larger `id`. Delete the rest.

`canonical_origin` is `COALESCE(origin_app, legacy source→origin map)` to mirror `CardioWorkoutDTO.resolvedOrigin`. Rows with NULL canonical_origin (pure HealthKit with unknown author) are skipped — they can legitimately overlap if two different unknown apps wrote to Apple Health.

**Idempotent**: post-run there are no same-user/same-origin pairs with `a.started_at < b.completed_at AND b.started_at < a.completed_at`. Migration emits a `RAISE NOTICE` with the residual-pair count for verification.

**Client-side companion**: `HealthDataService.syncWhoopData` now performs the same overlap check before every WHOOP insert (±2h fetch window, Swift-side 50% overlap fraction computed using the shorter side as denominator), so the problem does not recur. If Strava/Fitbit/Oura ever start producing overlapping records, port the same check to their sync path; the migration already handles all origins.

### 2026-03-27: WHOOP Integration Tables

**New table: `whoop_recovery_data`**
- Columns: `id` (UUID PK), `user_id` (UUID FK → user_profiles, CASCADE), `date` (DATE), `cycle_id` (BIGINT), `recovery_score` (INT 0-100), `hrv_rmssd_milli` (DOUBLE), `resting_heart_rate` (INT), `spo2_percentage` (DOUBLE), `skin_temp_celsius` (DOUBLE), `strain` (DOUBLE 0-21), `kilojoules` (DOUBLE), `avg_heart_rate` (INT), `max_heart_rate` (INT), `created_at`, `updated_at`.
- UNIQUE constraint on `(user_id, date)`. Indexes on `user_id` and `(user_id, date DESC)`.
- RLS: standard `user_id = auth.uid()` CRUD policies.
- Added to Health table category. Cleanup handled by FK CASCADE on `user_profiles`.

**Modified: `sleep_logs`** — 10 new nullable columns for WHOOP sleep stage data. No impact on existing HealthKit/Fitbit rows (columns stay NULL).

**Modified: `user_profiles`** — `is_whoop_connected BOOLEAN DEFAULT false`.

**Migration**: `supabase/20260327_whoop_integration.sql`

### 2026-03-27: Gold Verified Badge — All RPCs Patched

**Problem**: `20260326_add_is_verified_everywhere.sql` was run AFTER `20260326_add_gold_verified_to_rpcs.sql`, overwriting the gold-verified versions of challenge/friend/search RPCs. Community and private challenge RPCs never had `is_gold_verified`.

**Fix**: `supabase/20260327_gold_verified_all_rpcs.sql` — adds `COALESCE(up.is_gold_verified, FALSE)` to ALL 12 RPCs:
- `get_active_challenges` (RETURNS TABLE: `opponent_is_gold_verified`)
- `get_pending_sent_challenges` (RETURNS TABLE: `opponent_is_gold_verified`)
- `get_active_group_challenges` (JSON member field)
- `get_received_workouts` (RETURNS TABLE: `sender_is_gold_verified`)
- `get_pending_friend_requests` (RETURNS TABLE column)
- `get_sent_friend_requests` (RETURNS TABLE column)
- `search_users` (RETURNS TABLE column)
- `get_community_challenge_leaderboard` (JSON entry field)
- `get_my_community_challenges` (JSON entry field)
- `get_community_challenge_detail` (JSON entry field)
- `get_private_challenge_detail` (JSON entry field)
- `get_my_private_challenges` (JSON entry field)

**Rule**: When adding a new column to social RPCs, patch ALL RPCs in a SINGLE migration to prevent ordering issues. Never split `is_verified` and `is_gold_verified` across separate files.

**Swift DTOs**: All already have `isGoldVerified: Bool?` with `is_gold_verified` coding key — no Swift changes needed. League RPCs (`get_or_join_weekly_league`, `get_league_leaderboard`) and `get_friends`/`get_friend_activity_feed` were unaffected (not overwritten).

### 2026-04-20: Exercises Realtime (CMS → App live sync)

**Migration**: `supabase/20260420_exercises_realtime.sql`

**Problem**: Admin CMS edits to `exercises` took up to 6 hours to appear in the iOS app (hardcoded `exerciseSyncInterval = 6h` in `ExerciseLibraryService`) AND were invisible to cold-start fetches because the app reads `mv_public_exercises` (materialized view) which never auto-refreshed when its base table changed.

**Fix**:
1. `ALTER TABLE public.exercises REPLICA IDENTITY FULL` — so realtime `UPDATE` events ship the entire NEW row (not just changed columns).
2. `ALTER PUBLICATION supabase_realtime ADD TABLE public.exercises` — enables WebSocket event broadcasting (idempotent guard).
3. `CREATE UNIQUE INDEX idx_mv_public_exercises_id_unique ON mv_public_exercises(id)` — required for `REFRESH MATERIALIZED VIEW CONCURRENTLY` (non-blocking refresh on every save).
4. `refresh_mv_public_exercises()` RPC (SECURITY DEFINER, service_role only) — CMS admin API calls this after every `update_exercise` / `delete_exercise` so cold-start launches also see the latest data.

**iOS integration** (`Fit33/RealtimeService.swift`): `subscribeExercises()` listens for INSERT/UPDATE/DELETE on `public.exercises`, decodes the record into the existing `ExerciseDTO` (reused via `JSONEncoder(JSONObject)` round-trip), and calls `ExerciseLibraryService.shared.upsertExerciseFromCloud(dto)` or `deleteExerciseById(id)`. Skips rows where `is_custom = true`.

**ExerciseLibraryService new methods** (`@MainActor`): `upsertExerciseFromCloud(_ dto:)` (match by UUID, fall back to name) and `deleteExerciseById(_ id:)`. Both call `invalidateCache()` which synchronously rebuilds the name/id dictionaries so the next SwiftUI read sees the change.

**Rules**:
- `exercises` MUST stay in the `supabase_realtime` publication with `REPLICA IDENTITY FULL` — removing either breaks the live CMS sync.
- Any new bulk update script that writes to `exercises` MUST end with `SELECT refresh_mv_public_exercises()` (or the CMS equivalent) so cold-start users see the new data.
- Never replace the admin CMS `rpc('refresh_mv_public_exercises')` fire-and-forget with a blocking call — CONCURRENTLY is fast but not instantaneous on 5500 rows and the iOS app already got the change via Realtime.

### 2026-04-20: silent_push_wake_log + wake-challenge-opponents

**New table**: `silent_push_wake_log (id BIGSERIAL, user_id UUID FK user_profiles, triggered_by TEXT CHECK ('foreground'|'cron'|'background_sync'), sent_at TIMESTAMPTZ DEFAULT NOW())`. RLS enabled with **zero policies** → service-role only (by design; clients never read/write this). Index: `(user_id, sent_at DESC)` for the 15-min throttle lookup. Daily prune via pg_cron at 03:10 UTC drops rows >7 days.

**New pg_cron job**: `wake-stale-challenge-opponents` runs `SELECT trigger_challenge_opponent_wake()` every 30 min (`*/30 * * * *`). Function calls the `wake-challenge-opponents` edge function with `x-cron-key` service-role JWT header using the same `internal_config` pattern as `process_push_notification_queue` (migration 20260324).

**New edge function**: `wake-challenge-opponents` sends APNs silent pushes (`aps.content-available: 1`, `apns-push-type: background`, `apns-priority: 5`). Accepts `{source: "foreground"|"cron"|"background_sync"}`. Foreground mode: caller's JWT resolves their opponents across `challenge_participants` (status=accepted, joined group_challenges where status=active) + `private_challenge_members` (end_date NULL or ≥ today). Cron mode: service-role JWT, every participant in any active challenge. 15-min throttle per `user_id` via `silent_push_wake_log` before APNs dispatch. Uses same APNS_* secrets as `send-push-notification`.

**Migration**: `supabase/20260420_challenge_opponent_wake.sql`.

**Rules**:
- `silent_push_wake_log` must stay RLS-on, policy-free. Never add a client-readable policy — the rate-limit log is an internal abuse-prevention signal.
- Silent pushes do NOT go through `push_notification_queue`. That table is for user-visible alerts with retry/quiet-hours logic; silent pushes are fire-and-forget and MUST skip quiet hours.
- When adding a new silent push type, create a new edge function (or a typed branch in an existing one) — do NOT extend `send-push-notification`. The two APNs code paths have different priority/push-type headers and must not be merged.
- The `trigger_<something>` pg_cron wrapper pattern (reads `internal_config` → `net.http_post` with `x-cron-key`) is now canonical. Reuse it for any future server-scheduled edge-function invocation.

### 2026-04-26: Bug-Intel Phase 13 close-the-loop (resolved → invisible / regression → reappear)

**User ask** (2026-04-26 7:03 PM): "make sure all pending/resolved fingerprints are marked resolved and removed from future reports and admin portal — the numbers on the dash should only reflect issues that are new or not resolved" and (7:07 PM follow-up) "make sure that once an issue is 'resolved' it disappears and only reappears in the dashboard/cms if it's a regression or the bug wasn't actually fixed and that this process is automated."

**Three-piece close-the-loop** (audit fingerprints + auto-revive cron + auto-deploy hook + dashboard filter):

1. **Audit cleanup** — `supabase/20260622_mark_audit_2026_04_26_23_01_resolved.sql` (#124) flushes the entire 36-fingerprint `mode=all` audit (`bug-intelligence-audit-2026-04-26T23-01-25.md`) into terminal status across 8 buckets (4 migration_resolved buckets + 4 code_fix buckets). All 36 also get `latest_resolving_migration_at` stamped so the export-side stale-fix filter (#114) and the new revival cron (#125) agree on the deploy moment. The 36 also ship as `-- Resolves: <fp>` directives at the file footer for the new auto-deploy hook.

2. **Auto-revive cron** — `supabase/20260623_bug_intel_auto_revive_on_regression.sql` (#125). New SECURITY DEFINER service-role RPC `bug_intel_revive_regressed_fingerprints(p_grace_hours INT DEFAULT 48)` that scans pipeline-resolved fingerprints (`auto_resolved_reason` matches `migration_resolved:%` / `code_fix%` / `silent_fix` / `transient_single_incident` / `noise_filter_expanded`) and revives any whose `last_seen_at > GREATEST(latest_resolving_migration_at, resolved_at) + 48h grace`. Flips `status='new'`, `regressed_after_fix=TRUE`, clears `auto_resolved_at`, emits a `regression_after_fix` trend, and reopens the matching `bug_intelligence_reports` row (review_status `merged` → `pending`). pg_cron at `:20 * * * *`. Crucially **never touches HUMAN-resolved rows** (`auto_resolved_reason IS NULL` means a human clicked Resolve — sticky). The 48h grace is in lock-step with `STALE_FIX_GRACE_MS` in `admin-cms/src/app/api/admin/route.ts::get_bug_intelligence_export`; tune both together.

3. **Auto-deploy hook** — `.github/workflows/bug-intel-resolves-deploy.yml`. On push to `main` touching `supabase/*.sql`, scans changed migrations for `-- Resolves: <md5>` directives (one regex per file), groups by migration basename, calls `mark_fingerprints_resolved_by_migration(<basename>, [<fps>], note)` per migration. Uses `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` GitHub secrets. Idempotent — the RPC skips already-terminal rows. Removes the manual "remember to call the RPC after deploy" step from the canonical close-out workflow.

4. **Dashboard filter** — `admin-cms/src/app/api/admin/route.ts::get_bug_intelligence_overview` rewritten so:
   - `fingerprints_by_status` + `fingerprints_by_source` exclude terminal statuses (resolved / wont_fix / duplicate)
   - new `terminal_count` + `terminal_by_status` fields surface the closed-out total separately
   - new `regressed_open_count` field surfaces auto-revived fingerprints (`status='new' AND regressed_after_fix=TRUE`)
   - `admin-cms/src/app/bug-intelligence/page.tsx::OverviewRow` relabels "Total fingerprints" → "Open fingerprints" and shows resolved + regressed sub-counts. The "⚠ N regressed" pill in the headline is the user's signal that a fix didn't hold.

**Result**: a fingerprint resolved by migration disappears from the dashboard / CMS list / next handoff within seconds. If the bug recurs on any client past the 48h grace, the cron flips it back to `new + regressed_after_fix=TRUE` within an hour and it shows up everywhere again, prominently flagged. Manual CMS resolves stay sticky forever.

**Rules**:
- Never UPDATE `bug_intelligence_fingerprints.status` directly in app code. Use `mark_fingerprints_resolved_by_migration` (#95 / #114) for migration-driven resolves OR the close-out migration pattern (#109 / #110 / #111 / #113 / #116 / #120 / #124) for hand-curated audits. Both stamp the audit trail; direct UPDATEs bypass the new auto-revive eligibility filter (it keys off `auto_resolved_reason IS NOT NULL`).
- When you add a `-- Resolves: <fp>` directive to a migration, the GitHub Action will auto-call the RPC on push. Don't also call the RPC by hand in the migration body unless you need it to flip immediately during the migration's own transaction (e.g. when the migration itself ships the fix and you want pre-deploy stale rows already gone).
- The 48h grace window is the single tunable. If you raise it, change `STALE_FIX_GRACE_MS` in `admin-cms/src/app/api/admin/route.ts` AND the default in `bug_intel_revive_regressed_fingerprints(p_grace_hours)` AND the `regressed_after_fix` rollup window guard in `compute_daily_bug_rollup` so all three pipelines agree. Diverging values cause "fingerprint disappears in handoff but stays open in CMS" (or worse, vice-versa).
