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
6. Index audit (no full table scans on large tables)

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
