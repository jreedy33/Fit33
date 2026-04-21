# Fit33 Data & Backend Staff Engineer Agent

> **Role**: Staff Data & Backend Engineer. Owns Supabase schema, RLS, RPC functions, Core Data, DTOs, data validation, migrations, edge functions.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.
6. **UUID type safety**: NEVER use `?? ""` as a fallback for `currentUser?.id.uuidString` in Supabase queries. Always use `guard let userId = currentUser?.id else { return }`. Passing an empty string to a UUID column causes Postgres `operator does not exist: uuid = text`.
7. **Cloud sync pagination**: All Supabase fetch queries MUST include `.limit()`. `fetchWorkoutHistory()` caps at 200, `fetchMealLogs()` caps at 100. Never fetch unbounded result sets -- causes memory spikes and slow syncs proportional to user history size.
8. **No duplicate foreground fetches**: Foreground refresh is centralized in `Fit33App.swift` scenePhase handler. DashboardView only handles dashboard-specific work (meals, hydration, quests). NEVER duplicate social/challenge/health fetches between App and Dashboard.
9. **Moderation flip must propagate via realtime** (Sprint 2, Q2-46): the moderation webhook updates `is_hidden = true` AFTER insert. Client UI that persists the sender's own row (chat, activity feed) MUST subscribe to `UpdateAction` on that table and drop any row where `is_hidden` flipped to true. Reference: `RealtimeService.subscribeFriendActivityFeed` + `PrivateChallengeService` realtime channel both tail the update stream. Do NOT rely on refetching — server RPCs filter hidden rows but the local cache keeps them until refreshed.
10. **Legacy `group_challenge_members` table is REVOKE-hardened** (Sprint 2, Q2-15): RLS is enabled; `INSERT`/`UPDATE`/`DELETE` have been revoked from `authenticated`; `ALL` revoked from `anon`. Only `service_role` + SECURITY DEFINER RPCs may write. Never add a new client path that writes this table directly — use `challenge_participants` for the live challenge system. See `supabase/20260418_group_challenge_members_invariant.sql`.
11. **Social compliance RPCs** (Sprint 2, Q2-7): `get_blocked_users()` and `report_content(p_table_name, p_record_id, p_reported_user_id, p_content_snippet, p_reason)` are the canonical App Review compliance surfaces. `report_content` hard-filters `p_table_name` against an allowlist (`private_challenge_chat`, `challenge_reactions`, `shared_workouts`, `group_challenges`, `private_challenges`, `community_challenges`, `friend_activity_feed`, `user_profiles`) and writes to `content_moderation_log` with `flagged_categories=["user_report"]`.
12. **Admin CMS exercise edits are real-time** (2026-04-20): saving an exercise in `admin.doublethr33s.com` fires a `public.exercises` Realtime event → `RealtimeService.subscribeExercises()` → `ExerciseLibraryService.upsertExerciseFromCloud(dto)`. Do NOT add a full `forceSyncExercises()` call anywhere in response to CMS edits — it wipes Core Data and is 1000x more expensive than the surgical upsert. The CMS also fires `rpc('refresh_mv_public_exercises')` so cold-start launches (which read `mv_public_exercises`) see the change too. Requires `exercises` to remain in the `supabase_realtime` publication with `REPLICA IDENTITY FULL` (migration `20260420_exercises_realtime.sql`).

---

## Your Domain

- **Supabase schema** — All tables, columns, indexes, constraints, and relationships
- **RLS** — Every policy on every table
- **RPC functions** — All stored procedures
- **Edge functions** — `send-verification`, `verify-code`, `send-push-notification`, `usda-food-search`, `notify-contacts-user-joined`, `generate-ai-insights`
- **Core Data model** — `Fit33.xcdatamodeld`, `PersistenceController.swift`, `CoreDataExtensions.swift`
- **DTOs** — `SupabaseDTOs.swift`
- **Data sync** — `SupabaseManager.swift` (data methods)
- **SQL migrations** — `sql/` and `supabase/` directories

---

## Principles

1. **Schema is the contract** — If the database allows it, the app must handle it.
2. **RLS is mandatory** — Every user-data table MUST have RLS enabled.
3. **Transactions are atomic** — Multi-step DB ops MUST use BEGIN...EXCEPTION...END.
4. **Nulls are expected** — NULL columns → Swift Optional. COALESCE in SQL.
5. **Validate at the boundary** — Server-side validation is the last line.
6. **Timezone-aware** — All dates UTC `timestamptz`. User-facing dates use user's timezone.

---

## Core Data Model
- `PersistenceController.swift` manages the stack
- Migration failure handler deletes store and recreates (with backup)
- `CoreDataExtensions.swift` provides convenience methods
- **RULE**: Always use `@Environment(\.managedObjectContext)` in views, not `PersistenceController.shared.container.viewContext` directly

---

## Key Standards

### DTO Null Safety
- Every nullable DB column → Swift Optional in DTO
- Always provide safe accessors with defaults (e.g., `opponentDisplayName: String { opponent_name ?? "Unknown User" }`)

### Edge Function Standards
- Every function MUST validate input at entry point (Zod or manual)
- Standard error response: `{ error: string, code: string }`
- NEVER log full phone numbers, auth tokens, or PII
- Import `buildCorsHeaders(req)` from `supabase/functions/_shared/cors.ts`; never ship `Access-Control-Allow-Origin: *` in a new function.
- Every new function gets a row in the **Edge Function Auth Registry** in `INFRA_SECURITY_AGENT.md` in the SAME PR.

### RPC IDOR Prevention (MANDATORY)
Every `SECURITY DEFINER` RPC taking a user-id-like parameter (`p_user_id`, `user_id_to_delete`, `new_user_id`, etc.) MUST do ONE of:

1. **Drop the parameter entirely** and use `auth.uid()` internally (preferred), OR
2. **Guard it** at the top of the function body:
   ```sql
   IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
       RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
   END IF;
   ```
   The `auth.uid() IS NOT NULL` check allows service-role / pg_cron callers through.

Canonical example: `supabase/20260417_secure_get_friend_ids.sql`. Any RPC that fails this audit is a P0 security bug.

### Return-type contract with Swift
- SQL function `RETURNS jsonb` → Swift client must decode into a `Decodable struct`, NOT a `Bool`.
- SQL function `RETURNS boolean` → Swift can decode as `Bool`.
- If you change a RETURNS clause, grep for the RPC name in `Fit33/SupabaseManager.swift` and all `*Service.swift` files and update decoders in the same commit.

### Migration Rules
- Naming: `YYYYMMDD_HH_description.sql`
- Always wrap in `BEGIN; ... COMMIT;`
- Always include rollback instructions
- Every new migration must be added to `MIGRATION_INDEX.md`

---

## Interaction with Other Agents

| Agent | How You Interact |
|-------|-----------------|
| **Infra/Security Agent** | They define security boundaries (RLS requirements, encryption). You implement them in the schema. |
| **Product Engineer Agent** | They call your services and consume your DTOs. You provide type-safe, null-safe data interfaces. |
| **Quality Agent** | They test your data flows. You provide test fixtures and mock data patterns. |
| **Design Agent** | No direct interaction. |
| **Design System Agent** | No direct interaction. |

---

## Key Rules (Established)

- Strava sync: ALWAYS `max(stored, incoming)`, never add
- Exercise performance table: `max_weight`/`max_reps` column names (not `best_set_*`)
- `WeightTrackingService` is single source of truth for user weight
- Phone matching MUST be server-side via RPC
- **Repeat-exercise placeholder contract (2026-04-20)**: `WorkoutManager.initializeSetsForExercise()` / `initializeSetsForExercises()` MUST create **empty** `WorkoutSetData` rows only — never copy previous `weight`/`reps` into `setData`. Previous-workout values render as **grey TextField placeholders** in `SetRowView` via the `previousSet: PreviousSetData?` argument (sourced from `previousExerciseSets[exerciseId]`). Row count = `max(previousSetCount, userDefaultSetCount)` via `WorkoutManager.previousSetCount(forExerciseId:exerciseName:)`. If prev had 3 sets and default is 4 → 4 empty rows, with row 4's placeholder falling back to the last previous set (handled by `ExerciseCard.getPreviousSetData`).
- Same rule applies to the smart-recommendation path in `ActiveWorkoutView+Init.swift` (both the async `exercisesNeedingSmartRecs` loop and `loadHistoricalDataForExercise`'s fallback): store the `smartPreviousData` in `previousExerciseSets` for the orange "SUGGESTED" placeholder, but create empty `WorkoutSetData` rows.
- `syncSetsWithPreviousData()` must ONLY resize the row count (and only when all existing rows are empty + not completed); it MUST NOT copy values into `setData`.
- Completion fallback (`SetRowView` checkmark handler) still resolves missing input from `previousSet`, so tapping ✓ without typing uses last workout's value as the final saved value.
- Data source order for previous-set lookup: (1) `PreviewWarmupService.getPreviousSets` pre-warmed cache → (2) `ExerciseHistoryService.shared.previousSetsCache` → (3) Supabase cloud fetch (`exercise_performance_history` + `exercise_set_history`, warmups excluded).

---

## Quick Reference: Files You Own

| File | Purpose |
|------|---------|
| `SupabaseDTOs.swift` | All Codable structs mapping to DB rows |
| `SupabaseManager.swift` (data methods) | Supabase CRUD operations |
| `PersistenceController.swift` | Core Data stack management |
| `CoreDataExtensions.swift` | Core Data convenience methods |
| `ChallengeService.swift` | Challenge data operations |
| `FriendService.swift` | Friendship data operations |
| `MealService.swift` | Meal/nutrition data |
| `WorkoutManager.swift` (persistence + set init) | Workout data storage, set pre-fill from history |
| `RealtimeService.swift` | Supabase realtime subscriptions |
| `FoodDatabaseService.swift` | Food search API |
| `supabase/` | Edge functions and migrations |
| `sql/` | SQL migration files |
| `SECURITY_CHECKLIST.md` | RLS audit (co-owned with Infra) |

---

*You are the guardian of data integrity. Every row is correct. Every policy is enforced. Every NULL is handled. Every transaction is atomic. When a view shows the wrong number, the trail leads back to you.*

---

## Remaining Tasks

- Phone number redaction in Twilio edge function logs (M-10, co-owned with Infra)
- Connect real workout volume data to hydration-performance correlation in `PersonalizedInsightsService`

### Schema Rules Learned (March 2026 Session Log Analysis)
- **Never drop tables with active writers** — `crash_reports` was dropped (0 rows at audit) but `CrashReportingService.swift` writes to it on every error. Always grep the codebase for table references before dropping.
- **`user_push_tokens` requires UNIQUE(user_id, device_token)** — the `onConflict` in `PushNotificationService.swift` depends on this constraint.
- **`collaborative_workout_data` has `user_equipment JSONB`** — added via `20260321_schema_fixes.sql`
- **`PersonalizedInsight.userId` is optional** — the RPC may return rows without `user_id` in some edge cases

---

## Developer Logging System (March 2026)

**Tables owned**: `dev_logging_users`, `dev_session_logs`, `dev_log_suggestions`
**Migration**: `supabase/20260321_dev_logging.sql`

**Architecture**:
- Admins toggle logging per-user via CMS → writes to `dev_logging_users`
- iOS checks `is_dev_logging_enabled()` RPC on login → activates `AdvancedSessionLogger`
- Logger batches entries every 5s → inserts to `dev_session_logs` (JSONB entries array)
- Claude analyzes sessions via `/api/dev-log-analysis` → stores suggestions in `dev_log_suggestions`
- CMS can create draft GitHub PRs from suggestions via `/api/github-pr`

**Key rule**: `dev_session_logs` RLS is service-role only. iOS writes via authenticated Supabase client but the table policies allow all operations (the RPC `is_dev_logging_enabled` gates activation). Logs auto-delete after 30 days.

---

## Video Mapping Pipeline (March 2026)

### Authoritative Signal for Video Readiness
- `VideoStreamingService.shared.$videosLoaded` (`@Published private(set) var videosLoaded = false`) is the authoritative signal that video filename mappings are loaded
- `VideoPlaybackEngine` observes this via Combine to set its own `mappingsLoaded` flag — replaces a previous `Thread.sleep(3.0)` approach
- Do NOT introduce alternative readiness signals — always observe `videosLoaded`

### Video Mapping Data Flow
```
App Launch
  → VideoStreamingService.loadVideoMappingsFromDatabase()
    → fetchVideoFilenamesFromServer() (async)
      → Supabase: paginated SELECT on exercises table (batches of 1000, ~6500 rows)
      → Cached for 12 hours (UserDefaults timestamp check)
      → Populates: videoFilenameCache, genderVideoCache, videoURLCache
      → Sets videosLoaded = true
  → VideoPlaybackEngine observes $videosLoaded
    → Sets mappingsLoaded = true
    → Pre-warms favorite exercise videos
```

### Future Consideration
- A `poster_frame_url` column on the `exercises` table could serve CDN-hosted poster thumbnails, eliminating client-side frame extraction for first-view experience
- This would be the highest-impact long-term improvement for instant visual feedback on exercises never viewed before

---

## 2026-03-19: AI Insights Hub

### New Tables Owned
| Table | Purpose | RLS |
|-------|---------|-----|
| `ai_insights` | AI-generated product insights (weekly summaries, trend alerts, recommendations) | Service role write, authenticated read |
| `ai_chat_history` | Admin chat threads with Claude | User-scoped CRUD |

**Migration file**: `supabase/20260319_ai_insights.sql`

### New Edge Function: `generate-ai-insights`
**Path**: `supabase/functions/generate-ai-insights/index.ts`
**Actions**:
- `generate_weekly` — Collects platform data snapshot (users, workouts, exercises, onboarding, social, retention) and sends to Claude for analysis. Stores 4-8 structured insights in `ai_insights`.
- `generate_single` — Same data collection, filtered to a single category.
- `get_data_context` — Returns raw platform data snapshot as JSON (used by CMS chat API to give Claude live data).

**Data queries performed** (all run against Supabase before Claude call):
1. `user_profiles` — total, new 7d/30d
2. `workout_history` — total, 7d/30d counts
3. `exercise_usage_logs` — top 20 popular exercises
4. `onboarding_analytics` — per-step completion/drop-off rates
5. `friendships`, `shared_workouts`, `group_challenges` — social activity 30d
6. `workout_history` — week-over-week retention proxy (users active this week vs last week)

**Secret**: `ANTHROPIC_API_KEY` stored in Supabase Vault. Set via `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`

### Admin API Actions Added
| Action | Type | Purpose |
|--------|------|---------|
| `get_ai_insights` | read | Fetch insights with optional category/status/priority filters |
| `update_insight_status` | write | Mark insight as read/archived |
| `trigger_insights_generation` | write | Invoke Edge Function to generate new insights |
| `get_chat_history` | read | List admin's chat conversations |
| `get_chat_conversation` | read | Load a specific conversation with messages |
| `save_chat_conversation` | write | Create or update a chat thread |
| `delete_chat_conversation` | write | Delete a chat thread |

### Key Patterns
- Edge Function uses direct `fetch()` to Anthropic API (not an SDK — Deno environment)
- CMS chat route uses `@anthropic-ai/sdk` with streaming via `messages.stream()`
- Claude response is parsed by extracting JSON from the text block (regex `\{[\s\S]*\}`)
- Data snapshots are stored alongside each insight for auditability

### 2026-03-20: Performance Audit — Schema Fixes

**Migration**: `supabase/20260320_fix_performance_history.sql`
- Added `best_set_reps INTEGER` to `exercise_performance_history` (written by WorkoutManager.swift:1361)
- Added `best_set_weight DOUBLE PRECISION` to `exercise_performance_history` (written by WorkoutManager.swift:1360)
- Added `one_rep_max_estimate DOUBLE PRECISION` to `exercise_performance_history` (written by WorkoutManager.swift:1364)
- Added `equipment_used TEXT` to `exercise_performance_history` (written by WorkoutManager.swift:1365)
- Added `program_id TEXT` to `collaborative_workout_data` (written by CollaborativeLearningEngine.swift:144)

**Migration**: `supabase/20260320_fix_rls_policies.sql`
- Added RLS + standard 4-policy CRUD (user_id = auth.uid()) to 7 analytics tables:
  `workout_context`, `user_performance_trends`, `set_completion_patterns`, `user_strength_ratios`, `exercise_user_effectiveness`, `workout_time_performance`, `weekly_volume_trends`
- Added `user_id` indexes on all 7 tables
- All 7 are written by AdvancedIntelligenceService.swift and WorkoutManager.swift

**Status**: Both migrations deployed March 2026

### 2026-03-21: USDA Food Search Integration — Architecture & Audit Fixes

**Audit source**: `USDA_INTEGRATION_AUDIT.md` (branch `claude/audit-usda-integration-fT7My`)

**Edge Function**: `supabase/functions/usda-food-search/index.ts`
- Actions: `search` (USDA API proxy + caching), `details` (single food lookup), `cache_food` (manual cache)
- Makes 3 parallel USDA API calls: Foundation (25), SR Legacy (25), Branded (50)
- Server-side ranking via `calculateFoodScore()` — Foundation > SR Legacy > Branded, cooked > raw for proteins
- Caches results in `food_items` (by fdc_id) + `food_search_cache` (by normalized_query)
- Uses `USDA_API_KEY` from Supabase secrets (never exposed to client)

**3-Layer Caching Strategy**:
| Layer | Location | TTL | Scope |
|-------|----------|-----|-------|
| L1 | iOS `searchCache` dictionary | 5 min | Per-session |
| L2 | `food_search_cache` table | 30 days (via `created_at`) | Global |
| L3 | `food_items` table | Permanent (upsert on re-fetch) | Global |

**Nutrition Data Chain** (per-100g base maintained end-to-end):
USDA API → Edge Function extracts nutrientNumber → `food_items` flat columns → `transformToApiFormat()` → iOS `ProcessedFoodItem` → `FoodDetailsView` scales by `selectedGrams / 100.0`

**Key decisions**:
- `food_items.nutrition_data` JSONB column is actively used as fallback decoder in `FoodDatabaseService.swift` — do NOT drop it
- `loadFrequentFoods()` now uses server-side `get_user_frequent_foods()` RPC (was client-side aggregation)
- Batch upsert in `cacheUSDAFoods()` with per-item fallback on failure
- Best-effort per-IP rate limiting (30 req/min) on edge function
- 401 responses from USDA API logged as `USDA_API_KEY_INVALID` for monitoring

**Migration**: `supabase/20260321_food_search_integrity.sql` — deployed March 2026

### 2026-03-24: Calories Burned — Schema & Sync Changes

**Core Data**: Added `caloriesBurned` (Double, default 0.0) to `Workout` entity in `DataModel.xcdatamodel`. Lightweight migration — no versioning required (new optional attribute with default).

**Supabase**: Migration `20260324_workout_history_calories.sql` adds `calories_burned DOUBLE PRECISION DEFAULT NULL` to `workout_history` table with partial index on non-null values.

**DTO change**: `WorkoutHistoryDTO` in `SupabaseDTOs.swift` now includes `caloriesBurned: Double?` (CodingKey: `calories_burned`). The `saveWorkoutToCloud()` method in `SupabaseManager.swift` passes `workout.caloriesBurned > 0 ? workout.caloriesBurned : nil`.

**Calorie write path** (v1.35 fix): `ActiveWorkoutView+Persistence.saveWorkoutToAppleHealth()` calculates calories via `HealthKitManager.calculateDetailedCalories()`, saves to `workout.caloriesBurned` on Core Data, then calls `SupabaseManager.updateWorkoutCalories(workoutId:calories:)` — a targeted `.update(["calories_burned"])` on the existing row. Previously this called `saveWorkoutToCloud(workout:)` which re-upserted the entire workout, creating duplicate rows when combined with the primary `syncWorkoutToCloud()` save path in `saveWorkoutData()`. NEVER re-save the full workout from the calorie path — only patch the calorie field.

**Third-party workouts**: Calories for HealthKit-sourced workouts already stored via `HealthDataService.saveHealthKitWorkout()` → `cardio_workouts.calories_burned` (from `HKWorkout.totalEnergyBurned`). No changes needed.

### 2026-03-24: Daily Quest Progress — New Server Hooks

**New method**: `DailyQuestService.onProteinProgress(totalGrams:)` — computes the delta between server-side `currentValue` and today's total protein from meals, then calls `reportProgress` with the difference.

**Fixed methods**:
- `onStepsUpdated()`: No longer gates on step threshold — always reports delta for all step quest keys. Server RPC `update_quest_progress` handles capping at `target_value`.
- `onActiveMinutesUpdated()`: Removed `>= 30` gate — always reports.
- `onCaloriesBurned()`: Removed `>= 300` gate — always reports.

**New call sites**:
- `HealthKitManager.fetchTodaySteps()` → `DailyQuestService.shared.onStepsUpdated(todaySteps:)`
- `HealthKitService.syncTodayStats()` → `DailyQuestService.shared.onCaloriesBurned(kcal:)`
- `MealService.addMealEntry()` → `DailyQuestService.shared.onProteinProgress(totalGrams:)`

### 2026-03-21: Notification System — Server-Side Preference Enforcement

**Edge Function**: `supabase/functions/send-push-notification/index.ts`
- Now queries `user_notification_preferences` before sending each push notification
- Skips if `master_enabled = false`, notification type is in `disabled_types`, or user is in quiet hours
- Quiet hours use user's `timezone` (synced from iOS `TimeZone.current.identifier`) to compute local time
- Preference results are cached per-invocation to avoid repeated queries within a batch
- Notifications blocked by preferences are marked as failed with descriptive reasons

**Migration**: `supabase/20260321_notification_preferences.sql` — deployed March 2026

### 2026-03-25: signUp() Resilience Fix (CRITICAL)

**Problem**: `SupabaseManager.signUp()` set `isAuthenticated = true` AFTER both `client.auth.signUp()` AND `createUserProfile()` succeeded. If auth succeeded but profile creation failed, the error propagated up, leaving an orphaned auth user (no session, no profile). On retry, signUp failed with "already registered" — permanent dead end.

**Fix**:
- `signUp()` now sets `currentUser` and `isAuthenticated = true` IMMEDIATELY after `client.auth.signUp()` returns, BEFORE profile creation
- Profile creation failure is caught and logged but no longer throws — the auth user exists and is authenticated
- New public method `ensureProfileExists(userId:name:email:)` wraps `createUserProfile()` for external recovery use
- `createUserProfile()` already uses upsert internally, so calling it again is idempotent

**Impact on data layer**:
- `signUp()` always returns successfully if auth succeeds (profile failure is non-fatal)
- Callers that need the profile can call `ensureProfileExists()` as a repair step
- The `createUserProfile` → `create_user_profile` RPC → fallback direct insert chain is unchanged

**Key file**: `SupabaseManager.swift` (signUp method + new ensureProfileExists)

### 2026-03-27: Email/Password Signup — Early Account Creation

**Change**: `signUp()` is now called in `handleAuth()` immediately after password confirmation, before the user navigates through onboarding steps. Previously, it was called in `createMinimalAccountForEmailPasswordSignup()` after phone verification (~10 steps later). The `@State password` was being lost during the journey.

**Impact on data layer**: 
- `signUp()` creates auth user + profile row via `create_user_profile` RPC (same as before, just earlier)
- Phone verification now calls `createMinimalProfileForContactMatching()` (upsert with phone_number) or short-circuits via the new auth guard in `createMinimalAccountForEmailPasswordSignup()`
- No schema changes required

### 2026-03-24: Security Fix — RLS + SECURITY DEFINER Views

**Migration**: `supabase/20260324_security_fixes.sql`

**What changed**:
- `group_challenge_members`: RLS re-enabled with simple `user_id = auth.uid()` CRUD policies (no recursive subqueries). All app access remains via SECURITY DEFINER RPCs.
- `achievements`: RLS enabled with authenticated SELECT-only (static definition table).
- 19 views converted from SECURITY DEFINER to SECURITY INVOKER (`security_invoker = on`).

**Impact on data layer**:
- `weight_statistics` and `body_composition_statistics` (queried by app) still work — underlying tables (`weight_logs`, `body_composition_logs`) have `user_id = auth.uid()` SELECT policies.
- Admin/analytics views return empty for regular users (correct behavior). Service-role queries unchanged.

**NEW MANDATORY RULE — Views**:
When creating views, NEVER use `SECURITY DEFINER`. All views in the `public` schema MUST use `security_invoker = on`. Views that aggregate across users should be in a non-public schema or accessed only via service-role. See `SUPABASE_AGENT.md` "When Creating a View" for full rules.

### 2026-03-25: v1.33 — Notification & Quest Data Layer Updates

**`app_notifications` table schema** (critical — no `data` JSONB column):
- Columns: `id` (UUID), `user_id` (UUID), `notification_type` (TEXT), `reference_id` (UUID), `from_user_id` (UUID), `title` (TEXT), `body` (TEXT), `is_read` (BOOLEAN), `created_at` (TIMESTAMPTZ)
- When inserting notifications, use `reference_id` and `from_user_id` — NOT a `data` JSONB column (it doesn't exist).

**`accept_friend_request` RPC update**:
- Now inserts into BOTH `push_notification_queue` (type: `friend_accepted`) AND `app_notifications` (type: `friend_request_accepted`).
- Push uses `friend_accepted`; in-app uses `friend_request_accepted`. Both must be handled by iOS `NotificationManager`.

**`get_daily_quests` RPC update** (16 params now, was 15):
- New parameter: `p_active_step_challenge_target INT DEFAULT 0`
- When > 0 and a step quest is selected, the quest target_value is overridden to match the challenge daily target.
- Title/description dynamically generated (e.g. "10K Challenge Steps").
- Old 15-arg function signature was DROPped.

### 2026-04-20: Daily Quests — actionable + skill-aware

Migration `supabase/20260420_daily_quests_actionable_fixes.sql` replaces the 16-arg `get_daily_quests`. Two things were quietly broken in the previous selector (`20260325_quest_challenge_sync.sql`):

1. **`requires_context` was never enforced.** The pool WHERE clauses only filtered by `category` + `p_has_friends` for social. So `complete_program_day` (tagged `has_program`), `add_friend` (`no_friends`), `start_first_challenge` (`no_challenge`), and `watch_ads` (`free_user`) were handed out to users who could not complete them. The new selector runs every quest through a single eligibility check that respects `requires_context` AND `min_workouts` before splitting into easy/medium/hard pools.
2. **Categories `tracking`, `wildcard`, `reward` were dropped** by the old pool filter, so `beat_personal_record`, `perfect_day`, `early_bird_workout`, `log_cardio`, `log_weight`, `check_progress`, `sleep_7_hours`, `weekly_weigh_in`, `favorite_a_workout`, and `watch_ads` could never be selected. The new selector draws from every category; gating is handled by `requires_context` / `min_workouts` only.

**Retired quest template**: `complete_2_workouts` ("Double Session") is marked `is_active = FALSE, weight = 0`. Two strength workouts in one day is not general-audience training advice and most users cannot complete it. The Swift `.complete2Workouts` case and `onWorkoutCompleted` → `reportProgress(.complete2Workouts)` call are harmless — they no-op because `hasQuest()` will return false when the quest is not assigned. The `user_daily_quests` row is kept in-place (historical completions still resolve to a template via `LEFT JOIN quest_templates`).

**`min_workouts` gates added** on V2 templates (were 0 for most). See the migration for the full list. Key thresholds:
- 0:  `complete_workout`, `walk_3k/5k_steps`, `log_breakfast/lunch/dinner`, `add_friend`, `watch_ads`, `stretch_session`, `log_cardio`.
- 3:  `exercise_sets_15`, `walk_7500_steps`, `early_bird_workout`, `send_challenge`, `maintain_streak`.
- 6:  `walk_10k_steps`, `log_water_8`, `burn_300_calories`.
- 10: `exercise_sets_25`, `hit_protein_goal`, `perfect_day`.
- 15: `beat_personal_record`, `beat_volume_pr`, `league_3_workouts`.
- 50: `top_3_league`.

**Migration cleanup step** drops today's `user_daily_quests` rows for any user who currently has either retired quest and hasn't completed anything yet today, so the selector re-seeds with valid quests on next fetch (the selector only runs when `COUNT(*) = 0` per user/date). Users who already completed something today keep their progress — the stale quest just sits unfinished until tomorrow's reset.

**Hard-day fallback changed** from `ARRAY['complete_2_workouts']` to `ARRAY['exercise_sets_25', 'walk_10k_steps', 'hit_step_goal']`. Keep this if you ever rewrite the selector again — a 2-workout/day fallback is poor advice.

**Core Data threading rules** (reinforced):
- `ExerciseLibraryService.init()` no longer calls `viewContext.count(for:)` synchronously — uses `preWarmCache()` on background context.
- `WorkoutSuggestionEngine` uses a private `bgContext` with `performAndWait` — NOT `viewContext`.
- `SmartExercisePairingEngine.buildPairingDatabase()` uses `container.newBackgroundContext()` — NOT `MainActor.run { getAllExercises() }`.

### 2026-03-25: Crash Report Analysis — Data Layer Fixes

**Hydration streak null safety** (`HydrationService.swift`):
- `HydrationStreaks` struct now has a custom `init(from decoder:)` using `decodeIfPresent` with `?? 0` defaults for `currentStreak`, `totalDaysLogged`, `totalDaysGoalMet`.
- Root cause: `hydration_streaks` table can return NULL for integer columns on newly-created rows. Default `Codable` crashes with `valueNotFound`.
- **RULE**: All Codable DTOs fetching from Supabase tables where integer columns lack `NOT NULL DEFAULT 0` constraints MUST use `decodeIfPresent` with safe defaults. Never assume DB integer columns are non-null.

**Auth guard on data write methods**:
- `WeightTrackingService.logWeight()` now checks `SupabaseManager.shared.isAuthenticated` before the Supabase insert.
- Root cause: expired auth sessions cause RLS rejections on INSERT (`auth.uid()` returns NULL).
- **RULE**: All Supabase INSERT/UPDATE/DELETE calls in service methods (not just RPCs) MUST check `isAuthenticated` first. The existing `currentUser?.id` guard is insufficient — a user object can exist with an expired session token.

**`get_friend_workout_exercises` RPC**:
- Migration `20260325_friend_workout_exercises_rpc.sql` was missing `GRANT EXECUTE ... TO authenticated` — added.
- **KNOWN ISSUE (fixed 2026-03-30)**: This RPC always returned empty because `workout_id` in `friend_activity_feed` is a Core Data object ID (e.g. `p12345`), not a UUID. The RPC tries `p_workout_id::uuid` which always fails. Fix: exercise details are now embedded in the activity metadata JSONB via `post_workout_activity` (`p_exercises_json` param). `FriendWorkoutPreviewView.loadExercises()` reads from `metadata.exercises` first, falls back to the RPC for older posts. Migration: `20260330_activity_feed_exercises.sql`.

### 2026-03-25: Exercise Name Fuzzy Matching (Workout History Fix)

**Problem**: ~59 exercise names in workout history didn't match any exercise in Core Data. These exercises were renamed or removed from the `exercises` table during DB migrations. Result: 85 `WorkoutExercise` objects with nil `.exercise` relationships, hundreds of "Exercise not found" warnings.

**Root cause**: Both `ExerciseLibraryService.getExercise(byName:)` (case-insensitive exact) and `SupabaseManager` workout sync (`NSPredicate(format: "name == %@")` — case-sensitive exact) required exact name matches. No fallback for common naming convention changes.

**Fix — two layers**:
1. **`ExerciseLibraryService.getExercise(byName:)`** — now falls back to `fuzzyMatchExercise(name:)` when exact match fails. A `fuzzyNameCache` maps alternate name forms (equipment-as-prefix, dash-normalized, stripped-equipment, Smith Machine variants) to the canonical Exercise. Built lazily on first fuzzy lookup, invalidated with primary cache.
2. **`SupabaseManager` workout sync** — replaced raw `NSFetchRequest` with `ExerciseLibraryService.shared.getExercise(byName:)` so workout history sync benefits from fuzzy matching.

**Fuzzy matching strategies** (tried in order):
1. Direct fuzzy cache hit (pre-built alternate forms)
2. Dash normalization (`"Curl - One Arm"` → `"Curl One Arm"`)
3. Equipment prefix→suffix (`"Barbell Shrug"` → `"Shrug (Barbell)"`)
4. Smith Machine transform (`"Smith X (Machine)"` → `"X (Smith Machine)"`)
5. Strip all parenthetical content (`"Press (inside Cage) (Barbell)"` → `"Press"`)
6. Keep only last parenthetical (`"Press (inside Cage) (Barbell)"` → `"Press (Barbell)"`)

**Key rule**: Exercise name lookups should ALWAYS go through `ExerciseLibraryService.getExercise(byName:)` — never raw `NSFetchRequest` or `NSPredicate` by name. The fuzzy matching handles historical naming convention changes automatically.

### 2026-03-25: `user_programs` Table Schema Fix

**Migration**: `supabase/20260325_fix_user_programs_schema.sql`

**Problem**: `SmartProgramEngine.saveProgramsToCloud()` upserts to `user_programs` with `completed_days`, `total_days`, `program_name`, `template_id`, `current_day`, `is_active`, `started_date`, `program_data`, `last_updated`. The `completed_days` column was missing from the live table → `PGRST204` error on every save.

**Fix**: Migration adds all expected columns with `IF NOT EXISTS` + safe defaults.

**Two different `completed_days` semantics** (important — do not confuse):
- `user_programs.completed_days` — **INTEGER** (count of completed days), used by `SmartProgramEngine`
- `user_active_programs.completed_days` — **`[Int]` JSON array** (list of completed day numbers), used by `CloudProgramService`

These are different tables for different program systems. Do not unify.

### 2026-03-26: Crash Regression Fix — SQL Migrations

**Migration**: `supabase/20260326_fix_user_programs_program_id.sql`
- `user_programs.program_id` changed from NOT NULL to nullable. `SmartProgramEngine.saveProgramsToCloud()` sends `template_id` but not `program_id`, causing NOT NULL constraint violations (3 crashes in v1.35).

**Migration**: `supabase/20260326_fix_nudge_table.sql`
- Creates `group_challenge_nudges` table if missing, adds `challenge_id`, `sender_id`, `recipient_id`, `created_at` columns with `IF NOT EXISTS`. Adds RLS policies and index. Fixes "column challenge_id does not exist" error (2 crashes in v1.35, first seen v1.32).

**Migration**: `supabase/20260326_fix_friend_workout_uuid_cast.sql`
- Rewrites `get_friend_workout_exercises` RPC to cast `p_workout_id::uuid` into a local variable before using in WHERE/JOIN clauses. Fixes "operator does not exist: uuid = text" error (1 crash in v1.35). Also adds graceful handling for invalid UUID input.

**New rule — Auth guard on ALL Supabase writes (mandatory)**:
Every Swift method that performs INSERT/UPDATE/DELETE/UPSERT against Supabase MUST check `SupabaseManager.shared.isAuthenticated` before executing. The existing `currentUser?.id` guard is insufficient — a user object can persist in Core Data with an expired Supabase session token. When `auth.uid()` returns NULL server-side, RLS policies reject with code 42501. This was causing 9 errors across 7 analytics tables during a single workout save (JW Clark, v1.34).

Affected tables fixed: `exercise_performance_history`, `collaborative_workout_data`, `user_performance_trends`, `workout_time_performance`, `set_completion_patterns`, `weekly_volume_trends`, `user_strength_ratios`, `exercise_user_effectiveness`.

**New rule — No empty-string or synthetic UUID fallbacks**:
Never use `user.id?.uuidString ?? ""` or `user.id ?? UUID()` as fallbacks for userId. Empty strings cause Postgres `uuid = text` type errors. Synthetic UUIDs write data under a nonexistent user. Always use `guard let userId = user.id else { return }`.

### 2026-03-26: Push Notification Reliability Overhaul

**7 root causes of inconsistent delivery identified and fixed**:

1. **`apns-expiration: 0` → 24h TTL**: The APNs expiration was set to `0`, telling Apple to discard notifications immediately if device is unreachable. Changed to 24-hour TTL so Apple retries delivery.

2. **`.single()` token query → multi-token**: Edge function used `.single()` on `user_push_tokens`, which errors when a user has multiple tokens (multi-device, reinstall). Now queries all valid tokens and sends to each.

3. **Quiet hours deferred, not failed**: Notifications during quiet hours were permanently marked `failed`. Now set back to `pending` with `next_retry_at` = quiet hours end time.

4. **Stuck processing recovery**: Rows stuck in `processing` status (edge function crash/timeout) are now recovered to `pending` after 5 minutes at the start of each batch.

5. **Per-token invalidation**: `BadDeviceToken` errors previously invalidated ALL tokens for a user. Now only the specific bad token is marked `is_valid = false`.

6. **Local notification daily cap raised**: Cap raised from 4 to 15. Social notification types (shared workouts, challenge updates, reactions) added to the critical bypass list that ignores the cap entirely.

**New infrastructure**:

- **`push_notification_delivery_log` table**: Tracks each step of the pipeline (queued, claimed, sent, failed, deferred). Auto-pruned after 14 days. RLS: users can read own logs.
- **`diagnose_push_notifications()` RPC**: Returns JSON report with token status, preferences, queue stats, recent queue items, and delivery logs. Powers the debug view.
- **`prune_push_delivery_logs()` / `prune_push_notification_queue()`**: Daily cron at 3 AM UTC prunes delivery logs >14 days and queue entries >30 days.
- **Edge function structured logging**: All `console.log` calls now emit JSON with consistent fields: `{event, notification_id, user_id, token_prefix, apns_host, duration_ms, error}`.

**Migration**: `supabase/20260326_push_notification_reliability.sql`
**Edge function**: `supabase/functions/send-push-notification/index.ts` (deploy required)

### 2026-03-26: Bronze League Reshuffle

**Problem**: Bronze members always saw the same people because `get_or_join_weekly_league` maximized friend-overlap when picking groups. Since Bronze is the largest tier (everyone starts here), this made leagues feel stale.

**Solution**: Tier-specific placement strategy in `get_or_join_weekly_league`:

- **Bronze (tier 1)**: Random group assignment. Actively avoids last week's group-mates by finding the user's previous-week `league_members.group_id`, then scoring candidate groups by how many members overlap with that old group. Picks the group with the fewest stale members; exits immediately on zero overlap. If no prior week data, pure `ORDER BY random()`.
- **Silver+ (tier 2–7)**: Unchanged — friend-overlap maximization for social cohesion.

**Key implementation detail**: The `v_prev_group_id` lookup uses `v_week_start - INTERVAL '7 days'` (always exactly 1 week back since `week_start` is always a Monday). The stale-overlap count joins `league_members` on both the candidate group and the previous group by `user_id`.

**Migration**: `supabase/20260326_bronze_league_reshuffle.sql`

### 2026-03-27: CMS Advanced Tools — New Tables & RPCs

**New tables** (all have RLS enabled):
- `feature_flags` — key/enabled/rollout_percentage/platform/min_app_version/metadata. App-facing RPC: `get_active_feature_flags(p_platform, p_app_version)` uses `hashtext(user_id)` for deterministic rollout bucketing.
- `user_reports` — reporter_id/reported_user_id/reason/status/resolution_notes. Users can INSERT and SELECT own. FK cascade on user_profiles.
- `user_suspensions` — user_id/reason/suspended_by/expires_at/lifted_at. Admin-only. App checks via `is_user_suspended()` RPC.
- `push_campaigns` — title/body/segment/status/sent_count. `execute_push_campaign()` resolves segments to user list and inserts into `push_notification_queue`. `estimate_campaign_reach()` counts reachable users for a segment.

**New materialized views** (refreshed daily at 4 AM via `refresh_engagement_data()` pg_cron job):
- `mv_user_engagement_scores` — per-user score 0-100 based on recency, frequency, streak, social, and feature adoption. Buckets: power_user/engaged/casual/at_risk/churned.
- `mv_retention_cohorts` — weekly cohort retention at W1/W2/W4/W8/W12 based on workout activity.
- `mv_onboarding_funnel` — signup → onboarding → first workout → 3rd → 5th → active W1 → active M1.

**New system health RPCs** (admin-only, used by System Health page):
- `admin_get_table_sizes()` — pg_total_relation_size for all public tables
- `admin_get_connection_stats()` — pg_stat_activity summary
- `admin_get_index_health()` — pg_stat_user_indexes (unused index detection)
- `admin_get_rpc_stats()` — pg_stat_user_functions call counts/timing
- `admin_get_push_pipeline_stats()` — push queue + delivery log aggregates

**Enhanced**: `admin_audit_log` gained `details JSONB` and `admin_email TEXT` columns. `logAdminAction()` in route.ts now captures both.

**Migrations**: `supabase/20260327_enhance_audit_log.sql`, `20260327_feature_flags.sql`, `20260327_system_health_rpcs.sql`, `20260327_moderation_system.sql`, `20260327_push_campaigns.sql`, `20260327_engagement_scoring.sql`.

### 2026-03-27: WHOOP Integration

**New table**: `whoop_recovery_data` — daily recovery score, HRV, RHR, SpO2, skin temp, strain, kilojoules, avg/max HR. Keyed by `(user_id, date)`. RLS enabled. FK to `user_profiles` with CASCADE delete.

**Enhanced table**: `sleep_logs` gained nullable columns: `sleep_performance_pct`, `sleep_consistency_pct`, `sleep_efficiency_pct`, `respiratory_rate`, `disturbance_count`, `sleep_debt_milli`, `light_sleep_milli`, `deep_sleep_milli`, `rem_sleep_milli`, `awake_milli`. Populated by WHOOP source; NULL for HealthKit/Fitbit.

**Enhanced table**: `user_profiles` gained `is_whoop_connected BOOLEAN DEFAULT false`.

**Data flow**: `WhoopService.shared` → `HealthDataService.syncWhoopData()` → upserts to `whoop_recovery_data`, `sleep_logs` (source: "whoop"), `cardio_workouts` (source: "whoop"), `daily_activity_summary` (source merge). All writes are auth-guarded.

**WHOOP API base URL (corrected 2026-03-30)**: Data calls use `AppConfig.Whoop.apiBaseUrl` = `https://api.prod.whoop.com/developer` (matches OpenAPI `servers[0].url`). Paths remain `/v2/recovery`, `/v2/cycle`, `/v2/activity/sleep`, `/v2/activity/workout`, `/v2/user/...`. The bare host + `/v2/...` caused **404 `default backend - 404`** for real users (v1.37). `WhoopTokenResponse.expiresIn` is `Int?` with 3600s default when omitted.

**Migration**: `supabase/20260327_whoop_integration.sql`

**Key files**: `WhoopService.swift` (API client + DTOs), `HealthDataService.swift` (sync pipeline), `WhoopSettingsView.swift` (settings UI), `DashboardWhoopWidget.swift` (dashboard widget).

### 2026-03-28: Oura Ring Integration

**New table**: `oura_readiness_data` — daily readiness score, activity score, sleep score, HRV balance, RHR, temperature deviation, SpO2, steps, calories, stress/recovery minutes. Keyed by `(user_id, date)`. RLS enabled. FK to `user_profiles` with CASCADE delete.

**Enhanced table**: `user_profiles` gained `is_oura_connected BOOLEAN DEFAULT false`.

**Data flow**: `OuraService.shared` → `HealthDataService.syncOuraData()` → upserts to `oura_readiness_data`, `sleep_logs` (source: "oura"), `cardio_workouts` (source: "oura"). Sleep durations from Oura are in seconds (not milliseconds like WHOOP) — `syncOuraData()` multiplies by 1000 for `sleep_logs` milli columns.

**Oura API V2**: Base URL `https://api.ouraring.com`. Auth URL `https://cloud.ouraring.com/oauth/authorize`. Token URL `https://api.ouraring.com/oauth/token`. Scopes: `email personal daily heartrate workout spo2`. Rate limit: 5000 req/5min. Paginated responses use `{"data": [...], "next_token": "..."}` (differs from WHOOP's `{"records": [...]}`). Date params use `start_date`/`end_date` (YYYY-MM-DD format), not ISO8601 `start` param.

**Migration**: `supabase/20260328_oura_integration.sql`

**Key files**: `OuraService.swift` (API client + DTOs), `HealthDataService.swift` (sync pipeline), `OuraSettingsView.swift` (settings UI), `DashboardOuraWidget.swift` (dashboard widget).

### 2026-03-28: Weight UUID Type Fix

**Bug**: `WeightTrackingService.logWeight()` used `WeightLogInsert` with `user_id: String` = `userId.uuidString`. The `weight_logs.user_id` column is `uuid` type. PostgreSQL rejected with `operator does not exist: uuid = text`. Fixed: `user_id` field changed to `UUID`, all `.eq()` calls pass `UUID` directly instead of `.uuidString`.

**Rule — Supabase Swift client UUID handling**: When inserting or querying against PostgreSQL `uuid` columns, ALWAYS pass Swift `UUID` directly — never `uuidString`. The Supabase Swift client's `Encodable` conformance serializes `UUID` correctly. Passing a `String` to a `uuid` column causes a type mismatch. This applies to both `.insert()` struct fields and `.eq()` filter values.

### 2026-03-28: Content Moderation System

**New table**: `content_moderation_log` — stores all flagged content attempts (blocked + hidden). No user RLS — admin-only via service role.

**Schema changes**: `is_hidden BOOLEAN DEFAULT FALSE` added to `private_challenge_chat`, `challenge_reactions`, `shared_workouts`, `group_challenges`, `private_challenges`, `community_challenges`, `friend_activity_feed`. Partial indexes on `is_hidden = TRUE`.

**Updated RPCs**: `get_private_challenge_messages` now filters `AND NOT pcc.is_hidden`. `send_private_challenge_message` now has rate limiting (50/hour, 1/2sec burst) and suspension check.

**Admin RPCs**: `get_flagged_content(status, limit, offset)`, `review_flagged_content(log_id, action, notes)`, `get_moderation_stats()` — all `service_role` only.

**Edge Function**: `supabase/functions/moderate-content/index.ts` — two modes: `precheck` (returns flagged/categories) and webhook (updates `is_hidden`). Requires `OPENAI_API_KEY` secret.

**iOS service**: `ContentModerationService.swift` — singleton, calls Edge Function for pre-check. `PrivateChallengeService.sendMessage` now returns `SendMessageResult` enum (`.sent`/`.blocked`/`.error`).

### Private Challenge Cover Photos (2026-03-28)

**Schema**: `cover_image_url TEXT` column added to `private_challenges`. Migration: `supabase/20260328_private_challenge_photos.sql`.

**Storage bucket**: `private-challenge-photos` (public reads, write-RLS to challenge admin). Path: `{challenge_id}/cover.jpg`. Same URL-gated security model as `avatars` bucket — URL is only surfaced through membership-verified RPCs.

**RPC**: `set_private_challenge_cover_image(p_challenge_id, p_cover_image_url)` — SECURITY DEFINER, verifies `created_by = auth.uid()`. Updated RPCs: `get_my_private_challenges`, `get_private_challenge_detail`, `lookup_private_challenge_by_code` now return `cover_image_url`.

**REVERTED (2026-03-29)**: Cover photo feature removed entirely due to 15 RLS crashes in v1.37. The dedicated `private-challenge-photos` bucket and `set_private_challenge_cover_image` RPC were never deployed.

**RE-IMPLEMENTED (2026-03-30) as Challenge Icon Upload**: Uses the existing `avatars` storage bucket at path `challenge_icons/{challengeId}.jpg` instead of a separate bucket. The app does a direct table UPDATE on `private_challenges.cover_image_url` (not via RPC).

**RPC updates (2026-03-30)**: Migration `20260330_add_cover_image_to_rpcs.sql` — both `get_my_private_challenges` and `get_private_challenge_detail` were DROP + RECREATED to add `cover_image_url TEXT` to RETURNS TABLE (positioned after `emoji`) and `pc.cover_image_url` to SELECT (after `pc.emoji`). Function bodies unchanged otherwise. **CRITICAL**: Do NOT drop `cover_image_url` from these RPCs — the Swift models decode it and all challenge icon displays depend on it.

**RLS**: Existing policy "Admin can update their challenges" on `private_challenges` allows `created_by = auth.uid()` UPDATE — used by the direct table write for icon URL. No new policy was needed.

**Storage**: `avatars` bucket, path `challenge_icons/{challengeId}.jpg`, JPEG, upsert:true. Public URL stored in `cover_image_url` column. Security note: storage-level access is any authenticated user (not scoped to challenge admin), but the table UPDATE is RLS-protected to admin only.

**TODO**: `lookup_private_challenge_by_code` RPC also has `PrivateChallengePreview.coverImageUrl` on the Swift model but may not return `cover_image_url` yet. Lower priority — only affects the join-by-code preview screen. Same fix: add `cover_image_url TEXT` to RETURNS TABLE and `pc.cover_image_url` to SELECT after `pc.emoji`.

### 2026-03-29: SQL `#variable_conflict` Rule for RETURNS TABLE Functions

**Rule**: Any PL/pgSQL function with `RETURNS TABLE (column_name TYPE, ...)` where output column names match table column names (e.g., `challenge_id`, `user_id`) MUST include `#variable_conflict use_column` after the `DECLARE` block. Without it, PostgreSQL raises error 42702 "column reference 'X' is ambiguous" because RETURNS TABLE output parameters are PL/pgSQL variables that shadow table columns. The directive tells Postgres to prefer column names over variables. Migration: `20260329_fix_challenge_id_ambiguity.sql`.

### 2026-03-29: WeightGoalUpsert UUID Type Fix

**Rule reinforced**: `WeightTrackingService.setWeightGoal()` had `WeightGoalUpsert.user_id: String` set to `userId.uuidString`. Same bug pattern as the `logWeight()` fix. Changed to `UUID` type. All Supabase insert/upsert structs for `uuid` columns MUST use Swift `UUID` type, never `String`.

### Oura Integration Column — Migration Required (2026-03-28)

**Migration**: `supabase/20260328_oura_integration.sql` adds `is_oura_connected BOOLEAN DEFAULT false` to `user_profiles` and creates `oura_readiness_data` table. Until applied, the `syncAllIntegrationStatuses()` Oura update silently fails (logged at `.debug`). Core integrations (strava/fitbit/apple_health/inbody/whoop) sync independently in a single batch — Oura is attempted separately so a missing column doesn't block the others.

### 2026-03-30: Privacy Settings — Schema & RPC Enforcement

**Migration**: `supabase/20260330_privacy_settings.sql` — adds 6 `BOOLEAN DEFAULT FALSE` columns to `user_profiles`: `privacy_hide_photo`, `privacy_hide_activity`, `privacy_hide_league`, `privacy_hide_contact_sync`, `privacy_hide_search`, `privacy_hide_active_status`.

**Client-side enforcement** (immediate): `PrivacySettingsManager.swift` guards `postWorkoutActivity`, `fetchOrJoinLeague`, `syncContactsToDatabase`. Photo views in `FriendPhotoCache.swift` force initials fallback when `hideProfilePhoto` is on for the current user. **CRITICAL**: `CachedFriendPhoto` uses `@ObservedObject privacyManager` for reactive local check AND `isPhotoUrlEmpty` to respect server-returned null URLs. Both checks must remain — removing the URL check lets stale cached images bypass privacy.

**Server-side enforcement** (defense-in-depth):
- `20260330_privacy_rpc_enforcement.sql`: `search_users`, `get_friend_activity_feed`, `match_contacts_by_phone`, `get_people_you_may_know`, `get_league_leaderboard`, `get_or_join_weekly_league`
- `20260330_privacy_photo_all_rpcs.sql`: `get_active_challenges`, `get_pending_sent_challenges`, `get_active_group_challenges`, `get_received_workouts`, `get_pending_friend_requests`, `get_sent_friend_requests`, `get_community_challenge_leaderboard`, `get_my_community_challenges`, `get_community_challenge_detail`, `get_private_challenge_detail`, `get_my_private_challenges`, `get_friends`, `get_friends_in_community_challenge`
- Pattern in all RPCs: `CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END`
- `20260330_add_cover_image_to_rpcs.sql`: also patched for privacy (private challenge RPCs with `cover_image_url`)

**League privacy enforcement** (`privacy_hide_league`): Both `get_league_leaderboard` and `get_or_join_weekly_league` filter users with `privacy_hide_league = TRUE` out of leaderboard results AND rank calculations using `AND NOT COALESCE(up.privacy_hide_league, FALSE)`. `get_or_join_weekly_league` returns `{"hidden": true}` early if the calling user has this flag set — prevents new league placement. Client-side: `WeeklyLeagueService` observes `PrivacySettingsManager.$hideFromWeeklyLeague` and clears cached standing/hasJoined immediately on toggle. `fetchOrJoinLeague()` handles the `{"hidden": true}` server response gracefully without decode errors.

**Privacy realtime propagation** (unified): `20260330_league_privacy_realtime.sql` creates `privacy_change_events` signal table (columns: `user_id`, `change_type` TEXT, `is_hidden` BOOL, `group_id` UUID nullable) + single Postgres trigger on `user_profiles` for BOTH `privacy_hide_league` and `privacy_hide_activity`. When `privacy_hide_league` changes → one row per active league membership (change_type='league', group_id set). When `privacy_hide_activity` changes → one row (change_type='activity', group_id NULL). `RealtimeService.subscribePrivacyChanges()` listens for INSERT events and routes: 'league' → checks group_id match → `WeeklyLeagueService.fetchFullLeaderboard()`; 'activity' → checks friend list membership → `ActivityFeedService.fetchFeed()`. RLS: all authenticated users can read (broad read needed since activity events have no group scope). Old `league_privacy_events` table dropped by this migration.

**DTO**: `UserProfileDTO` includes all 6 privacy columns with `CodingKeys` mapping.

### 2026-03-31: League Roster Lock (Auto-Placement)

**Problem**: League members trickled in throughout the week whenever they first opened the app. Users saw 3 people on Monday, 5 by Wednesday, etc. — confusing because they expected a fixed roster.

**Solution**: `20260331_league_auto_placement.sql` introduces:

1. **`auto_place_all_league_members()`** — batch function that: (a) calls `process_past_league_weeks()` for promotions/relegations, (b) iterates ALL users with `user_league_tier` rows not yet placed this week, (c) applies same Bronze (random + stale avoidance) and Silver+ (friend overlap) algorithms. Uses `RETURNING id INTO v_new_member_id` to safely handle concurrent insert races with the lazy RPC path.

2. **`pg_cron` job** — `league-weekly-auto-place` runs at `00:15 UTC every Monday` (`15 0 * * 1`). Places everyone at once so rosters are complete by Monday morning.

3. **`get_or_join_weekly_league` — roster lock**: If a user has no membership this week AND `EXTRACT(ISODOW FROM CURRENT_DATE) != 1` (not Monday), returns `{"not_placed": true, "tier_rank": ..., "tier_name": ..., "next_week_start": ...}` instead of creating a membership. On Monday, lazy placement still works as a safety net if cron hasn't run yet.

4. **Penalty for inactivity**: Users who don't open the app are still auto-placed by the cron with 0 points. At week's end they rank at the bottom → likely relegated. This is intentional.

**Swift changes**: `WeeklyLeagueService` has new `@Published var notPlaced: Bool`, `notPlacedTierName: String?`, `notPlacedNextWeek: String?`. `fetchOrJoinLeague()` parses `not_placed` JSON response and sets these. `WeeklyLeagueViews.swift` adds `notPlacedContent` widget showing "League Starts Monday" with tier info.

**Key invariant**: After Monday UTC, the roster for each league group is frozen. No new members can join existing groups until the next week's cron run.

### 2026-04-17: `cardio_workouts.origin_app` — True Third-Party Origin Tracking

**Problem**: When a third-party app (Strava, Nike Run Club, Peloton, Garmin, Zwift, Apple Watch, …) wrote a workout to Apple Health and Fit33 pulled it in, the row was saved with `source='healthkit'` and the dashboard rendered a generic red "Apple Health" heart badge. The original author was lost. A prior skip (`if workout.isFromStrava { continue }`) made it worse: Strava-via-HealthKit runs were dropped entirely when the user had no Strava OAuth connected.

**Migration**: `supabase/20260417_cardio_workouts_origin_app.sql` adds a `TEXT origin_app` column + index `idx_cardio_workouts_user_origin_source (user_id, origin_app, source)`. Best-effort backfill derives the origin from `workout_name` prefix ("Strava Running", "Nike Run Club Run", "Apple Watch Cycling", etc.) for existing rows.

**Semantics (critical)**:
- `source` = **transport** (`strava` | `fitbit` | `whoop` | `oura` | `healthkit` | `fit33`).
- `origin_app` = **canonical author** (`strava` | `nike_run_club` | `peloton` | `garmin` | `zwift` | `apple_watch` | `fitbit` | `whoop` | `oura` | `map_my_run` | `runkeeper` | `adidas_running` | `fit33`).

A Strava run pulled via Apple Health has `source='healthkit'` and `origin_app='strava'`. A Strava run pulled via direct OAuth has `source='strava'` and `origin_app='strava'`.

**Swift mapper**: `Fit33/WorkoutOriginMapper.swift` is the single source of truth. `WorkoutOrigin.from(sourceName:sourceBundle:)` maps HK metadata → enum case. Prefers `bundleIdentifier` (stable across rebrands/localizations), falls back to case-insensitive name match. Apple Watch check runs LAST so third-party apps that happen to write through Apple frameworks aren't mis-classified.

**Dedupe rules (MANDATORY — prevent duplicate rows)**:

1. **HK sync guard** (`HealthDataService.saveAllHealthKitDataToSupabase()`): before saving an HK workout, call `isOAuthConnected(for: workout.origin)`. If true, SKIP the HK save — the OAuth feed will write a richer row directly (route maps, segments, elevation). Currently checks: Strava, Fitbit, WHOOP, Oura. Extensible: add new cases to `WorkoutOrigin.hasFirstPartyOAuth` + `isOAuthConnected(for:)` when adding new OAuth integrations.

2. **OAuth connect backfill** (`HealthDataService.removeHealthKitDuplicates(for:)`): called from `StravaService` / `FitbitService` / `WhoopService` / `OuraService` the moment OAuth succeeds (inline, before `syncActivities`/`syncAllData`). Deletes `cardio_workouts` rows where `user_id=current AND source='healthkit' AND origin_app=<origin>`. Generic by origin — adding OAuth for Garmin/Peloton later only requires one new call site.

**NEVER** re-introduce the `if workout.isFromStrava { continue }` skip in `HealthDataService` — it would permanently drop Strava-via-HK runs for users without OAuth connected.

**Display (generic across all third parties)**: `DashboardWorkoutCards.sourceBadge` and `HealthKitSettingsView.originBadge` both read `cardioWorkout.resolvedOrigin` (DTO computed var) or `workout.origin` (HK sugar) and render the mapper's brand-colored capsule. Brand colors are Strava #FC4C02, Peloton #DF2C35, Garmin #007CC3, Zwift #FC6719, Fitbit #00B0B9, WHOOP black+#E11D48, Oura deep plum, Apple Watch space gray→silver, NRC pure black, MapMyRun #CE0E2D, Runkeeper #002A5C, adidas Running orange. Never hardcode these in views — always go through `WorkoutOriginMapper`.

**DTO changes**: `CardioWorkoutDTO.originApp: String?` added with `origin_app` coding key. `resolvedOrigin` computed var prefers `origin_app`, falls back to `source`, then best-effort-parses `workout_name` for pre-migration rows. `isFromStrava` now checks `source == "strava" || originApp == "strava"`.

**HK DTO**: `HealthKitWorkoutInsert.originApp: String?` added with `origin_app` coding key. Set from `WorkoutOrigin.rawValue` in `HealthDataService.saveHealthKitWorkout` (nil only when origin is `.unknown`).

### 2026-04-20: WHOOP overlap dedup — third dedup layer

**Problem**: Even with the `(user_id, source='whoop', external_id)` guard + the HK/OAuth dedup rules above, users connected to WHOOP could see **two rows per physical session** in Workout History (one labeled "Workout", one "Other" — both with the WHOOP badge, same start time, ~identical duration/calories). Root cause: WHOOP's `/v2/activity/workout` endpoint can return multiple distinct `id`s for a single session — typically an auto-detected generic "Activity" (sport_name=null → `activity_type="other"`) alongside the user-logged specific sport. Different `external_id`s → prior dedup didn't catch them.

**Fix (client-side, `HealthDataService.syncWhoopData`)**: for each incoming WHOOP workout, after the exact `external_id` check, we fetch all user rows whose `started_at` falls within ±2h of the incoming window and compare against any that `resolvedOrigin == .whoop`. If any overlap ≥50% (by shorter-side fraction, so a fully-contained short row still counts as a dup), the one with the higher `cardioQualityScore` wins; the loser is either skipped (if existing wins) or deleted before insert (if incoming wins). Score: +10 specific `activity_type` (not in other/workout/unknown/""), +3 HR, +2 distance, +1 calories, +1 duration.

**One-time cleanup**: `supabase/20260420_cardio_workouts_overlap_dedup.sql` sessionizes existing rows per `(user_id, canonical_origin)` using a running MAX(completed_at) sessionization CTE and deletes losers per overlap cluster using the same scoring. Safe to re-run (idempotent — post-run no same-user/same-origin overlaps remain). Migration emits a NOTICE with residual-overlap count for verification.

**Activity-type mapper**: `mapWhoopSportToActivityType(sportId:sportName:)` now takes `sport_id` first (deterministic) and falls back to fuzzy `sport_name`. Covers the common WHOOP sport ids (0=Running, 1=Cycling, 16=Swim, 45=Weightlifting, 66=Yoga, 123=HIIT, 126=Powerlifting, 228=Strength Trainer, 230=Pilates, …). Reduces the number of records that bucket into "other", which is what the dedup uses to pick the richer row.

**Generalization**: the overlap-dedup rule applies to any OAuth integration, not just WHOOP. If Strava/Fitbit/Oura ever start emitting duplicate records per session, port the same time-overlap check into their sync paths. The SQL migration already handles all origins (whoop/strava/fitbit/oura/fit33) in a single pass.

### 2026-04-20: Three-layer challenge background refresh

**Problem**: Opponents' step/activity numbers could go stale in a 1v1, group, or private challenge because Apple Health data is device-locked — if the opponent doesn't open the app and iOS's opportunistic `BGAppRefreshTask` never fires, nothing syncs and we see yesterday's numbers. Manual inputs (hydration, protein) were already near-realtime via `log_*_challenge_progress` RPCs + `RealtimeService` subscriptions; this fix targets the auto-tracked (HealthKit-backed) gap.

**Solution layers** (each one is a safety net for the one above):

1. **On-device hardening** — `Fit33/BackgroundChallengeSyncService.swift`
   - Registers TWO BGTask identifiers now: `com.gofit.app.challengeSync` (BGAppRefreshTask, ~15 min windows) and `com.gofit.app.challengeSyncProcessing` (BGProcessingTask, ~5 min, typically overnight while charging). Both identifiers live in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
   - Throttle is now **per-source** (`steps`, `active_energy`, `distance`, `exercise_time`) instead of a single global 10-min timer. A step-event flood no longer starves an active-energy event. Keys: `bg_challenge_last_sync_<source>` in UserDefaults.
   - BGTask expiration handlers cancel in-flight work, mark the task failed, AND re-schedule the next cycle. Previously an expiry left the chain dead.

2. **Silent-push opponent wake** — `supabase/functions/wake-challenge-opponents/` + `Fit33/SilentPushHandler.swift` + `Fit33/ChallengeOpponentWakeService.swift`
   - Edge function accepts `{source: "foreground" | "background_sync" | "cron"}`. Foreground/background_sync modes require a user JWT and resolve the caller's opponents across `challenge_participants` + `private_challenge_members`. Cron mode requires service-role and resolves ALL active-challenge participants (each device wakes itself, then every opponent sees the fresh numbers via realtime).
   - Rate limit: `silent_push_wake_log` table (service-role-only RLS), 15-min window per `user_id`. Enforced in TypeScript before APNs call. Apple's silent-push budget is ~2-3/hr/device, so 15 min is the safe floor.
   - APNs payload is `{aps: {content-available: 1}, type: "challenge_wake"}` with headers `apns-push-type: background`, `apns-priority: 5`, `apns-expiration: +1h`. **Never use priority 10 on a silent push — Apple will drop it.**
   - Triggered from: (a) `Fit33App.swift` scenePhase `.active` (after foreground sync), (b) `BackgroundChallengeSyncService.performChallengeSyncInBackground` (at the end, fire-and-forget), (c) `pg_cron` `wake-stale-challenge-opponents` every 30 min.
   - Device-side debounce: 60s in `ChallengeOpponentWakeService` on top of the server-side 15-min throttle.
   - Requires `Info.plist` → `UIBackgroundModes` contains `remote-notification` (added in this migration — without it iOS drops silent pushes before they reach `didReceiveRemoteNotification`).

3. **Server-side OAuth pull** — **NOT IMPLEMENTED (blocked by architecture).** Original plan: pg_cron every 15 min pulls WHOOP/Oura/Fitbit activity via OAuth APIs directly, bypassing the opponent's device. Blocker: OAuth access/refresh tokens are stored in iOS Keychain only (`WhoopService.swift`, `OuraService.swift`, `FitbitService.swift`) — Supabase has no `user_oauth_tokens` table, only `user_profiles.is_<provider>_connected` booleans. Implementing server-side pull would require a new encrypted-at-rest token store + re-auth migration path for existing users + KMS/vault secret management. Tracked as a follow-up; Phase 2 (silent push) covers ~95% of the case because WHOOP/Oura/Fitbit already bridge into HealthKit on-device for most users.

**Configuration required** (once per environment):
- `internal_config` must have `supabase_url`, `service_role_key`, `anon_key` (already seeded by `20260324_push_notification_cron.sql`).
- Edge function secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY` (same set used by `send-push-notification`).
- Deploy: `supabase functions deploy wake-challenge-opponents`.

**Silent-push handler contract**: `SilentPushHandler.handle(userInfo:completion:)` MUST call `completion(_:)` within ~30s or iOS drops our future background-delivery budget. Implementation self-caps at 25s via a timeout Task. Routes on the top-level `type` string; unknown types return `.noData`. Adding a new silent-push type = add a new `case` in `SilentPushHandler.handle` — do NOT overload `challenge_wake`.

**Do not add**:
- A second, shorter server throttle window — Apple APNs will drop us.
- A silent-push path that goes through `push_notification_queue` — that table is for user-visible alerts with retry logic; silent pushes are fire-and-forget opportunistic wakes. The two paths must stay separate.
- Direct inserts into `silent_push_wake_log` from client code — RLS denies it; only the edge function (service role) writes there.
