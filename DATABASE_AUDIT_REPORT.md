# Fit33 Database & Codebase Audit Report

> **Date**: 2026-03-20
> **Scope**: Full Supabase database (140 tables, 20 views, 200+ functions) cross-referenced against entire codebase (285 Swift files, 91 Supabase files, Admin CMS)
> **Project**: GoFit (`ehooeghabzefgoqzugrc`)

---

## Executive Summary

The Fit33 database has grown to **140 tables** with **200+ RPC functions** and **20 views**. This audit found:

- **13 completely dead tables** (zero code references anywhere)
- **~38 tables with 0 rows** but active code references (features built but never used by users)
- **35 tables with no foreign key relationships** (orphaned from referential integrity)
- **4 areas of significant data duplication** that can be improved
- **6 fields duplicated** between `user_profiles` and `user_progress` with no sync mechanism
- **Several data integrity gaps** where code writes to tables without proper FK constraints

---

## Section 1: Dead Tables (Safe to Remove)

These 13 tables have **zero references** in Swift, TypeScript, or SQL code and **zero rows** of data:

| # | Table | Columns | Recommendation | Confidence |
|---|-------|---------|----------------|------------|
| 1 | `community_benchmarks` | 16 | DROP | 99% |
| 2 | `exercise_cooldown_log` | 8 | DROP | 99% |
| 3 | `muscle_synergy_matrix` | 7 | DROP | 99% |
| 4 | `program_ratings` | 7 | DROP | 99% |
| 5 | `program_workout_history` | 8 | DROP | 99% |
| 6 | `rest_time_analytics` | 15 | DROP | 99% |
| 7 | `set_scheme_analytics` | 13 | DROP | 99% |
| 8 | `user_food_preferences` | 10 | DROP | 99% |
| 9 | `user_goal_metrics` | 30 | DROP | 99% |
| 10 | `user_recipe_carousel_state` | 7 | DROP | 99% |
| 11 | `user_recipe_interactions` | 11 | DROP | 99% |
| 12 | `user_recommended_recipes` | 14 | DROP | 99% |
| 13 | `user_taste_profile` | 19 | DROP | 99% |

**Action**: Create a migration to DROP these 13 tables. Total of ~165 unused columns removed.

---

## Section 2: Empty Tables WITH Code References (Monitor)

These tables have code that writes to them, but no users have triggered the feature yet. **Do NOT remove** - these are live features waiting for usage:

| Table | Rows | Referenced In | Status |
|-------|------|---------------|--------|
| `body_composition_goals` | 0 | BodyCompositionTrackingService.swift | Feature built, unused |
| `body_composition_logs` | 0 | BodyCompositionTrackingService.swift, InBodyService.swift | Feature built, unused |
| `cardio_goals` | 0 | SupabaseManager.swift | Feature built, unused |
| `collaborative_program_completions` | 0 | CollaborativeLearningEngine.swift | Feature built, unused |
| `collaborative_workout_data` | 0 | CollaborativeLearningEngine.swift | Feature built, unused |
| `completed_programs` | 0 | SmartProgramEngine.swift | Feature built, unused |
| `custom_exercises` | 0 | SupabaseManager.swift | Feature built, unused |
| `equipment_substitutions` | 0 | SupabaseManager.swift | Feature built, unused |
| `exercise_effectiveness` | 0 | CommunityIntelligenceService.swift | Feature built, unused |
| `exercise_pairings` | 0 | CollaborativeLearningEngine.swift, ExerciseIntelligenceService.swift | Feature built, unused |
| `exercise_progressions` | 0 | ProgressiveWorkoutIntelligence.swift | Feature built, unused |
| `heart_rate_daily` | 0 | HealthDataService.swift | Feature built, unused |
| `inbody_connections` | 0 | InBodyService.swift | Feature built, unused |
| `onboarding_analytics` | 0 | Admin CMS only | Admin feature |
| `program_completion_analytics` | 0 | CommunityIntelligenceService.swift | Feature built, unused |
| `program_history` | 0 | CloudProgramService.swift | Feature built, unused |
| `progress_photos` | 0 | ProgressPhotoService.swift | Feature built, unused |
| `recovery_patterns` | 0 | SQL migrations only | Schema-only, no app code |
| `sleep_logs` | 0 | HealthDataService.swift | Feature built, unused |
| `user_blocks` | 0 | Admin CMS, SQL | Feature built, unused |
| `user_cuisine_preferences` | 0 | RecipePreferencesView.swift | Feature built, unused |
| `user_custom_programs` | 0 | ProgramCustomizationService.swift | Feature built, unused |
| `user_dietary_restrictions` | 0 | RecipePreferencesView.swift | Feature built, unused |
| `user_exercise_nicknames` | 0 | SupabaseManager.swift | Feature built, unused |
| `user_exercise_preferences` | 0 | SQL only | Schema-only |
| `user_favorite_foods` | 0 | FoodDatabaseService.swift | Feature built, unused |
| `user_goal_progress` | 0 | AdvancedIntelligenceService.swift | Feature built, unused |
| `user_ingredient_preferences` | 0 | RecipePreferenceService.swift | Feature built, unused |
| `user_similarity_profiles` | 0 | CollaborativeLearningEngine.swift | Feature built, unused |
| `weight_goals` | 0 | WeightTrackingService.swift | Feature built, unused |
| `weight_logs` | 0 | WeightTrackingService.swift, Admin CMS | Feature built, unused |
| `workout_sets` | 0 | Admin CMS only | Admin feature |

---

## Section 3: Data Duplication Issues

### 3.1 user_profiles vs user_progress (CRITICAL)

**Problem**: 6 fields duplicated with **NO sync mechanism** - data drifts over time.

| Duplicated Field | user_profiles | user_progress | Who Writes? |
|-----------------|---------------|---------------|-------------|
| `current_streak` | integer | integer | Both independently |
| `last_workout_date` | timestamptz | timestamptz | Both independently |
| `longest_streak` | integer | integer | Both independently |
| `total_workouts` | integer | integer | Both independently |
| `weight_lbs` | numeric | numeric | Both independently |
| `xp` | integer | integer | Both independently |

**Risk**: User sees different streak counts on profile vs progress screens.

**Recommendation**: Add a database trigger that syncs these 6 fields whenever either table is updated. `user_profiles` should be the source of truth for social display, `user_progress` for detailed analytics.

**Confidence**: 95% - This is causing silent data inconsistency.
**Priority**: HIGH

### 3.2 meal_logs vs user_food_history (MERGE CANDIDATE)

**Problem**: 8 identical columns duplicated across tables.

```
Shared: calories, carbs, fat, fdc_id, food_name, meal_type, protein, quantity
```

**Data Flow**:
1. User logs meal -> writes to `meal_logs` (MealService.swift)
2. MealService calls `logFoodToHistory()` -> writes to `user_food_history`
3. FoodDatabaseService queries `user_food_history` for "foods you eat often"

**Recommendation**:
- Create a VIEW `user_food_history_v` that aggregates from `meal_logs`
- Update FoodDatabaseService to query the view
- Deprecate `user_food_history` table

**Confidence**: 90%
**Priority**: MEDIUM

### 3.3 Challenge System Overlap (KEEP AS-IS)

Four separate challenge systems exist with overlapping schemas:

| System | Tables | Purpose | Active Users |
|--------|--------|---------|-------------|
| 1v1 Friend | `group_challenges`, `challenge_participants`, `challenge_daily_progress` | Peer-to-peer | 325+ challenges |
| Community | `community_challenges`, `community_challenge_participants`, `community_challenge_daily_progress` | Open/public | 8 challenges, 16 participants |
| Private | `private_challenges`, `private_challenge_members`, `private_challenge_invites`, `private_challenge_chat` | Invite-only groups | 1 challenge |
| Weekly Leagues | `league_tiers`, `league_groups`, `league_members`, `league_history` | Duolingo-style | 5 groups, 10 members |

**Verdict**: Despite schema overlap (13 shared columns between community & private), these serve fundamentally different use cases with different:
- Access control (public vs invite-only vs peer-to-peer vs algorithmic)
- Features (chat only in private, tiers only in leagues, unlimited only in community)
- RLS policies (different rules per system)
- Lifecycles (weekly reset vs date-bound vs friend-managed)

**Recommendation**: KEEP separate. Merging would introduce massive complexity.
**Confidence**: 95%

### 3.4 user_recipe_preferences_summary vs user_taste_profile (DEAD)

Both tables have 0 rows and 6 overlapping columns. `user_taste_profile` has no code references.

**Recommendation**: Drop `user_taste_profile` (included in Section 1 dead tables).
**Confidence**: 99%

---

## Section 4: Missing Foreign Key Constraints

35 tables have **no foreign key relationships at all**. Key concerns:

| Table | Rows | Should FK To | Risk |
|-------|------|-------------|------|
| `activity_recovery_correlation` | 382 | `user_profiles.id` | Orphaned rows if user deleted |
| `exercise_user_effectiveness` | 776 | `user_profiles.id`, `exercises.id` | Orphaned rows |
| `set_completion_patterns` | 776 | `user_profiles.id` | Orphaned rows |
| `user_performance_trends` | 887 | `user_profiles.id` | Orphaned rows |
| `weekly_volume_trends` | 308 | `user_profiles.id` | Orphaned rows |
| `nutrition_performance_link` | 331 | `user_profiles.id` | Orphaned rows |
| `user_strength_ratios` | 37 | `user_profiles.id` | Orphaned rows |
| `user_learning_profiles` | 39 | `user_profiles.id` | Orphaned rows |
| `workout_time_performance` | 42 | `user_profiles.id` | Orphaned rows |
| `exercise_swap_analytics` | 105 | `user_profiles.id` | Orphaned rows |
| `equipment_proficiency` | 128 | `user_profiles.id` | Orphaned rows |
| `exercises` | 6428 | (reference table) | OK - no FK needed |
| `exercise_videos` | 447 | `exercises.id` | Should have FK |
| `food_search_cache` | 219 | (cache table) | OK - no FK needed |
| `challenge_templates` | 68 | (template table) | OK - no FK needed |
| `limitation_exercise_mappings` | 27 | `user_limitations.id` | Should have FK |

**Recommendation**: Add FK constraints with `ON DELETE CASCADE` for user-owned tables.
**Confidence**: 90%
**Priority**: HIGH - Without these, `delete_user_account()` leaves orphaned data.

---

## Section 5: Data Insights & Monetization Opportunities

### 5.1 Currently Captured Data (Being Used)

| Data Category | Tables | Insight Value |
|---------------|--------|--------------|
| Workout patterns | `exercise_performance_history`, `workout_history`, `exercise_set_history` | User progression tracking |
| Social engagement | `friendships`, `challenge_*`, `friend_activity_feed` | Viral growth metrics |
| Nutrition habits | `meal_logs`, `food_items`, `hydration_logs` | Diet adherence |
| Health metrics | `step_tracking`, `daily_activity_summary`, `cardio_workouts` | Holistic wellness |
| User behavior | `user_behavior_patterns`, `user_learning_profiles`, `onboarding_logs` | Product optimization |
| Exercise intelligence | `exercise_user_effectiveness`, `set_completion_patterns`, `user_performance_trends` | Smart recommendations |

### 5.2 Data NOT Being Captured (Opportunities)

| Missing Data | Why It Matters | Suggested Table | Priority |
|-------------|---------------|-----------------|----------|
| **Workout completion rate** | Track drop-off mid-workout | Add `completion_rate` to `workout_history` | HIGH |
| **Feature usage analytics** | Know which screens users visit most | `user_feature_usage` table | HIGH |
| **Exercise skip/swap reasons** | Understand why users reject exercises | Add `skip_reason` to `exercise_swap_analytics` | MEDIUM |
| **Goal achievement timeline** | Track how long goals take to reach | Compute from `user_progress` over time | MEDIUM |
| **Referral tracking** | Source attribution for growth | Add `referral_source` to `user_profiles` | HIGH |
| **Session duration** | Time spent in app per session | `user_sessions` table | MEDIUM |
| **Subscription events** | Conversion funnel from free to paid | `subscription_events` table | HIGH |
| **Push notification engagement** | Which notifications drive re-engagement | Add `opened_at` to `push_notification_queue` | MEDIUM |
| **AI chat effectiveness** | Track if AI advice was followed | Add `followed_up` to `ai_chat_history` | LOW |
| **Social challenge virality** | Track invitation -> join conversion | Already partially in `community_challenge_participants.referred_by` | LOW |

### 5.3 New Relationship Opportunities

| Relationship | Between | Value |
|-------------|---------|-------|
| Nutrition -> Workout Performance | `meal_logs` + `exercise_performance_history` | Show users how eating affects lifting |
| Sleep -> Recovery | `sleep_logs` + `activity_recovery_correlation` | Personalized recovery recommendations |
| Hydration -> Energy | `hydration_logs` + `workout_time_performance` | Correlate hydration with workout quality |
| Social -> Retention | `friendships` + `user_streak_tracking` | Users with friends retain better |
| Challenge -> Growth | `challenge_*` + `user_progress` | Challenge participants progress faster |

---

## Section 6: Action Plan

### Phase 1: Cleanup (Safe, Immediate) - Estimated: 1 session

| # | Action | Owner Agent | Risk | Files Affected |
|---|--------|-------------|------|----------------|
| 1.1 | DROP 13 dead tables | Supabase Agent | None | New migration SQL |
| 1.2 | Add FK constraints to 12 orphaned user-data tables | Supabase Agent | Low | New migration SQL |
| 1.3 | Add `ON DELETE CASCADE` to new FKs | Supabase Agent | Low | Same migration |

### Phase 2: Data Integrity (Medium Priority) - Estimated: 1-2 sessions

| # | Action | Owner Agent | Risk | Files Affected |
|---|--------|-------------|------|----------------|
| 2.1 | Create trigger to sync `user_profiles` <-> `user_progress` (6 fields) | Supabase Agent | Medium | New migration, verify SupabaseManager.swift |
| 2.2 | Create `user_food_history_v` view from `meal_logs` | Supabase Agent | Low | Migration + FoodDatabaseService.swift |
| 2.3 | Verify `delete_user_account()` cascades to ALL user tables | Supabase Agent + Data Backend | Medium | Review function |

### Phase 3: Intelligence & Growth (Strategic) - Estimated: 2-3 sessions

| # | Action | Owner Agent | Risk | Files Affected |
|---|--------|-------------|------|----------------|
| 3.1 | Add `completion_rate` column to `workout_history` | Supabase Agent + Product Engineer | Low | Migration + WorkoutManager.swift |
| 3.2 | Create `user_feature_usage` table | Supabase Agent + Product Engineer | Low | Migration + new analytics service |
| 3.3 | Add `referral_source` to `user_profiles` | Supabase Agent | Low | Migration + onboarding |
| 3.4 | Add `opened_at` to `push_notification_queue` | Supabase Agent | Low | Migration + notification handler |
| 3.5 | Build nutrition -> performance correlation views | Supabase Agent | Low | New views |

### Phase 4: Monitoring & Prevention (Ongoing)

| # | Action | Owner Agent | Risk |
|---|--------|-------------|------|
| 4.1 | Supabase Agent reviews every new table/column PR | Supabase Agent | None |
| 4.2 | Monthly orphan data check (rows without valid FK) | Supabase Agent | None |
| 4.3 | Quarterly dead table audit | Supabase Agent | None |

---

## Database Statistics

| Metric | Count |
|--------|-------|
| Total tables | 140 |
| Total views | 20 |
| Total RPC functions | ~200 |
| Tables with data | ~102 |
| Tables with 0 rows | ~38 |
| Dead tables (no code refs) | 13 |
| Tables missing FK constraints | 35 |
| Largest table (rows) | `food_items` (7,409 rows, 22 MB) |
| Second largest | `exercises` (6,428 rows, 18 MB) |
| Total users | ~25 |
| Total workouts logged | ~92 |
| Total challenges created | ~330 |
